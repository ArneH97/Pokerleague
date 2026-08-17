'use client'

import { useCallback, useEffect, useMemo, useState } from 'react'
import { createClient } from '@/lib/supabase/client'

/**
 * De uitbetaallijst: wie krijgt er geld, hoeveel, en is het al betaald.
 *
 * Bewust één bron voor twee momenten die op de floor los aanvoelen maar het
 * niet zijn. Als er iemand in het geld afvalt hoort de floor te weten wat hij
 * die man moet geven, en na een deal hoort er een rij namen met bedragen te
 * staan. Dat is dezelfde vraag, twee keer gesteld.
 *
 * Het rekenwerk zit in de database (`tournament_payouts`), niet hier. Na een
 * deal is het afgesproken bedrag maatgevend en niet de ladder, en dat soort
 * onderscheid hoort op één plek te staan — anders wijkt de lijst aan de kassa
 * ooit af van de uitslagpagina, en dan is er ruzie.
 */
export interface PayoutRow {
  tournamentPlayerId: string
  name: string
  place: number
  amountCents: number
  paidAt: string | null
}

interface Raw {
  tournament_player_id: string
  player_name: string
  place: number
  amount_cents: number
  paid_at: string | null
}

export function usePayouts(tournamentId: string) {
  const supabase = useMemo(() => createClient(), [])
  const [rows, setRows] = useState<PayoutRow[]>([])
  const [error, setError] = useState<string | null>(null)

  const load = useCallback(async (): Promise<PayoutRow[]> => {
    const { data, error: err } = await supabase.rpc('tournament_payouts', {
      p_tournament_id: tournamentId,
    })
    if (err) {
      // Geen rechten is hier geen fout om over te klagen: een speler die
      // toevallig op dit scherm belandt hoort de kassalijst gewoon niet te
      // zien, en een rode balk zou suggereren dat er iets stuk is.
      if (!err.message.includes('Geen rechten')) setError(err.message)
      setRows([])
      return []
    }
    const next = ((data ?? []) as unknown as Raw[]).map((r) => ({
      tournamentPlayerId: r.tournament_player_id,
      name: r.player_name,
      place: r.place,
      amountCents: r.amount_cents,
      paidAt: r.paid_at,
    }))
    setError(null)
    setRows(next)
    return next
  }, [supabase, tournamentId])

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    void load()
  }, [load])

  const markPaid = useCallback(async (tpId: string, paid: boolean) => {
    const { error: err } = await supabase.rpc('floor_mark_paid', {
      p_tournament_player_id: tpId,
      p_paid: paid,
    })
    if (err) setError(err.message)
    await load()
  }, [supabase, load])

  const totalCents = rows.reduce((sum, r) => sum + r.amountCents, 0)
  const openCents = rows.filter((r) => !r.paidAt).reduce((sum, r) => sum + r.amountCents, 0)

  return { rows, error, reload: load, markPaid, totalCents, openCents }
}
