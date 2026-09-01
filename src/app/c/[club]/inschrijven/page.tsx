import { notFound } from 'next/navigation'
import { SignupPage, type SignupCard } from '@/components/public/SignupPage'
import { getClub } from '@/lib/club'
import { translator } from '@/lib/i18n/dictionaries'
import { clubLocale, urlLocale } from '@/lib/i18n/server'
import { createClient } from '@/lib/supabase/server'

/**
 * `cutoff.pokerleague.be/inschrijven` — het adres dat op de affiche staat.
 *
 * Zonder tornooi in de URL, met opzet. Een affiche moet een adres dragen dat
 * iemand kan overtikken van een raam of een scherm, en `/inschrijven/8f3c-…`
 * is dat niet. De database zoekt zelf de eerstvolgende geplande avond, dus
 * hetzelfde adres blijft volgende maand werken zonder dat er iemand een
 * affiche moet aanpassen.
 *
 * Wie tóch een bepaalde avond wil delen, gebruikt `/inschrijven/<id>`.
 *
 * `force-dynamic`: hier staat een teller op die met elke inschrijving
 * verandert, en een pagina die gisteren "3 ingeschreven" cachte, liegt.
 */

export const dynamic = 'force-dynamic'

export async function generateMetadata({ params }: PageProps<'/c/[club]/inschrijven'>) {
  const { club: slug } = await params
  const club = await getClub(slug)
  const t = translator(await clubLocale(club?.locale))
  return {
    title: club ? `${t('rsvp.metaTitle')} — ${club.name}` : t('rsvp.metaTitle'),
    description: club ? t('rsvp.metaBody').replace('{club}', club.name) : undefined,
  }
}

export default async function Page({ params, searchParams }: PageProps<'/c/[club]/inschrijven'>) {
  const { club: slug } = await params
  const club = await getClub(slug)
  if (!club) notFound()

  // `?l=fr` van de Franse affiche wint van alles; daarna pas het koekje van
  // de bezoeker en de taal van de club.
  const locale = urlLocale((await searchParams).l) ?? (await clubLocale(club.locale))
  const supabase = await createClient()
  const { data } = await supabase.rpc('tournament_signup_card', { p_club_slug: slug })
  const card = ((data ?? []) as unknown as SignupCard[])[0] ?? null

  return <SignupPage card={card} club={club} locale={locale} />
}
