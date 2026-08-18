'use client'

import { useCallback, useEffect, useMemo, useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { formatMoney } from '@/lib/types'
import { useT } from '@/lib/i18n/context'
import { dbMessage } from '@/lib/dbMessage'

/**
 * De prijzenverdeling vastleggen tijdens de avond.
 *
 * Het sjabloon van de club bepaalt standaard hoeveel plaatsen betaald worden.
 * Dat werkt zolang het veld voorspelbaar is, en breekt zodra er dertig man
 * zit en de floor er zes wil betalen. Vandaar dit scherm: kies het aantal
 * plaatsen, bekijk het voorstel, pas elk bedrag naar smaak aan, en zet het
 * vast.
 *
 * Pas ná het sluiten van de inkopen, want daarvoor verandert de pot bij elke
 * speler die binnenkomt — en een bord dat om half elf nog verspringt is erger
 * dan geen bord. De knop staat er wel al, met uitleg, want soms weet de floor
 * op voorhand al wat hij wil.
 *
 * De bubbel is geen aparte pot maar een plaats erbij. Wie net naast het geld
 * valt krijgt zijn inleg terug, en dat gaat van de bovenkant af. Anders zou
 * de som niet meer kloppen met wat er in kas zit.
 */

interface Row { place: number; amount_cents: number }

export function PayoutPanel({
  tournamentId,
  currency,
  buyinCents,
  potCents,
  entries,
  entriesClosed,
  onClose,
  onChanged,
}: {
  tournamentId: string
  currency: string
  buyinCents: number
  potCents: number
  entries: number
  /** Zijn de inkopen gesloten? Zo niet, dan waarschuwen we eerst. */
  entriesClosed: boolean
  onClose: () => void
  onChanged: () => void
}) {
  const supabase = useMemo(() => createClient(), [])
  const t = useT()

  const [places, setPlaces] = useState(3)
  const [bubble, setBubble] = useState(false)
  const [bubbleCents, setBubbleCents] = useState(buyinCents)
  const [rows, setRows] = useState<Row[]>([])
  const [fixed, setFixed] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [proceed, setProceed] = useState(false)

  // Wat er nu geldt: de override van de floor, of het sjabloon van de club.
  const loadCurrent = useCallback(async () => {
    const [ladder, tour] = await Promise.all([
      supabase.rpc('tournament_prizes', { p_tournament_id: tournamentId }),
      supabase.from('tournaments').select('payout_override,paid_places')
        .eq('id', tournamentId)
        .maybeSingle<{ payout_override: number[] | null; paid_places: number | null }>(),
    ])
    const list = ((ladder.data ?? []) as unknown as Row[]).sort((a, b) => a.place - b.place)
    setRows(list)
    setFixed(tour.data?.payout_override != null)
    if (list.length > 0) setPlaces(tour.data?.paid_places ?? list.length)
  }, [supabase, tournamentId])

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    void loadCurrent()
  }, [loadCurrent])

  async function suggest(nPlaces = places, withBubble = bubble, cents = bubbleCents) {
    setBusy(true)
    setError(null)
    const { data, error: err } = await supabase.rpc('suggest_payouts', {
      p_tournament_id: tournamentId,
      p_places: nPlaces,
      p_bubble_cents: withBubble ? cents : 0,
    })
    if (err) setError(dbMessage(err, t))
    else setRows(((data ?? []) as unknown as Row[]).sort((a, b) => a.place - b.place))
    setBusy(false)
  }

  async function save() {
    setBusy(true)
    setError(null)
    const { error: err } = await supabase.rpc('set_payouts', {
      p_tournament_id: tournamentId,
      p_amounts: rows.sort((a, b) => a.place - b.place).map((r) => r.amount_cents),
    })
    if (err) setError(dbMessage(err, t))
    else { setFixed(true); onChanged() }
    setBusy(false)
  }

  async function reset() {
    setBusy(true)
    const { error: err } = await supabase.rpc('clear_payouts', { p_tournament_id: tournamentId })
    if (err) setError(dbMessage(err, t))
    else { await loadCurrent(); setFixed(false); onChanged() }
    setBusy(false)
  }

  const total = rows.reduce((n, r) => n + r.amount_cents, 0)
  const ok = total === potCents
  const maxPlaces = Math.max(1, Math.min(entries, 20))

  if (!entriesClosed && !proceed) {
    return (
      <Panel title={t('payout.title')} onClose={onClose}>
        <p className="text-sm font-medium text-[var(--warn)]">{t('payout.tooEarly')}</p>
        <p className="mt-1 text-sm text-[var(--text-muted)]">{t('payout.tooEarlyBody')}</p>
        <button
          type="button"
          onClick={() => setProceed(true)}
          className="mt-3 rounded-lg border border-[var(--line-strong)] px-3 py-2 text-sm transition hover:bg-[var(--surface-hover)]"
        >
          {t('payout.openAnyway')}
        </button>
      </Panel>
    )
  }

  return (
    <Panel title={t('payout.title')} onClose={onClose}>
      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="text-sm text-[var(--text-muted)]">
          {t('payout.pot')}{' '}
          <span className="tnum font-semibold text-[var(--text)]">
            {formatMoney(potCents, currency)}
          </span>
        </p>
        <span
          className={`rounded-full px-2.5 py-1 text-xs ${
            fixed
              ? 'bg-[color-mix(in_oklab,var(--ok)_14%,transparent)] text-[var(--ok)]'
              : 'bg-[var(--surface-2)] text-[var(--text-faint)]'
          }`}
        >
          {fixed ? t('payout.fixed') : t('payout.template')}
        </span>
      </div>

      {/* ------------------------------------------------------------ keuzes */}
      <div className="mt-3 flex flex-wrap items-end gap-4">
        {/* Plus en min in plaats van een tikveld: op een laptop aan de deur
            is één klik sneller dan een getal selecteren en overtypen, en het
            aantal kan nooit onder de één zakken. Elke aanpassing rekent
            meteen door, zodat je het effect ziet in plaats van het te moeten
            opvragen. */}
        <div>
          <span className="mb-1 block text-xs text-[var(--text-muted)]">{t('payout.places')}</span>
          <div className="flex items-center gap-1">
            <Step
              label="−"
              disabled={busy || places <= 1}
              onClick={() => { const v = Math.max(1, places - 1); setPlaces(v); void suggest(v) }}
            />
            <span className="tnum w-12 text-center text-lg font-semibold">{places}</span>
            <Step
              label="+"
              disabled={busy || places >= maxPlaces}
              onClick={() => { const v = Math.min(maxPlaces, places + 1); setPlaces(v); void suggest(v) }}
            />
          </div>
        </div>

        <label className="flex items-center gap-2 pb-2">
          <input
            type="checkbox"
            checked={bubble}
            onChange={(e) => { setBubble(e.target.checked); void suggest(places, e.target.checked) }}
            className="size-4"
          />
          <span className="text-sm">{t('payout.bubble')}</span>
        </label>

        {bubble && (
          <label className="block">
            <span className="mb-1 block text-xs text-[var(--text-muted)]">
              {t('payout.bubbleAmount')}
            </span>
            <input
              inputMode="decimal"
              value={(bubbleCents / 100).toFixed(2)}
              onChange={(e) => setBubbleCents(
                Math.max(0, Math.round(Number(e.target.value.replace(',', '.')) * 100) || 0))}
              className="tnum w-28 rounded-lg border border-[var(--line-strong)] bg-[var(--surface-2)] px-3 py-2 text-right outline-none focus:border-[var(--brand)]"
            />
          </label>
        )}

        <button
          type="button"
          disabled={busy}
          onClick={() => void suggest()}
          className="rounded-lg border border-[var(--line-strong)] px-3 py-2 text-sm transition hover:bg-[var(--surface-hover)] disabled:opacity-45"
        >
          {t('payout.suggest')}
        </button>
      </div>

      {bubble && (
        <p className="mt-1.5 text-xs text-[var(--text-faint)]">{t('payout.bubbleHint')}</p>
      )}

      {/* ------------------------------------------------------------ tabel */}
      {rows.length > 0 && (
        <div className="mt-3 overflow-x-auto rounded-lg border border-[var(--line)]">
          <table className="w-full min-w-[22rem] text-sm">
            <thead>
              <tr className="border-b border-[var(--line)] text-left text-xs uppercase tracking-widest text-[var(--text-faint)]">
                <th className="px-3 py-2 font-medium">{t('payout.place')}</th>
                <th className="px-3 py-2 text-right font-medium">%</th>
                <th className="w-36 px-3 py-2 text-right font-medium">{t('payout.amount')}</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r, i) => (
                <tr key={r.place} className="border-b border-[var(--line)] last:border-0">
                  <td className="px-3 py-2">
                    <span
                      className="tnum font-semibold"
                      style={r.place <= 3 ? { color: 'var(--brand)' } : undefined}
                    >
                      {r.place}
                    </span>
                    {bubble && i === rows.length - 1 && rows.length > 1 && (
                      <span className="ml-2 text-xs text-[var(--text-faint)]">
                        {t('payout.bubble')}
                      </span>
                    )}
                  </td>
                  <td className="tnum px-3 py-2 text-right text-[var(--text-faint)]">
                    {potCents > 0 ? `${((r.amount_cents / potCents) * 100).toFixed(1)}%` : '—'}
                  </td>
                  <td className="px-3 py-2">
                    <input
                      inputMode="decimal"
                      aria-label={`${t('payout.place')} ${r.place}`}
                      value={(r.amount_cents / 100).toFixed(2)}
                      onChange={(e) => {
                        const cents = Math.max(0, Math.round(Number(e.target.value.replace(',', '.')) * 100) || 0)
                        setRows((list) => list.map((x) =>
                          x.place === r.place ? { ...x, amount_cents: cents } : x))
                      }}
                      className="tnum w-full rounded-lg border border-[var(--line-strong)] bg-[var(--surface-2)] px-2.5 py-1.5 text-right text-sm outline-none focus:border-[var(--brand)]"
                    />
                  </td>
                </tr>
              ))}
            </tbody>
            <tfoot>
              <tr className="bg-[var(--surface-2)]">
                <td className="px-3 py-2 text-[var(--text-muted)]" colSpan={2}>
                  {t('payout.total')}
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
      )}

      {!ok && rows.length > 0 && (
        <p className="mt-2 text-sm text-[var(--warn)]">{t('payout.mismatch')}</p>
      )}
      {error && <p className="mt-2 text-sm text-[var(--danger)]">{error}</p>}

      <div className="mt-4 flex flex-wrap gap-2">
        <button
          type="button"
          disabled={busy || !ok || rows.length === 0}
          onClick={() => void save()}
          className="rounded-lg bg-[var(--brand)] px-4 py-2 text-sm font-medium text-[var(--on-brand)] transition hover:brightness-110 disabled:opacity-40"
        >
          {t('payout.save')}
        </button>
        {fixed && (
          <button
            type="button"
            disabled={busy}
            onClick={() => void reset()}
            className="rounded-lg border border-[var(--line-strong)] px-3 py-2 text-sm transition hover:bg-[var(--surface-hover)]"
          >
            {t('payout.reset')}
          </button>
        )}
      </div>
    </Panel>
  )
}

function Step({
  label, onClick, disabled,
}: { label: string; onClick: () => void; disabled?: boolean }) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      aria-label={label}
      className="size-10 rounded-lg border border-[var(--line-strong)] text-lg leading-none transition hover:bg-[var(--surface-hover)] disabled:cursor-not-allowed disabled:opacity-35"
    >
      {label}
    </button>
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
