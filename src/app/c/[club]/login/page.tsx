import { notFound } from 'next/navigation'
import { LanguageSwitch } from '@/components/LanguageSwitch'
import { LoginForm } from '@/components/LoginForm'
import { getClub } from '@/lib/club'
import { translator } from '@/lib/i18n/dictionaries'
import { clubLocale } from '@/lib/i18n/server'
import { leagueUrl } from '@/lib/site'

export default async function Page({ params }: PageProps<'/c/[club]/login'>) {
  const { club: slug } = await params
  const club = await getClub(slug)
  if (!club) notFound()

  const locale = await clubLocale(club.locale)
  const t = translator(locale)

  return (
    <LoginForm
      brandName={club.name}
      logoUrl={club.logo_url}
      fallbackNext={`/c/${club.slug}`}
      branded
      // Dit scherm is voor medewerkers. Een speler die hier landt hoort in
      // één klik op de clubpagina van het platform te staan, waar zijn eigen
      // account thuishoort.
      playerHref={leagueUrl(`/c/${club.slug}`)}
      playerLabel={club.name}
      languageSwitch={<LanguageSwitch current={locale} label={t('common.language')} />}
    />
  )
}
