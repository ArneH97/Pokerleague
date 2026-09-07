import { notFound } from 'next/navigation'
import { ClockDisplay } from '@/components/ClockDisplay'
import { getClub } from '@/lib/club'
import { LocaleProvider } from '@/lib/i18n/context'

export const metadata = { title: 'Tournament clock' }

/**
 * Zaalweergave. Bewust een eigen URL zonder navigatie eromheen: dit scherm
 * gaat op de beamer of de tv en blijft daar de hele avond staan.
 *
 * **Altijd Engels, en dat is een keuze.** Elk ander scherm volgt de taal van
 * wie ernaar kijkt. Dit scherm heeft geen "wie": er kijkt een hele zaal naar,
 * en in een Belgische pokerzaal zit Nederlands en Frans door elkaar. Wie de
 * klok in één van die twee zet, kiest partij voor de helft van de tafel.
 *
 * Engels is aan een pokertafel geen vreemde taal maar de vaktaal — big blind,
 * ante, break, late reg. Precies de woorden die op dit scherm staan, en
 * precies de woorden die iedereen aan tafel al gebruikt, ongeacht waarin hij
 * praat.
 *
 * De taalkeuze van de floor blijft gewoon gelden voor zijn eigen scherm; die
 * `LocaleProvider` hierbinnen overschrijft alleen wat er op de beamer staat.
 * En omdat de omroepstem dezelfde taal volgt, spreekt hij nu ook Engels — dat
 * hoort bij elkaar: een scherm dat "BREAK" toont terwijl er "pauze" geroepen
 * wordt, klinkt als twee verschillende avonden.
 */
export default async function Page({ params }: PageProps<'/c/[club]/klok/[id]'>) {
  const { club: slug, id } = await params
  const club = await getClub(slug)
  if (!club) notFound()

  return (
    <LocaleProvider locale="en">
      <ClockDisplay tournamentId={id} />
    </LocaleProvider>
  )
}
