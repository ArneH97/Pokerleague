/**
 * Handgeschreven types voor de tabellen die de klok gebruikt.
 *
 * Bewust niet gegenereerd met `supabase gen types`: dat bestand loopt altijd
 * achter op de migraties en niemand merkt het. Dit is klein genoeg om bij te
 * houden en documenteert meteen wat de klok werkelijk nodig heeft.
 */

export type ClockStatusDb = 'stopped' | 'running' | 'paused'

export type TournamentStatus =
  | 'draft' | 'scheduled' | 'running' | 'paused' | 'finished' | 'cancelled'

export type EntryStatus = 'registered' | 'active' | 'eliminated' | 'withdrawn'

export interface TournamentRow {
  id: string
  club_id: string
  season_id: string | null
  structure_id: string | null
  name: string
  scheduled_at: string
  status: TournamentStatus
  buyin_cents: number
  fee_cents: number
  bounty_cents: number
  bounty_mode: string
  addon_cents: number | null
  addon_stack: number | null
  starting_stack: number
  max_reentries: number
  late_reg_level: number | null
  clock: ClockStatusDb
  level_idx: number
  level_started_at: string | null
  level_elapsed_ms: number
  started_at: string | null
  ended_at: string | null
}

export interface BlindLevelRow {
  id: string
  structure_id: string
  idx: number
  is_break: boolean
  label: string | null
  small_blind: number
  big_blind: number
  ante: number
  duration_s: number
}

export interface ClubRow {
  id: string
  slug: string
  name: string
  currency: string
  timezone: string
  /** De taal van de club. Stuurt de floor- en zaalschermen, en is het
      vertrekpunt voor de taal van een speler die aan de deur wordt ingetikt. */
  locale: string
  logo_url: string | null
  /** Alleen het beeldmerk, vrijstaand. Zie migratie 0009. */
  mark_url: string | null
  primary_color: string | null
}

/** Wat de zaalweergave over de deelnemers moet weten. */
export interface TournamentStats {
  /** Aantal spelers dat vanavond aan tafel kwam, ongeacht hoe vaak ze inkochten. */
  entriesTotal: number
  playersLeft: number
  totalChips: number
  prizePoolCents: number
  /** Aparte tellingen per soort inkoop. Een zaal wil het verschil zien. */
  buyins: number
  rebuys: number
  reentries: number
  addons: number
}

/**
 * Hoeveel chips er in spel horen te zijn.
 *
 * Elke inkoop en elke rebuy of re-entry legt een startstack op tafel, een
 * addon zijn eigen aantal. Dit getal is exact: het volgt uit het geldregister
 * en niet uit wat spelers doorgeven.
 *
 * Daarom rekent de gemiddelde stack hiermee en niet met de opgetelde
 * chipcounts. Die counts zijn een schatting — op een gewone avond vult bijna
 * niemand ze in — en dan zou de gemiddelde stack de hele avond op de
 * startstack blijven staan in plaats van te stijgen bij elke afvaller.
 */
export function expectedChipsInPlay(
  t: Pick<TournamentRow, 'starting_stack' | 'addon_stack'>,
  stats: Pick<TournamentStats, 'buyins' | 'rebuys' | 'reentries' | 'addons'>,
): number {
  const start = t.starting_stack ?? 0
  return (stats.buyins + stats.rebuys + stats.reentries) * start
    + stats.addons * (t.addon_stack ?? start)
}

/** Databaserij omzetten naar de klokstand die clock.ts verwacht. */
export function toClockState(t: TournamentRow) {
  return {
    status: t.clock,
    levelIdx: t.level_idx,
    levelStartedAt: t.level_started_at,
    levelElapsedMs: Number(t.level_elapsed_ms ?? 0),
  }
}

export function formatMoney(cents: number, currency = 'EUR'): string {
  return new Intl.NumberFormat('nl-BE', {
    style: 'currency',
    currency,
    minimumFractionDigits: cents % 100 === 0 ? 0 : 2,
  }).format(cents / 100)
}
