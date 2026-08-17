import { createClient } from '@/lib/supabase/server'

/**
 * De gegevens achter de publieke clubpagina's.
 *
 * Alles loopt via de functies uit migratie 0023 en niet via de tabellen. Die
 * omweg is het punt: die functies filteren zelf op "publiek tornooi van een
 * actieve club" en passen de naamregel toe. Zou een pagina hier zelf gaan
 * joinen op `players`, dan hangt de privacy ineens af van wie die query
 * schreef. Zo hangt ze aan één plek.
 */

export interface PublicClock {
  tournament_id: string
  name: string
  status: string
  clock: 'stopped' | 'running' | 'paused'
  level_idx: number
  level_started_at: string | null
  level_elapsed_ms: number
  started_at: string | null
  scheduled_at: string
  starting_stack: number
  addon_stack: number | null
  late_reg_level: number | null
  entry_cents: number
  entries: number
  players_left: number
  rebuys: number
  addons: number
  prize_pool_cents: number
  club_slug: string
  club_name: string
  logo_url: string | null
  mark_url: string | null
  primary_color: string | null
  currency: string
  timezone: string
}

export interface PublicLevel {
  idx: number
  is_break: boolean
  label: string | null
  small_blind: number
  big_blind: number
  ante: number
  duration_s: number
}

export interface PublicSeat {
  player_name: string
  status: string
  finish_position: number | null
  chip_count: number | null
}

export interface PublicResultRow {
  place: number
  player_name: string
  points: number
  knockouts: number
}

export interface PublicStanding {
  player_name: string
  tournaments: number
  points: number
  best_position: number
  cashes: number
  knockouts: number
}

/** Eén tornooi zoals een bezoeker het ziet, of null als het niet publiek is. */
export async function getPublicClock(tournamentId: string): Promise<PublicClock | null> {
  const supabase = await createClient()
  const { data } = await supabase.rpc('club_public_clock', { p_tournament_id: tournamentId })
  const rows = (data ?? []) as unknown as PublicClock[]
  return rows[0] ?? null
}

export async function getPublicLevels(tournamentId: string): Promise<PublicLevel[]> {
  const supabase = await createClient()
  const { data } = await supabase.rpc('club_public_levels', { p_tournament_id: tournamentId })
  return (data ?? []) as unknown as PublicLevel[]
}

export async function getPublicSeats(tournamentId: string): Promise<PublicSeat[]> {
  const supabase = await createClient()
  const { data } = await supabase.rpc('club_public_seats', { p_tournament_id: tournamentId })
  return (data ?? []) as unknown as PublicSeat[]
}

export async function getPublicResult(tournamentId: string): Promise<PublicResultRow[]> {
  const supabase = await createClient()
  const { data } = await supabase.rpc('club_public_result', { p_tournament_id: tournamentId })
  return (data ?? []) as unknown as PublicResultRow[]
}

export async function getPublicStandings(
  slug: string, from?: string, to?: string,
): Promise<PublicStanding[]> {
  const supabase = await createClient()
  const { data } = await supabase.rpc('club_public_standings', {
    p_club_slug: slug,
    p_from: from ?? null,
    p_to: to ?? null,
  })
  return (data ?? []) as unknown as PublicStanding[]
}

/** De prijzenladder. Deze functie was al open voor bezoekers. */
export async function getPrizeLadder(tournamentId: string): Promise<number[]> {
  const supabase = await createClient()
  const { data } = await supabase.rpc('tournament_prizes', { p_tournament_id: tournamentId })
  return ((data ?? []) as unknown as { place: number; amount_cents: number }[])
    .sort((a, b) => a.place - b.place)
    .map((r) => r.amount_cents)
}

export interface PublicTournament {
  id: string
  name: string
  scheduled_at: string
  status: string
  buyin_cents: number
  fee_cents: number
}

/**
 * De agenda van de club.
 *
 * Dit mag wél rechtstreeks uit de tabel: `tournaments` heeft een leesregel
 * die publieke tornooien voor iedereen openzet, en hier staan geen namen bij.
 */
export async function getPublicTournaments(
  clubId: string, limit = 60,
): Promise<PublicTournament[]> {
  const supabase = await createClient()
  const { data } = await supabase
    .from('tournaments')
    .select('id,name,scheduled_at,status,buyin_cents,fee_cents')
    .eq('club_id', clubId)
    .eq('player_visibility', 'public')
    .neq('status', 'draft')
    .order('scheduled_at', { ascending: false })
    .limit(limit)
    .overrideTypes<PublicTournament[]>()
  return data ?? []
}
