'use client'

import { useState } from 'react'
import Link from 'next/link'
import { createClient } from '@/lib/supabase/client'
import { useT, useLocale } from '@/lib/i18n/context'
import type { Locale } from '@/lib/i18n/dictionaries'
import { formatMoney } from '@/lib/types'
import { dbMessage } from '@/lib/dbMessage'

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
  level_label: string | null
  is_break: boolean
  small_blind: number
  big_blind: number
  ante: number
  next_big_blind: number
  my_chips: number
  my_chips_by: string | null
  my_chips_at: string | null
  counts_frozen: boolean
  players_left: number
  entries: number
  avg_stack: number
  chips_in_play: number
  my_rank: number | null
  ranked_players: number
  paid_places: number
  prize_pool_cents: number
}

/**
 * Een rangtelwoord in de taal van de speler.
 *
 * "7de van 9" leest als een plaats, "7 van 9" als een breuk. Het scheelt één
 * lettergreep en het is het verschil tussen een stand en een verhouding.
 *
 * Per taal een eigen regel, want ze verschillen: het Nederlands neemt -ste bij
 * 1, 8 en alles vanaf 20, het Frans kent alleen 1er apart, en het Engels heeft
 * zijn eigen uitzonderingen op elf tot dertien.
 */
function rangtelwoord(n: number, locale: Locale): string {
  if (locale === 'fr') return n === 1 ? '1er' : `${n}e`
  if (locale === 'en') {
    const rest100 = n % 100
    if (rest100 >= 11 && rest100 <= 13) return `${n}th`
    return `${n}${['th', 'st', 'nd', 'rd'][n % 10] ?? 'th'}`
  }
  return `${n}${n === 1 || n === 8 || n >= 20 ? 'ste' : 'de'}`
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
  const locale = useLocale()
  const [chips, setChips] = useState(String(r.my_chips ?? 0))
  const [saved, setSaved] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const accent = r.primary_color ?? 'var(--brand)'
  const mine = Number.parseInt(chips.replace(/\D/g, ''), 10)
  const avg = r.avg_stack || 1
  const ratio = Number.isFinite(mine) && avg > 0 ? mine / avg : null

  // Alles in big blinds. Tijdens een pauze rekent de server al met het
  // eerstvolgende speelniveau, dus hier hoeft daar niets meer voor te gebeuren.
  const bb = r.big_blind
  // Zonder chips valt er niets in big blinds uit te drukken. Dan liever een
  // streepje dan "0 BB · push or fold" bij iemand die simpelweg nog niets
  // doorgaf.
  const mijnBb = bb > 0 && Number.isFinite(mine) && mine > 0 ? Math.round(mine / bb) : null
  const gemBb = bb > 0 ? Math.round(avg / bb) : 0

  // Vier woorden voor waar je staat. Grenzen zoals ze aan tafel gebruikt
  // worden: onder de tien big blinds is er weinig te spelen, boven de veertig
  // heb je alle tijd.
  const diepte = mijnBb === null ? null
    : mijnBb < 10 ? 'live.critical' as const
    : mijnBb < 20 ? 'live.short' as const
    : mijnBb < 40 ? 'live.comfortable' as const
    : 'live.deep' as const
  const diepteKleur = mijnBb === null ? 'var(--text)'
    : mijnBb < 10 ? 'var(--danger)'
    : mijnBb < 20 ? 'var(--warn)'
    : accent

  // Hoe ver het geld nog is. De bubbel is het moment waarop er nog één moet
  // afvallen, en dat is precies wanneer mensen anders gaan spelen.
  const totGeld = r.players_left - r.paid_places
  const geld = r.paid_places === 0 ? undefined
    : totGeld <= 0 ? t('live.inTheMoney')
    : totGeld === 1 ? t('live.onTheBubble')
    : t('live.toTheMoney').replace('{n}', String(totGeld))

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
    if (err) { setError(dbMessage(err, t)); return }
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

      {/* ------------------------------------------------- hoe sta ik ervoor
          Big blinds bovenaan en chips eronder, want aan tafel wordt de vraag
          in big blinds gesteld. 54.000 zegt niets; 27 BB zegt "je hebt nog
          ruimte" en 9 BB zegt "je moet iets gaan doen". */}
      <div className="border-t border-[var(--line)] px-4 py-3">
        <div className="flex flex-wrap items-end justify-between gap-x-4 gap-y-2">
          <span>
            <span className="block text-[0.65rem] uppercase tracking-[0.14em] text-[var(--text-faint)]">
              {t('live.myStackBb')}
            </span>
            {mijnBb === null ? (
              <span className="mt-0.5 block text-lg text-[var(--text-faint)]">—</span>
            ) : (
              <span className="flex items-baseline gap-1.5">
                <span className="tnum text-3xl font-semibold leading-none" style={{ color: diepteKleur }}>
                  {mijnBb}
                </span>
                <span className="text-sm text-[var(--text-faint)]">{t('live.bb')}</span>
                {diepte && (
                  <span className="text-xs" style={{ color: diepteKleur }}>· {t(diepte)}</span>
                )}
              </span>
            )}
            <span className="tnum mt-0.5 block text-xs text-[var(--text-faint)]">
              {Number(r.my_chips ?? 0).toLocaleString('nl-BE')}
            </span>
          </span>

          <span className="text-right">
            <span className="block text-[0.65rem] uppercase tracking-[0.14em] text-[var(--text-faint)]">
              {r.is_break ? t('live.onBreak') : t('live.blinds')}
            </span>
            <span className="tnum mt-0.5 block text-lg font-medium">
              {r.small_blind.toLocaleString('nl-BE')} / {r.big_blind.toLocaleString('nl-BE')}
              {r.ante > 0 && <span className="text-sm text-[var(--text-faint)]"> ({r.ante.toLocaleString('nl-BE')})</span>}
            </span>
            {r.next_big_blind > 0 && (
              <span className="tnum block text-xs text-[var(--text-faint)]">
                {t('live.nextBlinds').replace('{n}', r.next_big_blind.toLocaleString('nl-BE'))}
              </span>
            )}
          </span>
        </div>

        {/* Een balk in plaats van nog een getal: waar je staat ten opzichte
            van het gemiddelde lees je in één blik af, en de schaal is
            begrensd op tweemaal het gemiddelde zodat een chipleader de balk
            niet onleesbaar maakt voor de rest. */}
        {mijnBb !== null && gemBb > 0 && (
          <span className="mt-3 block">
            <span className="relative block h-1.5 overflow-hidden rounded-full bg-[var(--surface-2)]">
              <span
                className="absolute inset-y-0 left-0 rounded-full"
                style={{ width: `${Math.min(100, (mijnBb / (gemBb * 2)) * 100)}%`, background: diepteKleur }}
              />
              <span className="absolute inset-y-0 w-px bg-[var(--text-faint)]" style={{ left: '50%' }} />
            </span>
            <span className="mt-1 flex justify-between text-[0.65rem] text-[var(--text-faint)]">
              <span>{t('live.avgBb')} {gemBb} {t('live.bb')}</span>
              {ratio !== null && <span className="tnum">{ratio.toFixed(1)}× {t('live.ofAverage')}</span>}
            </span>
          </span>
        )}
      </div>

      <div className="grid grid-cols-3 gap-px border-t border-[var(--line)] bg-[var(--line)]">
        <Cell
          label={t('live.rank')}
          value={r.my_rank === null
            ? '—'
            : t('live.rankOf')
                .replace('{n}', rangtelwoord(r.my_rank, locale))
                .replace('{m}', String(r.ranked_players))}
          sub={r.my_rank === null
            ? t('live.rankNone')
            : r.ranked_players < r.players_left
              ? t('live.rankPartial')
                  .replace('{n}', String(r.ranked_players))
                  .replace('{m}', String(r.players_left))
              : undefined}
        />
        <Cell
          label={t('clock.playersLeft')}
          value={`${r.players_left}`}
          sub={geld}
        />
        <Cell
          label={t('clock.prizePool')}
          value={formatMoney(Number(r.prize_pool_cents), r.currency)}
          sub={t('live.paidPlaces').replace('{n}', String(r.paid_places))}
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
            disabled={r.counts_frozen}
            onChange={(e) => setChips(e.target.value)}
            onFocus={(e) => e.target.select()}
            className="tnum w-full rounded-lg border border-[var(--line-strong)] bg-[var(--surface-2)] px-3 py-2.5 text-lg outline-none focus:border-[var(--brand)] disabled:opacity-45"
          />
        </label>
        <button
          type="button"
          disabled={busy || r.counts_frozen}
          onClick={() => void save()}
          className="rounded-lg px-4 py-2.5 text-sm font-medium transition disabled:opacity-45"
          style={{ background: accent, color: 'var(--on-brand)' }}
        >
          {busy ? t('common.busy') : saved ? t('common.saved') : t('common.save')}
        </button>

        {/* Een veld dat op slot staat zonder uitleg leest als een storing.
            Met de reden erbij is het een mededeling: de floor is bezig. */}
        {r.counts_frozen && (
          <span className="w-full text-xs text-[var(--warn)]">{t('live.frozen')}</span>
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
