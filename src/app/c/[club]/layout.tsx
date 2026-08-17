import { notFound } from 'next/navigation'
import { getClub, readableTextOn } from '@/lib/club'

/**
 * Omhulsel van de clubomgeving.
 *
 * Bewust zonder zichtbare navigatie of koptekst: de zaalklok is een
 * schermvullend scherm zonder chroom, en die zit hier ook onder. Wat deze
 * layout wél doet is de club vaststellen en zijn huisstijl beschikbaar maken
 * als CSS-variabelen.
 *
 * Hier staat nergens een productnaam. Cutoff koopt geen software van
 * Pokerleague; Cutoff koopt zijn eigen klok en ledenbestand. Vanuit hun stoel
 * hoort het platform onzichtbaar te zijn.
 */
export default async function ClubLayout({ children, params }: LayoutProps<'/c/[club]'>) {
  const { club: slug } = await params
  const club = await getClub(slug)

  if (!club) notFound()

  const brand = club.primary_color ?? '#059669'

  return (
    <div
      className="min-h-dvh"
      style={
        {
          // Overschrijft de standaardkleur uit globals.css voor alles onder
          // deze club. Elke knop en elk accent volgt vanzelf.
          '--brand': brand,
          '--on-brand': readableTextOn(brand),
        } as React.CSSProperties
      }
    >
      {children}
    </div>
  )
}

export async function generateMetadata({ params }: LayoutProps<'/c/[club]'>) {
  const { club: slug } = await params
  const club = await getClub(slug)
  return { title: club?.name ?? 'Club' }
}
