import { ClockDisplay } from '@/components/ClockDisplay'

export const metadata = { title: 'Tornooiklok' }

/**
 * Zaalweergave. Bewust een eigen URL zonder navigatie eromheen: dit scherm
 * gaat op de beamer of de tv en blijft daar de hele avond staan.
 */
export default async function Page({ params }: PageProps<'/klok/[id]'>) {
  const { id } = await params
  return <ClockDisplay tournamentId={id} />
}
