import { notFound } from 'next/navigation'
import { LoginForm } from '@/components/LoginForm'
import { getClub } from '@/lib/club'

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
    />
  )
}
