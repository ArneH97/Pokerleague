import { notFound } from 'next/navigation'
import { getClub, themeVars } from '@/lib/club'

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

  return (
    <div className="min-h-dvh bg-[var(--bg)] text-[var(--text)]" style={themeVars(club)}>
      {children}
    </div>
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
