import { notFound } from 'next/navigation'
import { LoginForm } from '@/components/LoginForm'
import { getClub } from '@/lib/club'
import { leagueUrl } from '@/lib/site'

export default async function Page({ params }: PageProps<'/c/[club]/login'>) {
  const { club: slug } = await params
  const club = await getClub(slug)
  if (!club) notFound()

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
    />
  )
}
