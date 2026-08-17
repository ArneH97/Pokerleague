'use client'

import { useCallback, useEffect, useMemo, useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import type { BlindLevel } from '@/lib/tournament/clock'
import type {
  BlindLevelRow, ClubRow, TournamentRow, TournamentStats,
} from '@/lib/types'

export interface OpenDeal {
  id: string
  method: string
  poolCents: number
  shares: { name: string; chips: number; agreed_cents: number }[]
}

interface State {
  tournament: TournamentRow | null
  club: ClubRow | null
  levels: BlindLevel[]
  stats: TournamentStats
  loading: boolean
  error: string | null
  /** Verbinding met de realtime-stroom. Zichtbaar maken in de UI: als dit
   *  wegvalt tijdens een tornooi wil de floor dat weten. */
  live: boolean
  /** Het voorstel dat nu op het zaalscherm hoort te staan, of null. */
  deal: OpenDeal | null
}

const EMPTY_STATS: TournamentStats = {
  entriesTotal: 0, playersLeft: 0, totalChips: 0, prizePoolCents: 0,
  buyins: 0, rebuys: 0, reentries: 0, addons: 0,
}

function toLevel(r: BlindLevelRow): BlindLevel {
  return {
    idx: r.idx,
    isBreak: r.is_break,
    label: r.label,
    smallBlind: r.small_blind,
    bigBlind: r.big_blind,
    ante: r.ante,
    durationS: r.duration_s,
  }
}

/**
 * Laadt een tornooi en houdt het actueel via Supabase Realtime.
 *
 * Naast realtime staat er een trage polling van 20 seconden onder. Dat is
 * geen dubbelop maar een vangnet: op zaalwifi valt een websocket zomaar weg,
 * en een klok die stilstaat omdat de verbinding hikte is het ergste wat er
 * op een tornooiavond kan gebeuren.
 */
export function useTournament(tournamentId: string): State & { reload: () => void } {
  const supabase = useMemo(() => createClient(), [])
  const [state, setState] = useState<State>({
    tournament: null, club: null, levels: [], stats: EMPTY_STATS,
    loading: true, error: null, live: false, deal: null,
  })

  const load = useCallback(async () => {
    const { data: t, error: tErr } = await supabase
      .from('tournaments')
      .select('*')
      .eq('id', tournamentId)
      .maybeSingle<TournamentRow>()

    if (tErr) {
      setState((s) => ({ ...s, loading: false, error: tErr.message }))
      return
    }
    if (!t) {
      setState((s) => ({
        ...s, loading: false,
        error: 'Tornooi niet gevonden, of je hebt er geen toegang toe.',
      }))
      return
    }

    const [clubRes, levelRes, playerRes, potRes, dealRes] = await Promise.all([
      supabase.from('clubs').select('id,slug,name,currency,timezone,logo_url,mark_url,primary_color')
        .eq('id', t.club_id).maybeSingle<ClubRow>(),
      t.structure_id
        ? supabase.from('blind_levels').select('*')
            .eq('structure_id', t.structure_id).order('idx')
        : Promise.resolve({ data: [] as BlindLevelRow[], error: null }),
      supabase.from('tournament_players')
        .select('status,chip_count')
        .eq('tournament_id', tournamentId),
      supabase.from('buyins')
        .select('amount_cents,kind')
        .eq('tournament_id', tournamentId)
        .eq('is_void', false),
      // Een openstaand dealvoorstel. Hoort op het zaalscherm zodra de floor
      // het erop zet, en verdwijnt zodra het ingetrokken of aanvaard is.
      supabase.from('tournament_deals')
        .select('id,method,pool_cents,shares')
        .eq('tournament_id', tournamentId)
        .eq('status', 'proposed')
        .maybeSingle<{ id: string; method: string; pool_cents: number; shares: OpenDeal['shares'] }>(),
    ])

    const players = (playerRes.data ?? []) as { status: string; chip_count: number | null }[]
    // buyins is alleen zichtbaar voor staf; spelers krijgen hier netjes null.
    const pot = (potRes.data ?? []) as { amount_cents: number; kind: string }[]
    const count = (k: string) => pot.filter((b) => b.kind === k).length

    setState({
      tournament: t,
      club: clubRes.data ?? null,
      levels: ((levelRes.data ?? []) as BlindLevelRow[]).map(toLevel),
      stats: {
        entriesTotal: players.length,
        playersLeft: players.filter((p) => p.status === 'active' || p.status === 'registered').length,
        // Alleen wie nog speelt telt mee, anders zakt de gemiddelde stack
        // mee met elke afvaller in plaats van te stijgen.
        totalChips: players
          .filter((p) => p.status === 'active' || p.status === 'registered')
          .reduce((sum, p) => sum + (p.chip_count ?? 0), 0),
        prizePoolCents: pot.reduce((sum, b) => sum + b.amount_cents, 0),
        buyins: count('buyin'),
        rebuys: count('rebuy'),
        reentries: count('reentry'),
        addons: count('addon'),
      },
      deal: dealRes.data
        ? {
            id: dealRes.data.id,
            method: dealRes.data.method,
            poolCents: dealRes.data.pool_cents,
            shares: dealRes.data.shares ?? [],
          }
        : null,
      loading: false,
      error: null,
      live: true,
    })
  }, [supabase, tournamentId])

  useEffect(() => {
    // De lintregel waarschuwt voor setState binnen een effect, maar `load`
    // is asynchroon en raakt de state pas ná een netwerkaanroep. Er ontstaan
    // dus geen cascaderende renders. Dit is de gewone "abonneer op een extern
    // systeem"-vorm: eerst één keer ophalen, daarna luisteren.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    void load()

    const channel = supabase
      .channel(`tournament:${tournamentId}`)
      .on('postgres_changes',
        { event: '*', schema: 'public', table: 'tournaments', filter: `id=eq.${tournamentId}` },
        () => void load())
      .on('postgres_changes',
        { event: '*', schema: 'public', table: 'tournament_players', filter: `tournament_id=eq.${tournamentId}` },
        () => void load())
      .on('postgres_changes',
        { event: '*', schema: 'public', table: 'buyins', filter: `tournament_id=eq.${tournamentId}` },
        () => void load())
      .on('postgres_changes',
        { event: '*', schema: 'public', table: 'tournament_deals', filter: `tournament_id=eq.${tournamentId}` },
        () => void load())
      .subscribe((status) => {
        setState((s) => ({ ...s, live: status === 'SUBSCRIBED' }))
      })

    // Vangnet voor een weggevallen websocket.
    const poll = setInterval(() => void load(), 20_000)

    return () => {
      clearInterval(poll)
      void supabase.removeChannel(channel)
    }
  }, [supabase, tournamentId, load])

  return { ...state, reload: () => void load() }
}
