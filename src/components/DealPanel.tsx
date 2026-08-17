'use client'

import { useEffect, useMemo, useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { computeDeal, type DealSeat } from '@/lib/tournament/deal'
import { formatMoney } from '@/lib/types'
import { useT } from '@/lib/i18n/context'

/**
 * De deal aan de finaletafel, bediend vanaf het floor-scherm.
 *
 * Waarom ICM en chipchop naast elkaar en niet één van de twee: dat verschil
 * ís de onderhandeling. Chipchop deelt naar rato van de chips; ICM houdt
 * rekening met de prijzenladder, want je kan maar één keer eerste worden en
 * een dubbel zo grote stapel is dus geen dubbel zo grote verwachting. De
 * chipleader wil chipchop, de kortste stapel wil ICM, en de waarheid ligt
 * ertussen. Beide tonen en de tafel laten kiezen is eerlijker dan zelf
 * beslissen welke methode "juist" is.
 *
 * De floor kan de bedragen ook met de hand zetten — een tafel spreekt vaak
 * iets af dat op geen van beide kolommen staat. Het enige dat de software
 * bewaakt is dat de som klopt met wat er te verdelen valt.
 */

interface Seat extends DealSeat {
  tpId: string
}

export function DealPanel({
  tournamentId,
  currency,
  seats,
  onClose,
}: {
  tournamentId: string
  currency: string
  /** Wie er nog zit, met hun chipcount. */
  seats: Seat[]
  onClose: () => void
}) {
  const supabase = useMemo(() => createClient(), [])
  const t = useT()

  const [prizes, setPrizes] = useState<number[] | null>(null)
  const [amounts, setAmounts] = useState<Record<string, number>>({})
  const [method, setMethod] = useState<'icm' | 'chipchop' | 'custom'>('icm')
  const [openDealId, setOpenDealId] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [confirming, setConfirming] = useState(false)

  // De prijzenladder van dit tornooi. Alleen de bovenste N plaatsen tellen,
  // met N het aantal spelers dat nog zit: de rest is al uitbetaald.
  useEffect(() => {
    let dood = false
    void (async () => {
      const { data, error: err } = await supabase.rpc('tournament_prizes', {
        p_tournament_id: tournamentId,
      })
      if (dood) return
      if (err) { setError(err.message); return }
      const rows = (data ?? []) as unknown as { place: number; amount_cents: number }[]
      setPrizes(rows.sort((a, b) => a.place - b.place).map((r) => r.amount_cents))
    })()
    return () => { dood = true }
  }, [supabase, tournamentId])

  // Staat er al een voorstel op het scherm?
  useEffect(() => {
    let dood = false
    void (async () => {
      const { data } = await supabase
        .from('tournament_deals')
        .select('id')
        .eq('tournament_id', tournamentId)
        .eq('status', 'proposed')
        .maybeSingle<{ id: string }>()
      if (!dood) setOpenDealId(data?.id ?? null)
    })()
    return () => { dood = true }
  }, [supabase, tournamentId])

  const result = useMemo(
    () => (prizes ? computeDeal(seats, prizes) : null),
    [seats, prizes],
  )

  // Bij het wisselen van methode nemen we die kolom over als voorstel.
  useEffect(() => {
    if (!result || method === 'custom') return
    const next: Record<string, number> = {}
    for (const s of result.shares) {
      next[s.id] = method === 'icm' ? (s.icmCents ?? s.chopCents) : s.chopCents
    }
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setAmounts(next)
  }, [result, method])

  if (seats.length < 2) {
    return (
      <Panel onClose={onClose} title={t('deal.title')}>
        <p className="text-sm text-[var(--text-muted)]">{t('deal.needTwo')}</p>
      </Panel>
    )
  }

  if (!result) {
    return (
      <Panel onClose={onClose} title={t('deal.title')}>
        <p className="text-sm text-[var(--text-muted)]">{t('common.loading')}</p>
      </Panel>
    )
  }

  const total = Object.values(amounts).reduce((a, b) => a + b, 0)
  const diff = total - result.poolCents
  const ok = diff === 0

  async function propose() {
    setBusy(true)
    setError(null)
    const shares = result!.shares.map((s) => ({
      tournament_player_id: s.id,
      name: s.name,
      chips: s.chips,
      icm_cents: s.icmCents,
      chop_cents: s.chopCents,
      agreed_cents: amounts[s.id] ?? 0,
    }))
    const { data, error: err } = await supabase.rpc('deal_propose', {
      p_tournament_id: tournamentId,
      p_method: method,
      p_shares: shares,
    })
    if (err) setError(err.message)
    else setOpenDealId(typeof data === 'string' ? data : 'open')
    setBusy(false)
  }

  async function cancel() {
    setBusy(true)
    const { error: err } = await supabase.rpc('deal_cancel', { p_tournament_id: tournamentId })
    if (err) setError(err.message)
    else setOpenDealId(null)
    setBusy(false)
  }

  async function accept() {
    setBusy(true)
    setError(null)
    const { error: err } = await supabase.rpc('deal_accept', { p_tournament_id: tournamentId })
    if (err) { setError(err.message); setBusy(false); return }
    setBusy(false)
    onClose()
  }

  return (
    <Panel onClose={onClose} title={t('deal.title')}>
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <p className="text-sm text-[var(--text-muted)]">
          {t('deal.pool')}{' '}
          <span className="tnum font-semibold text-[var(--text)]">
            {formatMoney(result.poolCents, currency)}
          </span>
        </p>
        <p className="text-xs text-[var(--text-faint)]">
          {t('deal.remaining')}: {Math.min(seats.length, prizes?.length ?? 0)}
        </p>
      </div>

      {/* ------------------------------------------------------- methodekeuze */}
      <div className="mt-3 flex flex-wrap gap-1.5">
        {(['icm', 'chipchop', 'custom'] as const).map((m) => (
          <button
            key={m}
            type="button"
            disabled={m === 'icm' && !result.icmAvailable}
            onClick={() => setMethod(m)}
            className={`rounded-lg border px-3 py-1.5 text-sm transition disabled:opacity-40 ${
              method === m
                ? 'border-[var(--brand)] bg-[color-mix(in_oklab,var(--brand)_16%,transparent)]'
                : 'border-[var(--line-strong)] hover:bg-[var(--surface-hover)]'
            }`}
          >
            {m === 'icm' ? t('deal.icm') : m === 'chipchop' ? t('deal.chop') : t('deal.custom')}
          </button>
        ))}
      </div>
      <p className="mt-1.5 text-xs text-[var(--text-faint)]">
        {method === 'icm' ? t('deal.icmWhat')
          : method === 'chipchop' ? t('deal.chopWhat')
          : ''}
        {!result.icmAvailable && ` ${result.icmUnavailableReason ?? t('deal.icmUnavailable')}`}
      </p>

      {/* ------------------------------------------------------------ tabel */}
      <div className="mt-3 overflow-x-auto rounded-lg border border-[var(--line)]">
        <table className="w-full min-w-[30rem] text-sm">
          <thead>
            <tr className="border-b border-[var(--line)] text-left text-xs uppercase tracking-widest text-[var(--text-faint)]">
              <th className="px-3 py-2 font-medium">{t('members.player')}</th>
              <th className="px-3 py-2 text-right font-medium">{t('deal.chips')}</th>
              <th className="px-3 py-2 text-right font-medium">{t('deal.icm')}</th>
              <th className="px-3 py-2 text-right font-medium">{t('deal.chop')}</th>
              <th className="w-32 px-3 py-2 text-right font-medium">{t('deal.total')}</th>
            </tr>
          </thead>
          <tbody>
            {result.shares.map((s) => (
              <tr key={s.id} className="border-b border-[var(--line)] last:border-0">
                <td className="px-3 py-2 font-medium">{s.name}</td>
                <td className="tnum px-3 py-2 text-right text-[var(--text-muted)]">
                  {s.chips.toLocaleString('nl-BE')}
                </td>
                <td
                  className="tnum px-3 py-2 text-right"
                  style={method === 'icm' ? { color: 'var(--brand)' } : { color: 'var(--text-faint)' }}
                >
                  {s.icmCents === null ? '—' : formatMoney(s.icmCents, currency)}
                </td>
                <td
                  className="tnum px-3 py-2 text-right"
                  style={method === 'chipchop' ? { color: 'var(--brand)' } : { color: 'var(--text-faint)' }}
                >
                  {formatMoney(s.chopCents, currency)}
                </td>
                <td className="px-3 py-2">
                  <input
                    inputMode="decimal"
                    aria-label={s.name}
                    value={((amounts[s.id] ?? 0) / 100).toFixed(2)}
                    onChange={(e) => {
                      const cents = Math.max(0, Math.round(Number(e.target.value.replace(',', '.')) * 100))
                      setMethod('custom')
                      setAmounts((a) => ({ ...a, [s.id]: Number.isFinite(cents) ? cents : 0 }))
                    }}
                    className="tnum w-full rounded-lg border border-[var(--line-strong)] bg-[var(--surface-2)] px-2.5 py-1.5 text-right text-sm outline-none focus:border-[var(--brand)]"
                  />
                </td>
              </tr>
            ))}
          </tbody>
          <tfoot>
            <tr className="bg-[var(--surface-2)]">
              <td className="px-3 py-2 text-[var(--text-muted)]" colSpan={4}>
                {t('deal.total')}
              </td>
              <td
                className="tnum px-3 py-2 text-right font-semibold"
                style={{ color: ok ? undefined : 'var(--warn)' }}
              >
                {formatMoney(total, currency)}
              </td>
            </tr>
          </tfoot>
        </table>
      </div>

      {!ok && (
        <p className="mt-2 text-sm text-[var(--warn)]">
          {t('deal.mismatch')} {t('deal.difference')}:{' '}
          <span className="tnum">{formatMoney(diff, currency)}</span>
        </p>
      )}

      {error && <p className="mt-2 text-sm text-[var(--danger)]">{error}</p>}

      {/* ---------------------------------------------------------- knoppen */}
      <div className="mt-4 flex flex-wrap items-center gap-2">
        {openDealId === null ? (
          <button
            type="button"
            disabled={busy || !ok}
            onClick={() => void propose()}
            className="rounded-lg bg-[var(--brand)] px-4 py-2 text-sm font-medium text-[var(--on-brand)] transition hover:brightness-110 disabled:opacity-40"
          >
            {t('deal.show')}
          </button>
        ) : (
          <>
            <span className="inline-flex items-center gap-2 rounded-full bg-[color-mix(in_oklab,var(--ok)_14%,transparent)] px-3 py-1.5 text-xs text-[var(--ok)]">
              <span className="size-1.5 animate-pulse rounded-full bg-[var(--ok)]" />
              {t('deal.showing')}
            </span>
            <button
              type="button"
              disabled={busy || !ok}
              onClick={() => void propose()}
              className="rounded-lg border border-[var(--line-strong)] px-3 py-2 text-sm transition hover:bg-[var(--surface-hover)] disabled:opacity-40"
            >
              {t('common.save')}
            </button>
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

        {/* Afsluiten met een deal is het einde van de avond en niet terug te
            draaien; vandaar de tussenstap. */}
        {openDealId !== null && (
          confirming ? (
            <>
              <button
                type="button"
                disabled={busy}
                onClick={() => void accept()}
                className="rounded-lg bg-[var(--brand)] px-4 py-2 text-sm font-medium text-[var(--on-brand)] transition hover:brightness-110 disabled:opacity-40"
              >
                {t('players.finishYes')}
              </button>
              <button
                type="button"
                onClick={() => setConfirming(false)}
                className="rounded-lg border border-[var(--line-strong)] px-3 py-2 text-sm"
              >
                {t('common.cancel')}
              </button>
            </>
          ) : (
            <button
              type="button"
              disabled={busy || !ok}
              onClick={() => setConfirming(true)}
              className="rounded-lg border border-[var(--brand)] px-4 py-2 text-sm font-medium text-[var(--brand)] transition hover:bg-[color-mix(in_oklab,var(--brand)_12%,transparent)] disabled:opacity-40"
            >
              {t('deal.accept')}
            </button>
          )
        )}
      </div>
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
