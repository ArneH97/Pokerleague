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
}

/** Wat de zaalweergave over de deelnemers moet weten. */
export interface TournamentStats {
  entriesTotal: number
  playersLeft: number
  totalChips: number
  prizePoolCents: number
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
