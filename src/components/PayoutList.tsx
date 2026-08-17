'use client'

import { formatMoney } from '@/lib/types'
import type { PayoutRow } from '@/lib/usePayouts'
import { useT } from '@/lib/i18n/context'

/**
 * De lijst waarmee de floor aan de kassa staat.
 *
 * Eén regel per naam, met de plaats en het bedrag, en een vinkje om af te
 * strepen. Dat vinkje is geen luxe: als er zes mensen tegelijk hun geld komen
 * halen is "wie heb ik al gehad" precies de vraag die je niet uit het hoofd
 * wil beantwoorden. Het staat in de database, dus het overleeft een refresh
 * en een tweede telefoon aan de kassa.
 *
 * Afgestreepte namen blijven staan, in grijs. Ze wegmoffelen leest prettiger
 * maar dan kan je niet meer nakijken of je iemand vergeten bent.
 */
export function PayoutList({
  rows, currency, totalCents, openCents, busy, onMarkPaid,
}: {
  rows: PayoutRow[]
  currency: string
  totalCents: number
  openCents: number
  busy?: boolean
  onMarkPaid: (tpId: string, paid: boolean) => void
}) {
  const t = useT()
  if (rows.length === 0) return null

  return (
    <section className="rounded-xl border border-[var(--line-strong)] bg-[var(--surface)] p-4">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <h3 className="text-sm uppercase tracking-widest text-[var(--text-faint)]">
          {t('payoutlist.title')}
        </h3>
        <p className="tnum text-sm text-[var(--text-muted)]">
          {openCents > 0
            ? `${t('payoutlist.remaining')} ${formatMoney(openCents, currency)} ${t('payoutlist.of')} ${formatMoney(totalCents, currency)}`
            : t('payoutlist.allPaid')}
        </p>
      </div>

      <ul className="mt-3 divide-y divide-[var(--line)]">
        {rows.map((r) => {
          const paid = r.paidAt !== null
          return (
            <li
              key={r.tournamentPlayerId}
              className={`flex flex-wrap items-center gap-3 py-2.5 ${paid ? 'opacity-45' : ''}`}
            >
              <span className="tnum w-10 shrink-0 text-sm text-[var(--text-faint)]">
                {r.place}.
              </span>
              <span className={`min-w-0 flex-1 truncate text-base ${paid ? 'line-through' : 'font-medium'}`}>
                {r.name}
              </span>
              <span className="tnum shrink-0 text-lg font-semibold">
                {formatMoney(r.amountCents, currency)}
              </span>
              <button
                type="button"
                disabled={busy}
                onClick={() => onMarkPaid(r.tournamentPlayerId, !paid)}
                className={`shrink-0 rounded-lg px-3 py-1.5 text-sm transition disabled:opacity-40 ${
                  paid
                    ? 'border border-[var(--line-strong)] hover:bg-[var(--surface-hover)]'
                    : 'bg-[var(--ok)] text-black hover:brightness-110'
                }`}
              >
                {paid ? t('payoutlist.undoPaid') : t('payoutlist.markPaid')}
              </button>
            </li>
          )
        })}
      </ul>
    </section>
  )
}

/**
 * De melding bij een uitschakeling in het geld.
 *
 * Dit is het moment waarop het misgaat: de bubbel spat, iedereen praat door
 * elkaar, en niemand kijkt naar de prijzenladder. Daarom springt het bedrag
 * hier in beeld op het moment zelf, met de naam erbij, en blijft het staan
 * tot de floor het wegklikt of meteen afstreept.
 */
export function InTheMoneyNotice({
  row, currency, busy, onMarkPaid, onDismiss,
}: {
  row: PayoutRow
  currency: string
  busy?: boolean
  onMarkPaid: () => void
  onDismiss: () => void
}) {
  const t = useT()
  return (
    <div className="rounded-xl border border-[var(--ok)] bg-[color-mix(in_oklab,var(--ok)_12%,transparent)] p-4">
      <p className="text-xs uppercase tracking-widest text-[var(--ok)]">
        {t('payoutlist.inTheMoney')}
      </p>
      <p className="mt-1 flex flex-wrap items-baseline gap-x-3 gap-y-1">
        <span className="text-xl font-semibold">{row.name}</span>
        <span className="text-sm text-[var(--text-muted)]">
          {t('payoutlist.place')} {row.place}
        </span>
        <span className="tnum text-2xl font-bold text-[var(--ok)]">
          {formatMoney(row.amountCents, currency)}
        </span>
      </p>
      <div className="mt-3 flex flex-wrap gap-2">
        <button
          type="button"
          disabled={busy}
          onClick={onMarkPaid}
          className="rounded-lg bg-[var(--ok)] px-4 py-2 text-sm font-medium text-black transition hover:brightness-110 disabled:opacity-40"
        >
          {t('payoutlist.markPaid')}
        </button>
        <button
          type="button"
          onClick={onDismiss}
          className="rounded-lg border border-[var(--line-strong)] px-3 py-2 text-sm transition hover:bg-[var(--surface-hover)]"
        >
          {t('payoutlist.later')}
        </button>
      </div>
    </div>
  )
}
