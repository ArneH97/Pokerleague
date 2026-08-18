import { notFound } from 'next/navigation'
import { getClub, themeVars } from '@/lib/club'
import { LocaleProvider } from '@/lib/i18n/context'
import { isLocale } from '@/lib/i18n/dictionaries'
import { visitorLocale } from '@/lib/i18n/server'
import { onPlatform } from '@/lib/whereAmI'

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

  // De taal van de club is de **standaard**, niet de wet.
  //
  // Ze stond hier vast, en de redenering was: de floor van Cutoff hoort elke
  // avond hetzelfde scherm te zien. Dat klopt voor de zaalklok, maar het brak
  // op de eerste echte club die we erbij zetten — een Vlaamse club met een
  // Franstalige floor. Die man kreeg een scherm vol Nederlandse knoppen en
  // kon niets testen, terwijl de app in drie talen bestaat.
  //
  // Nu: wie een taal koos, krijgt die taal, ook hier. Wie niets koos, krijgt
  // die van de club — dus de zaalklok in Baardegem staat vanzelf in het
  // Nederlands en er verandert niets voor wie nooit op de taalknop drukt.
  const chosen = await visitorLocale()
  const locale = chosen ?? (isLocale(club.locale) ? club.locale : 'nl')

  // Twee huiden, en het adres bepaalt welke.
  //
  // Op `app.cutoff.be` is dit de clubomgeving: het werkgereedschap van de
  // club, met hun kleuren en verder niets van ons. Die schermen blijven exact
  // zoals ze zijn — daar is niets mis mee en het is niet van ons om te
  // veranderen.
  //
  // Op `pokerleague.be/c/cutoff` is dit het platform dat een club laat zien.
  // Daar hoort de huid van het platform onder te liggen — nachtblauw, zoals
  // elk ander scherm waar een speler aangemeld is — met de kleur van de club
  // erbovenop uit themeVars. Zonder dat springt een speler van zijn eigen
  // pagina naar een clubpagina en verandert de vloer onder zijn voeten.
  const platform = await onPlatform()

  return (
    <LocaleProvider locale={locale}>
      <div
        {...(platform ? { 'data-site': '' } : {})}
        className="min-h-dvh bg-[var(--bg)] text-[var(--text)]"
        style={themeVars(club)}
      >
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
