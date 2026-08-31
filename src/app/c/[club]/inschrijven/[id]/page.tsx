import { notFound } from 'next/navigation'
import { SignupPage, type SignupCard } from '@/components/public/SignupPage'
import { getClub } from '@/lib/club'
import { translator } from '@/lib/i18n/dictionaries'
import { clubLocale } from '@/lib/i18n/server'
import { createClient } from '@/lib/supabase/server'

/**
 * Inschrijven voor één bepaalde avond.
 *
 * Voor wanneer er meer dan één avond gepland staat en je er eentje wil delen —
 * een deepstack, een clubkampioenschap. De korte variant zonder id pakt altijd
 * de eerstvolgende, en dat is meestal wat je wil, maar niet altijd.
 */

export const dynamic = 'force-dynamic'

export async function generateMetadata({ params }: PageProps<'/c/[club]/inschrijven/[id]'>) {
  const { club: slug } = await params
  const club = await getClub(slug)
  const t = translator(await clubLocale(club?.locale))
  return {
    title: club ? `${t('rsvp.metaTitle')} — ${club.name}` : t('rsvp.metaTitle'),
    description: club ? t('rsvp.metaBody').replace('{club}', club.name) : undefined,
  }
}

export default async function Page({ params }: PageProps<'/c/[club]/inschrijven/[id]'>) {
  const { club: slug, id } = await params
  const club = await getClub(slug)
  if (!club) notFound()

  const locale = await clubLocale(club.locale)
  const supabase = await createClient()
  const { data } = await supabase.rpc('tournament_signup_card', {
    p_club_slug: slug,
    p_tournament_id: id,
  })
  const card = ((data ?? []) as unknown as SignupCard[])[0] ?? null

  return <SignupPage card={card} club={club} locale={locale} />
}
