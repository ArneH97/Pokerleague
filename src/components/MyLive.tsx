'use client'

import { useState } from 'react'
import Link from 'next/link'
import { createClient } from '@/lib/supabase/client'
import { useT } from '@/lib/i18n/context'
import { formatMoney } from '@/lib/types'

/**
 * De avonden waar je nu in zit, bovenaan je startpagina.
 *
 * Zolang je speelt is dit het enige op deze pagina dat je op dat moment
 * interesseert, dus staat het boven je historie. Zit je nergens aan tafel,
 * dan staat er niets — een lege kaart met "geen lopende tornooien" is ruis op
 * driehonderdvierenzestig dagen per jaar.
 *
 * Het invoerveld voor je stapel is het echte nut. De chipcount op het
 * zaalscherm komt van iemand die twintig stapels na elkaar intikt; laat je de
 * speler zijn eigen aantal ingeven, dan klopt het vaker en heeft de floor er
 * minder werk aan. De database bewaakt dat je alleen je eigen aantal wijzigt
 * en alleen zolang je actief bent — zie `guard_player_chip_update` in 0005.
 * Hier staat dus geen enkele controle; als de server het weigert, zeggen we
 * gewoon wat hij zei.
 */

export interface LiveRow {
  tournament_id: string
  tournament_player_id: string
  name: string
  club_slug: string
  club_name: string
  logo_url: string | null
  primary_color: string | null
  currency: string
  status: string
  clock: string
  level_idx: number
  my_chips: number
  my_chips_by: string | null
  players_left: number
  entries: number
  avg_stack: number
  prize_pool_cents: number
}

export function MyLive({ rows }: { rows: LiveRow[] }) {
  const t = useT()
  if (rows.length === 0) return null

  return (
    <section>
      <h2 className="mb-2 text-xs uppercase tracking-[0.22em] text-[var(--text-faint)]">
        {t('live.title')}
      </h2>
      <ul className="space-y-3">
        {rows.map((r) => (
          <Row key={r.tournament_player_id} r={r} />
        ))}
      </ul>
    </section>
  )
}

function Row({ r }: { r: LiveRow }) {
  const t = useT()
  const [chips, setChips] = useState(String(r.my_chips ?? 0))
  const [saved, setSaved] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const accent = r.primary_color ?? 'var(--brand)'
  const mine = Number.parseInt(chips.replace(/\D/g, ''), 10)
  const avg = r.avg_stack || 1
  // Hoe je ervoor staat in één getal. Grote stapels praten in big blinds, maar
  // die kennen we hier niet — het veelvoud van het gemiddelde wel, en dat zegt
  // aan een pokertafel evenveel.
  const ratio = Number.isFinite(mine) && avg > 0 ? mine / avg : null

  async function save() {
    const value = Number.parseInt(chips.replace(/\D/g, ''), 10)
    if (!Number.isFinite(value) || value < 0) return
    setBusy(true)
    setError(null)
    const { error: err } = await createClient()
      .from('tournament_players')
      .update({ chip_count: value })
      .eq('id', r.tournament_player_id)
    setBusy(false)
    if (err) { setError(err.message); return }
    setSaved(true)
    setTimeout(() => setSaved(false), 1800)
  }

  return (
    <li
      className="overflow-hidden rounded-[var(--radius)] border bg-[var(--surface)]"
      style={{ borderColor: `color-mix(in oklab, ${accent} 40%, transparent)` }}
    >
      <div className="flex items-center gap-3 px-4 py-3">
        {r.logo_url && (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={r.logo_url} alt="" className="size-9 shrink-0 rounded-lg object-contain" />
        )}
        <span className="min-w-0 flex-1">
          <span className="flex items-center gap-2">
            <span
              className="inline-block size-1.5 shrink-0 rounded-full"
              style={{ background: accent, animation: r.clock === 'running' ? 'pulse 2s infinite' : undefined }}
            />
            <span className="truncate font-medium">{r.name}</span>
          </span>
          <span className="block truncate text-xs text-[var(--text-faint)]">
            {r.club_name} · {t('live.level')} {r.level_idx + 1}
            {r.clock === 'paused' ? ` · ${t('live.paused')}` : ''}
          </span>
        </span>
        <Link
          href={`/c/${r.club_slug}/live/${r.tournament_id}`}
          className="shrink-0 text-sm underline-offset-4 hover:underline"
          style={{ color: accent }}
        >
          {t('live.follow')} →
        </Link>
      </div>

      <div className="grid grid-cols-3 gap-px border-t border-[var(--line)] bg-[var(--line)]">
        <Cell label={t('clock.playersLeft')} value={`${r.players_left}`} sub={`${t('common.of')} ${r.entries}`} />
        <Cell label={t('live.avgStack')} value={r.avg_stack.toLocaleString('nl-BE')} />
        <Cell
          label={t('clock.prizePool')}
          value={formatMoney(Number(r.prize_pool_cents), r.currency)}
        />
      </div>

      {/* ------------------------------------------------------ eigen stapel */}
      <div className="flex flex-wrap items-end gap-3 border-t border-[var(--line)] px-4 py-3">
        <label className="min-w-0 flex-1">
          <span className="mb-1 block text-[0.65rem] uppercase tracking-[0.14em] text-[var(--text-faint)]">
            {t('live.myStack')}
          </span>
          <input
            inputMode="numeric"
            value={chips}
            onChange={(e) => setChips(e.target.value)}
            onFocus={(e) => e.target.select()}
            className="tnum w-full rounded-lg border border-[var(--line-strong)] bg-[var(--surface-2)] px-3 py-2.5 text-lg outline-none focus:border-[var(--brand)]"
          />
        </label>
        <button
          type="button"
          disabled={busy}
          onClick={() => void save()}
          className="rounded-lg px-4 py-2.5 text-sm font-medium transition disabled:opacity-45"
          style={{ background: accent, color: 'var(--on-brand)' }}
        >
          {busy ? t('common.busy') : saved ? t('common.saved') : t('common.save')}
        </button>

        {ratio !== null && (
          <span className="tnum w-full text-xs text-[var(--text-faint)] sm:w-auto">
            {ratio.toFixed(1)}× {t('live.ofAverage')}
          </span>
        )}
      </div>

      {error && (
        <p className="border-t border-[var(--line)] px-4 py-2 text-xs text-[var(--danger)]">{error}</p>
      )}
    </li>
  )
}

function Cell({ label, value, sub }: { label: string; value: string; sub?: string }) {
  return (
    <span className="block bg-[var(--surface)] px-3 py-2.5 text-center">
      <span className="block text-[0.6rem] uppercase tracking-[0.12em] text-[var(--text-faint)]">
        {label}
      </span>
      <span className="tnum mt-0.5 block font-semibold">{value}</span>
      {sub && <span className="block text-[0.65rem] text-[var(--text-faint)]">{sub}</span>}
    </span>
  )
}
