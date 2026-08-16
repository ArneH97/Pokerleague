import { notFound, redirect } from 'next/navigation'
import { FloorControls } from '@/components/FloorControls'
import { getClub } from '@/lib/club'
import { createClient } from '@/lib/supabase/server'

export const metadata = { title: 'Floor' }

export default async function Page({ params }: PageProps<'/c/[club]/floor/[id]'>) {
  const { club: slug, id } = await params
  const club = await getClub(slug)
  if (!club) notFound()

  const supabase = await createClient()

  // Vroege controle zodat een uitgelogde floor niet eerst een leeg scherm
  // ziet. De echte beveiliging blijft RLS: deze redirect is comfort.
  const { data } = await supabase.auth.getClaims()
  if (!data?.claims) {
    redirect(`/c/${slug}/login?next=${encodeURIComponent(`/c/${slug}/floor/${id}`)}`)
  }

  return (
    <FloorControls
      tournamentId={id}
      clockHref={`/c/${slug}/klok/${id}`}
    />
  )
}
