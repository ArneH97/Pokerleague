'use client'

import { useCallback, useEffect, useMemo, useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { computeDeal, evenSplitCents } from '@/lib/tournament/deal'
import { formatMoney } from '@/lib/types'
import { useT } from '@/lib/i18n/context'

/**
 * De deal aan de finaletafel.
 *
 * Twee dingen die de vorm bepalen.
 *
 * Eerst tellen, dan rekenen. De chipcounts in het systeem zijn een schatting:
 * spelers geven hun stapel door wanneer het hun uitkomt, en aan de
 * finaletafel klopt dat allang niet meer. Zodra er over geld gepraat wordt
 * moet de floor opnieuw tellen. De controle daarop is niet "exact gelijk"
 * maar 95 tot 105 procent van wat er in spel hoort te zijn — chip-ups en
 * verdwenen fiches zorgen altijd voor wat drift, en een systeem dat op één
 * fiche na gelijk eist krijgt gegarandeerd verzonnen getallen.
 *
 * En drie voorstellen, niet één. ICM houdt rekening met de prijzenladder,
 * chipchop deelt naar rato van de stapels, even split geeft iedereen
 * evenveel. De chipleader wil chipchop, de kortste stapel wil even split, en
 * ICM ligt ertussen. Alle drie tegelijk op het zaalscherm kunnen zetten is
 * eerlijker dan zelf beslissen welke de juiste is.
 *
 * Even split is het enige voorstel dat geen telling nodig heeft — daar komen
 * geen chips aan te pas. Dat is bewust apart bereikbaar: als de tafel dat
 * meteen afspreekt hoeft niemand nog te tellen.
 */

interface Seat {
  id: string
  name: string
  chips: number
}

type Col = 'icm' | 'chop' | 'even'

export function DealPanel({
  tournamentId,
  currency,
  seats,
  expectedChips,
  onClose,
}: {
  tournamentId: string
  currency: string
  /** Wie er nog zit, met hun laatst bekende chipcount als vertrekpunt. */
  seats: Seat[]
  /** Hoeveel chips er in spel horen te zijn: inkopen × startstack, plus addons. */
  expectedChips: number
  onClose: () => void
}) {
  const supabase = useMemo(() => createClient(), [])
  const t = useT()

  const [prizes, setPrizes] = useState<number[] | null>(null)
  const [step, setStep] = useState<'count' | 'propose'>('count')
  const [counts, setCounts] = useState<Record<string, number>>(
    () => Object.fromEntries(seats.map((s) => [s.id, s.chips])),
  )
  const [counted, setCounted] = useState(false)
  const [amounts, setAmounts] = useState<Record<string, number>>({})
  const [show, setShow] = useState<Record<Col, boolean>>({ icm: true, chop: true, even: true })
  const [openDeal, setOpenDeal] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [confirming, setConfirming] = useState(false)

  const load = useCallback(async () => {
    const [ladder, open] = await Promise.all([
      supabase.rpc('tournament_prizes', { p_tournament_id: tournamentId }),
      supabase.from('tournament_deals').select('id')
        .eq('tournament_id', tournamentId).eq('status', 'proposed')
        .maybeSingle<{ id: string }>(),
    ])
    if (ladder.error) setError(ladder.error.message)
    const rows = (ladder.data ?? []) as unknown as { place: number; amount_cents: number }[]
    setPrizes(rows.sort((a, b) => a.place - b.place).map((r) => r.amount_cents))
    setOpenDeal(open.data != null)
  }, [supabase, tournamentId])

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    void load()
  }, [load])

  const n = seats.length

  // Wat er nog te verdelen valt zijn de bovenste N plaatsen. De plaatsen
  // daaronder zijn al uitbetaald aan wie eerder afviel; die horen hier niet
  // meer bij.
  const remaining = prizes ? prizes.slice(0, Math.min(n, prizes.length)) : []
  const poolCents = remaining.reduce((a, b) => a + b, 0)
  const paidOutCents = prizes
    ? prizes.slice(Math.min(n, prizes.length)).reduce((a, b) => a + b, 0)
    : 0

  const totalCounted = seats.reduce((sum, s) => sum + (counts[s.id] ?? 0), 0)
  const ratio = expectedChips > 0 ? totalCounted / expectedChips : 0
  const countOk = expectedChips > 0 ? ratio >= 0.95 && ratio <= 1.05 : totalCounted > 0

  const result = useMemo(
    () => computeDeal(seats.map((s) => ({ ...s, chips: counts[s.id] ?? 0 })), remaining),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [seats, counts, prizes],
  )

  // De chips gaan mee zodat een restant van een euro bij de grootste stapel
  // terechtkomt en niet bij wie toevallig bovenaan de lijst staat.
  const even = useMemo(
    () => evenSplitCents(n, remaining, seats.map((s) => counts[s.id] ?? 0)),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [n, prizes, seats, counts])

  /**
   * Een voorstel aan- of uitzetten.
   *
   * Staat het al op de beamer, dan gaat de wijziging er meteen naartoe. Eerst
   * klikken en dan nog eens op "bewaren" moeten is precies het soort stap dat
   * je aan een finaletafel vergeet — en dan staat de zaal naar een voorstel te
   * kijken dat de floor al ingetrokken dacht te hebben.
   */
  function toggle(c: Col) {
    const next = { ...show, [c]: !show[c] }
    setShow(next)
    if (openDeal && (next.icm || next.chop || next.even)) {
      setBusy(true)
      void saveDeal(next).finally(() => setBusy(false))
    }
  }

  /** Hoeveel voorstellen er nu op het zaalscherm zouden komen. */
  const shownCount = (['icm', 'chop', 'even'] as Col[])
    .filter((c) => show[c] && (c === 'even' || counted)).length

  /** Wat een bepaald voorstel voor deze zitplaats uitkeert. */
  function valueOf(col: Col, i: number): number {
    const s = result.shares[i]
    if (!s) return 0
    return col === 'icm' ? (s.icmCents ?? 0) : col === 'chop' ? s.chopCents : even[i] ?? 0
  }

  function pick(col: Col) {
    const next: Record<string, number> = {}
    result.shares.forEach((s, i) => { next[s.id] = valueOf(col, i) })
    setAmounts(next)
  }

  /**
   * Welk voorstel staat er nu in de akkoord-kolom?
   *
   * De floor kan een kolom overnemen of zelf bedragen typen, en bij het
   * afsluiten moet vastliggen wélke afspraak de tafel gemaakt heeft. Daarom
   * leiden we dat af uit de bedragen zelf in plaats van te onthouden waar
   * ooit op geklikt is — dan klopt het ook nog als er achteraf iets is
   * bijgesteld.
   */
  const agreedCol: Col | 'custom' =
    (['icm', 'chop', 'even'] as Col[]).find((col) =>
      result.shares.length > 0 &&
      result.shares.every((s, i) => (amounts[s.id] ?? 0) === valueOf(col, i)),
    ) ?? 'custom'

  async function saveStacks() {
    setBusy(true)
    setError(null)
    for (const s of seats) {
      const { error: err } = await supabase
        .from('tournament_players')
        .update({ chip_count: counts[s.id] ?? 0 })
        .eq('id', s.id)
      if (err) { setError(err.message); setBusy(false); return }
    }
    setCounted(true)
    setStep('propose')
    pick('icm')
    setBusy(false)
  }

  function evenOnly() {
    const next: Record<string, number> = {}
    seats.forEach((s, i) => { next[s.id] = even[i] ?? 0 })
    setAmounts(next)
    setShow({ icm: false, chop: false, even: true })
    setStep('propose')
  }

  /**
   * Het voorstel wegschrijven. Geeft terug of het gelukt is, zodat afsluiten
   * eerst de akkoord-bedragen kan vastzetten en pas daarna de deal bevestigt
   * — anders sluit de database af op wat er stond vóór de laatste keuze.
   */
  async function saveDeal(showOverride?: Record<Col, boolean>): Promise<boolean> {
    setError(null)
    // De keuze kan meekomen als argument: React heeft de nieuwe state nog
    // niet doorgevoerd op het moment dat een knop hem meteen wil bewaren.
    const vis = showOverride ?? show
    const shares = seats.map((s, i) => {
      const share = result.shares[i]
      return {
        tournament_player_id: s.id,
        name: s.name,
        chips: counted ? (counts[s.id] ?? 0) : 0,
        icm_cents: vis.icm && counted ? share.icmCents : null,
        chop_cents: vis.chop && counted ? share.chopCents : null,
        even_cents: vis.even ? (even[i] ?? 0) : null,
        agreed_cents: amounts[s.id] ?? 0,
      }
    })
    const method = vis.icm && vis.chop && vis.even ? 'all'
      : vis.icm ? 'icm' : vis.chop ? 'chipchop' : 'even'

    const { error: err } = await supabase.rpc('deal_propose', {
      p_tournament_id: tournamentId,
      p_method: method,
      p_shares: shares,
    })
    if (err) { setError(err.message); return false }
    setOpenDeal(true)
    return true
  }

  async function project() {
    setBusy(true)
    await saveDeal()
    setBusy(false)
  }

  async function cancel() {
    setBusy(true)
    const { error: err } = await supabase.rpc('deal_cancel', { p_tournament_id: tournamentId })
    if (err) setError(err.message)
    else setOpenDeal(false)
    setBusy(false)
  }

  async function accept() {
    setBusy(true)
    // Eerst de gekozen bedragen vastleggen, dan pas afsluiten.
    if (!(await saveDeal())) { setBusy(false); return }
    const { error: err } = await supabase.rpc('deal_accept', { p_tournament_id: tournamentId })
    if (err) { setError(err.message); setBusy(false); return }
    setBusy(false)
    onClose()
  }

  const total = Object.values(amounts).reduce((a, b) => a + b, 0)
  const sumOk = total === poolCents

  if (n < 2) {
    return <Panel title={t('deal.title')} onClose={onClose}>
      <p className="text-sm text-[var(--text-muted)]">{t('deal.needTwo')}</p>
    </Panel>
  }
  if (prizes === null) {
    return <Panel title={t('deal.title')} onClose={onClose}>
      <p className="text-sm text-[var(--text-muted)]">{t('common.loading')}</p>
    </Panel>
  }

  // -------------------------------------------------------------- tellen ---
  if (step === 'count') {
    return (
      <Panel title={`${t('deal.title')} · ${t('deal.step1')}`} onClose={onClose}>
        <p className="text-sm leading-relaxed text-[var(--text-muted)]">{t('deal.countHint')}</p>

        <ul className="mt-3 divide-y divide-[var(--line)] overflow-hidden rounded-lg border border-[var(--line)]">
          {seats.map((s) => (
            <li key={s.id} className="flex items-center gap-3 px-3 py-2">
              <span className="min-w-0 flex-1 truncate font-medium">{s.name}</span>
              <input
                inputMode="numeric"
                aria-label={s.name}
                value={counts[s.id] ?? 0}
                onChange={(e) => {
                  const v = Math.max(0, Number.parseInt(e.target.value.replace(/\D/g, ''), 10) || 0)
                  setCounts((c) => ({ ...c, [s.id]: v }))
                }}
                className="tnum w-32 rounded-lg border border-[var(--line-strong)] bg-[var(--surface-2)] px-3 py-2 text-right outline-none focus:border-[var(--brand)]"
              />
            </li>
          ))}
        </ul>

        <div className="mt-3 flex flex-wrap items-baseline justify-between gap-2 text-sm">
          <p className="text-[var(--text-muted)]">
            {t('deal.counted')}{' '}
            <span className="tnum font-semibold text-[var(--text)]">
              {totalCounted.toLocaleString('nl-BE')}
            </span>
            <span className="mx-2 text-[var(--text-faint)]">/</span>
            {t('deal.expected')}{' '}
            <span className="tnum">{expectedChips.toLocaleString('nl-BE')}</span>
          </p>
          <p
            className="tnum font-medium"
            style={{ color: countOk ? 'var(--ok)' : 'var(--warn)' }}
          >
            {(ratio * 100).toFixed(1)}% · {countOk ? t('deal.countOk') : t('deal.countOff')}
          </p>
        </div>
        <p className="mt-1 text-xs text-[var(--text-faint)]">{t('deal.countTolerance')}</p>

        {error && <p className="mt-2 text-sm text-[var(--danger)]">{error}</p>}

        <div className="mt-4 flex flex-wrap gap-2">
          <button
            type="button"
            disabled={busy || !countOk}
            onClick={() => void saveStacks()}
            className="rounded-lg bg-[var(--brand)] px-4 py-2 text-sm font-medium text-[var(--on-brand)] transition hover:brightness-110 disabled:opacity-40"
          >
            {t('deal.toProposals')}
          </button>
          {/* Even split heeft geen telling nodig: daar komen geen chips aan
              te pas. Als de tafel dat meteen afspreekt scheelt dat een hoop
              gedoe met fiches. */}
          <button
            type="button"
            disabled={busy}
            onClick={evenOnly}
            className="rounded-lg border border-[var(--line-strong)] px-4 py-2 text-sm transition hover:bg-[var(--surface-hover)]"
          >
            {t('deal.evenOnly')}
          </button>
        </div>
      </Panel>
    )
  }

  // --------------------------------------------------------- voorstellen ---
  return (
    <Panel title={`${t('deal.title')} · ${t('deal.step2')}`} onClose={onClose}>
      <div className="flex flex-wrap items-baseline justify-between gap-2 text-sm">
        <p className="text-[var(--text-muted)]">
          {t('deal.pool')}{' '}
          <span className="tnum font-semibold text-[var(--text)]">
            {formatMoney(poolCents, currency)}
          </span>
        </p>
        {paidOutCents > 0 && (
          <p className="text-xs text-[var(--text-faint)]">
            {t('deal.paidOut')}: <span className="tnum">{formatMoney(paidOutCents, currency)}</span>
          </p>
        )}
      </div>

      {!counted && (
        <p className="mt-2 rounded-lg border border-[color-mix(in_oklab,var(--warn)_35%,transparent)] bg-[color-mix(in_oklab,var(--warn)_8%,transparent)] px-3 py-2 text-xs text-[var(--warn)]">
          {t('deal.needCount')}
        </p>
      )}

      {/* -------------------------------------------------- welke tonen we
          Drie knoppen en geen vinkjes. Dit is de keuze die de floor het
          vaakst maakt aan de finaletafel — alle drie tonen zodat de tafel het
          verschil ziet, of net één omdat er anders eindeloos onderhandeld
          wordt — en die keuze hoort niet weggestopt te zitten in
          aankruisvakjes die je pas ziet als je ernaar zoekt. Wat aanstaat is
          wat er op de beamer komt; dat moet je in één oogopslag zien. */}
      <div className="mt-4 rounded-xl border border-[var(--line-strong)] bg-[var(--surface-2)] p-3">
        <div className="flex flex-wrap items-baseline justify-between gap-2">
          <p className="text-xs uppercase tracking-widest text-[var(--text-faint)]">
            {t('deal.project')}
          </p>
          <p className="text-xs text-[var(--text-faint)]">
            {shownCount === 0 ? t('deal.projectNone') : `${shownCount} ${t('deal.projectCount')}`}
          </p>
        </div>

        <div className="mt-2 grid gap-2 sm:grid-cols-3">
          {(['icm', 'chop', 'even'] as const).map((c) => {
            const available = c === 'even' || counted
            const on = show[c] && available
            return (
              <button
                key={c}
                type="button"
                disabled={!available}
                onClick={() => toggle(c)}
                aria-pressed={on}
                className={`rounded-lg border px-3 py-2.5 text-left transition disabled:opacity-30 ${
                  on
                    ? 'border-[var(--brand)] bg-[color-mix(in_oklab,var(--brand)_16%,transparent)]'
                    : 'border-[var(--line-strong)] hover:bg-[var(--surface-hover)]'
                }`}
              >
                <span className="flex items-center gap-2 text-sm font-medium">
                  <span aria-hidden className={on ? 'text-[var(--brand)]' : 'text-[var(--text-faint)]'}>
                    {on ? '☑' : '☐'}
                  </span>
                  {c === 'icm' ? t('deal.icm') : c === 'chop' ? t('deal.chop') : t('deal.even')}
                </span>
                <span className="mt-0.5 block tabular-nums text-xs text-[var(--text-muted)]">
                  {available
                    ? seats.map((_, i) => formatMoney(valueOf(c, i), currency)).join(' · ')
                    : t('deal.needCountShort')}
                </span>
              </button>
            )
          })}
        </div>

        <p className="mt-2 text-xs text-[var(--text-faint)]">{t('deal.projectHint')}</p>
      </div>

      {/* -------------------------------------------------------- de tabel */}
      <div className="mt-3 overflow-x-auto rounded-lg border border-[var(--line)]">
        <table className="w-full min-w-[34rem] text-sm">
          <thead>
            <tr className="border-b border-[var(--line)] text-left text-xs uppercase tracking-widest text-[var(--text-faint)]">
              <th className="px-3 py-2 font-medium">{t('members.player')}</th>
              {counted && <th className="px-3 py-2 text-right font-medium">{t('deal.chips')}</th>}
              {counted && (
                <th className="px-3 py-2 text-right font-medium">
                  <button type="button" onClick={() => pick('icm')} className="hover:underline">
                    {t('deal.icm')}
                  </button>
                </th>
              )}
              {counted && (
                <th className="px-3 py-2 text-right font-medium">
                  <button type="button" onClick={() => pick('chop')} className="hover:underline">
                    {t('deal.chop')}
                  </button>
                </th>
              )}
              <th className="px-3 py-2 text-right font-medium">
                <button type="button" onClick={() => pick('even')} className="hover:underline">
                  {t('deal.even')}
                </button>
              </th>
              <th className="w-32 px-3 py-2 text-right font-medium">{t('deal.agreed')}</th>
            </tr>
          </thead>
          <tbody>
            {result.shares.map((s, i) => (
              <tr key={s.id} className="border-b border-[var(--line)] last:border-0">
                <td className="px-3 py-2 font-medium">{s.name}</td>
                {counted && (
                  <td className="tnum px-3 py-2 text-right text-[var(--text-muted)]">
                    {s.chips.toLocaleString('nl-BE')}
                  </td>
                )}
                {counted && (
                  <td className="tnum px-3 py-2 text-right text-[var(--text-faint)]">
                    {s.icmCents === null ? '—' : formatMoney(s.icmCents, currency)}
                  </td>
                )}
                {counted && (
                  <td className="tnum px-3 py-2 text-right text-[var(--text-faint)]">
                    {formatMoney(s.chopCents, currency)}
                  </td>
                )}
                <td className="tnum px-3 py-2 text-right text-[var(--text-faint)]">
                  {formatMoney(even[i] ?? 0, currency)}
                </td>
                <td className="px-3 py-2">
                  <input
                    inputMode="decimal"
                    aria-label={s.name}
                    value={((amounts[s.id] ?? 0) / 100).toFixed(2)}
                    onChange={(e) => {
                      const cents = Math.max(0, Math.round(Number(e.target.value.replace(',', '.')) * 100) || 0)
                      setAmounts((a) => ({ ...a, [s.id]: cents }))
                    }}
                    className="tnum w-full rounded-lg border border-[var(--line-strong)] bg-[var(--surface-2)] px-2.5 py-1.5 text-right text-sm outline-none focus:border-[var(--brand)]"
                  />
                </td>
              </tr>
            ))}
          </tbody>
          <tfoot>
            <tr className="bg-[var(--surface-2)]">
              <td className="px-3 py-2 text-[var(--text-muted)]" colSpan={counted ? 4 : 1}>
                {t('deal.total')}
              </td>
              <td className="tnum px-3 py-2 text-right text-[var(--text-faint)]">
                {formatMoney(even.reduce((a, b) => a + b, 0), currency)}
              </td>
              <td
                className="tnum px-3 py-2 text-right font-semibold"
                style={{ color: sumOk ? undefined : 'var(--warn)' }}
              >
                {formatMoney(total, currency)}
              </td>
            </tr>
          </tfoot>
        </table>
      </div>

      {!sumOk && (
        <p className="mt-2 text-sm text-[var(--warn)]">
          {t('deal.mismatch')} {t('deal.difference')}:{' '}
          <span className="tnum">{formatMoney(total - poolCents, currency)}</span>
        </p>
      )}
      {error && <p className="mt-2 text-sm text-[var(--danger)]">{error}</p>}

      <div className="mt-4 flex flex-wrap items-center gap-2">
        <button
          type="button"
          onClick={() => setStep('count')}
          className="rounded-lg border border-[var(--line-strong)] px-3 py-2 text-sm transition hover:bg-[var(--surface-hover)]"
        >
          {t('deal.backToCount')}
        </button>

        <button
          type="button"
          disabled={busy || (!show.icm && !show.chop && !show.even)}
          onClick={() => void project()}
          className="rounded-lg bg-[var(--brand)] px-4 py-2 text-sm font-medium text-[var(--on-brand)] transition hover:brightness-110 disabled:opacity-40"
        >
          {openDeal ? t('common.save') : t('deal.show')}
        </button>

        {openDeal && (
          <>
            <span className="inline-flex items-center gap-2 rounded-full bg-[color-mix(in_oklab,var(--ok)_14%,transparent)] px-3 py-1.5 text-xs text-[var(--ok)]">
              <span className="size-1.5 animate-pulse rounded-full bg-[var(--ok)]" />
              {t('deal.showing')}
            </span>
            <button
              type="button"
              disabled={busy}
              onClick={() => void cancel()}
              className="rounded-lg border border-[var(--line-strong)] px-3 py-2 text-sm transition hover:bg-[var(--surface-hover)]"
            >
              {t('deal.take')}
            </button>
          </>
        )}

        <span className="flex-1" />

        {openDeal && !confirming && (
          <button
            type="button"
            disabled={busy || !sumOk}
            onClick={() => setConfirming(true)}
            className="rounded-lg border border-[var(--brand)] px-4 py-2 text-sm font-medium text-[var(--brand)] transition hover:bg-[color-mix(in_oklab,var(--brand)_12%,transparent)] disabled:opacity-40"
          >
            {t('deal.accept')}
          </button>
        )}
      </div>

      {/* Afsluiten legt geld vast, dus hier hoort geen kale ja/nee-vraag.
          Er staan drie voorstellen op het zaalscherm; welk daarvan de tafel
          heeft afgesproken weet alleen de floor. Dat wordt hier gekozen, en
          pas daarna gaat het tornooi dicht. */}
      {openDeal && confirming && (
        <div className="mt-4 rounded-xl border border-[var(--brand)] bg-[color-mix(in_oklab,var(--brand)_7%,transparent)] p-4">
          <p className="text-sm font-medium">{t('deal.whichAgreed')}</p>
          <p className="mt-1 text-xs text-[var(--text-muted)]">{t('deal.whichHint')}</p>

          <div className="mt-3 grid gap-2 sm:grid-cols-3">
            {(['icm', 'chop', 'even'] as Col[]).map((col) => {
              const available = col === 'even' ? true : counted && (col !== 'icm' || result.icmAvailable)
              const active = agreedCol === col
              return (
                <button
                  key={col}
                  type="button"
                  disabled={busy || !available}
                  onClick={() => pick(col)}
                  className={`rounded-lg border px-3 py-2 text-left transition disabled:opacity-30 ${
                    active
                      ? 'border-[var(--brand)] bg-[color-mix(in_oklab,var(--brand)_16%,transparent)]'
                      : 'border-[var(--line-strong)] hover:bg-[var(--surface-hover)]'
                  }`}
                >
                  <span className="block text-sm font-medium">
                    {active ? '● ' : '○ '}
                    {col === 'icm' ? t('deal.icm') : col === 'chop' ? t('deal.chop') : t('deal.even')}
                  </span>
                  <span className="mt-0.5 block tabular-nums text-xs text-[var(--text-muted)]">
                    {seats.map((_, i) => formatMoney(valueOf(col, i), currency)).join(' · ')}
                  </span>
                </button>
              )
            })}
          </div>

          {agreedCol === 'custom' && (
            <p className="mt-3 rounded-lg border border-[var(--line-strong)] px-3 py-2 text-xs text-[var(--text-muted)]">
              ● {t('deal.custom')} — {seats.map((s) => formatMoney(amounts[s.id] ?? 0, currency)).join(' · ')}
            </p>
          )}

          <div className="mt-4 flex flex-wrap items-center gap-2">
            <button
              type="button"
              disabled={busy || !sumOk}
              onClick={() => void accept()}
              className="rounded-lg bg-[var(--brand)] px-4 py-2 text-sm font-medium text-[var(--on-brand)] transition hover:brightness-110 disabled:opacity-40"
            >
              {t('deal.confirmAgreed')}
              {' — '}
              {agreedCol === 'icm' ? t('deal.icm')
                : agreedCol === 'chop' ? t('deal.chop')
                : agreedCol === 'even' ? t('deal.even')
                : t('deal.custom')}
            </button>
            <button
              type="button"
              disabled={busy}
              onClick={() => setConfirming(false)}
              className="rounded-lg border border-[var(--line-strong)] px-3 py-2 text-sm"
            >
              {t('common.cancel')}
            </button>
            {!sumOk && <span className="text-xs text-[var(--danger)]">{t('deal.mismatch')}</span>}
          </div>
        </div>
      )}
    </Panel>
  )
}

function Panel({
  title, children, onClose,
}: { title: string; children: React.ReactNode; onClose: () => void }) {
  const t = useT()
  return (
    <section className="rounded-xl border border-[var(--brand)] bg-[var(--surface)] p-4">
      <div className="mb-2 flex items-center justify-between">
        <h2 className="text-sm uppercase tracking-widest text-[var(--text-faint)]">{title}</h2>
        <button
          type="button"
          onClick={onClose}
          className="rounded-lg border border-[var(--line-strong)] px-3 py-1.5 text-sm transition hover:bg-[var(--surface-hover)]"
        >
          {t('deal.close')}
        </button>
      </div>
      {children}
    </section>
  )
}
