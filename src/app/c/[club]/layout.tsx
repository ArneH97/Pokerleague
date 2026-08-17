import { notFound } from 'next/navigation'
import { getClub, themeVars } from '@/lib/club'
import { LocaleProvider } from '@/lib/i18n/context'
import { isLocale } from '@/lib/i18n/dictionaries'

/**
 * Omhulsel van de clubomgeving.
 *
 * Bewust zonder zichtbare navigatie of koptekst: de zaalklok is een
 * schermvullend scherm zonder chroom, en die zit hier ook onder. Wat deze
 * layout wél doet is de club vaststellen en zijn volledige huisstijl als
 * CSS-variabelen zetten — kleur én vlakken.
 *
 * Hier staat nergens een productnaam. Cutoff koopt geen software van
 * PokerLeague; Cutoff koopt zijn eigen klok en ledenbestand. Vanaf het moment
 * dat hun floor aanlogt hoort alles naar hen te ruiken, niet naar het
 * platform eronder.
 */
export default async function ClubLayout({ children, params }: LayoutProps<'/c/[club]'>) {
  const { club: slug } = await params
  const club = await getClub(slug)

  if (!club) notFound()

  // De taal is een instelling van de club, niet iets wat de floor elke avond
  // opnieuw kiest. Op de zaalklok wil je al helemaal geen keuzescherm.
  const locale = isLocale(club.locale) ? club.locale : 'nl'

  return (
    <LocaleProvider locale={locale}>
      <div className="min-h-dvh bg-[var(--bg)] text-[var(--text)]" style={themeVars(club)}>
        {children}
      </div>
    </LocaleProvider>
  )
}

export async function generateMetadata({ params }: LayoutProps<'/c/[club]'>) {
  const { club: slug } = await params
  const club = await getClub(slug)
  return {
    title: club?.name ?? 'Club',
    icons: club?.logo_url ? { icon: club.logo_url } : undefined,
  }
}
