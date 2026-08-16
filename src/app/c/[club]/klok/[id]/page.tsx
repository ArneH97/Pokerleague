import { notFound } from 'next/navigation'
import { ClockDisplay } from '@/components/ClockDisplay'
import { getClub } from '@/lib/club'

export const metadata = { title: 'Tornooiklok' }

/**
 * Zaalweergave. Bewust een eigen URL zonder navigatie eromheen: dit scherm
 * gaat op de beamer of de tv en blijft daar de hele avond staan.
 */
export default async function Page({ params }: PageProps<'/c/[club]/klok/[id]'>) {
  const { club: slug, id } = await params
  const club = await getClub(slug)
  if (!club) notFound()

  return <ClockDisplay tournamentId={id} />
}
