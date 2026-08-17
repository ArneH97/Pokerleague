'use client'

import { useCallback, useEffect, useMemo, useState } from 'react'
import { createClient } from '@/lib/supabase/client'

/**
 * De deelnemerslijst van één tornooi, en de clubleden die je nog kan
 * toevoegen.
 *
 * Apart van useTournament gehouden: de zaalklok heeft alleen tellingen nodig
 * en hoeft geen namen op te halen. Dit draait enkel op het floor-scherm.
 */

export interface FloorPlayer {
  id: string
  playerId: string
  name: string
  status: string
  chipCount: number | null
  finishPosition: number | null
  /** Re-entries en rebuys samen: voor de floor is dat één cijfer. */
  reentriesUsed: number
  rebuysUsed: number
  bountiesWon: number
  registeredAt: string
  email: string | null
}

export interface ClubMember {
  playerId: string
  name: string
  email: string | null
}

interface Row {
  id: string
  player_id: string
  status: string
  chip_count: number | null
  finish_position: number | null
  reentries_used: number
  rebuys_used: number
  bounties_won: number
  registered_at: string
  players: { display_name: string; email: string | null } | null
}

interface MemberRow {
  player_id: string
  players: { display_name: string; email: string | null } | null
}

export function useFloorPlayers(tournamentId: string, clubId: string) {
  const supabase = useMemo(() => createClient(), [])
  const [players, setPlayers] = useState<FloorPlayer[]>([])
  const [members, setMembers] = useState<ClubMember[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const load = useCallback(async () => {
    const [tpRes, memberRes] = await Promise.all([
      supabase
        .from('tournament_players')
        .select(
          'id,player_id,status,chip_count,finish_position,reentries_used,rebuys_used,bounties_won,registered_at,players(display_name,email)',
        )
        .eq('tournament_id', tournamentId)
        .overrideTypes<Row[]>(),
      supabase
        .from('club_players')
        .select('player_id,players(display_name,email)')
        .eq('club_id', clubId)
        .overrideTypes<MemberRow[]>(),
    ])

    if (tpRes.error) {
      setError(tpRes.error.message)
      setLoading(false)
      return
    }

    setPlayers(
      (tpRes.data ?? []).map((r) => ({
        id: r.id,
        playerId: r.player_id,
        name: r.players?.display_name ?? '—',
        status: r.status,
        chipCount: r.chip_count,
        finishPosition: r.finish_position,
        reentriesUsed: r.reentries_used,
        rebuysUsed: r.rebuys_used,
        bountiesWon: r.bounties_won,
        registeredAt: r.registered_at,
        email: r.players?.email ?? null,
      })),
    )
    setMembers(
      (memberRes.data ?? [])
        .map((m) => ({
          playerId: m.player_id,
          name: m.players?.display_name ?? '',
          email: m.players?.email ?? null,
        }))
        .filter((m) => m.name !== ''),
    )
    setError(null)
    setLoading(false)
  }, [supabase, tournamentId, clubId])

  useEffect(() => {
    // Zelfde vorm als useTournament: eerst ophalen, dan luisteren. De
    // lintregel over setState in een effect klopt hier niet, want `load`
    // raakt de state pas ná een netwerkaanroep.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    void load()

    const channel = supabase
      .channel(`floor-players:${tournamentId}`)
      .on('postgres_changes',
        { event: '*', schema: 'public', table: 'tournament_players', filter: `tournament_id=eq.${tournamentId}` },
        () => void load())
      .subscribe()

    const poll = setInterval(() => void load(), 20_000)

    return () => {
      clearInterval(poll)
      void supabase.removeChannel(channel)
    }
  }, [supabase, tournamentId, load])

  return { players, members, loading, error, reload: load }
}
