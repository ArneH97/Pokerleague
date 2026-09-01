'use client'

import { useRouter } from 'next/navigation'
import { useState } from 'react'
import { RsvpChecklist, type RsvpRow } from '@/components/RsvpChecklist'

/**
 * De inschrijvingenlijst op de tornooipagina.
 *
 * Die pagina is een serveronderdeel en kent dus geen knoppen die iets doen.
 * Dit dunne laagje maakt er een cliëntonderdeel van en meer niet: het houdt de
 * rijen bij die de server meegaf, en vraagt de pagina opnieuw op zodra er
 * iemand van de lijst gaat.
 *
 * `router.refresh()` en geen eigen ophaling: dan klopt ook de rest van de
 * pagina weer — het aantal in de kop, en straks de teller op de affichepagina.
 */
export function RsvpPanel({
  tournamentId, rows,
}: { tournamentId: string; rows: RsvpRow[] }) {
  const router = useRouter()
  const [weg, setWeg] = useState<string[]>([])
  const zichtbaar = rows.filter((r) => !weg.includes(r.playerId))

  return (
    <RsvpChecklist
      rows={zichtbaar}
      tournamentId={tournamentId}
      onChanged={() => {
        // Meteen uit beeld halen, en daarna pas de pagina verversen. Anders
        // blijft de naam nog een tel staan en klikt iemand een tweede keer.
        setWeg((was) => [...was, ...rows.map((r) => r.playerId).filter((id) =>
          !zichtbaar.some((z) => z.playerId === id))])
        router.refresh()
      }}
    />
  )
}
