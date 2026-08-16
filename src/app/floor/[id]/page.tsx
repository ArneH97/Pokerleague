import { redirect } from 'next/navigation'
import { FloorControls } from '@/components/FloorControls'
import { createClient } from '@/lib/supabase/server'

export const metadata = { title: 'Floor' }

export default async function Page({ params }: PageProps<'/floor/[id]'>) {
  const { id } = await params
  const supabase = await createClient()

  // Vroege controle zodat een uitgelogde floor niet eerst een leeg scherm
  // ziet. De echte beveiliging blijft RLS: deze redirect is comfort.
  const { data } = await supabase.auth.getClaims()
  if (!data?.claims) {
    redirect(`/login?next=${encodeURIComponent(`/floor/${id}`)}`)
  }

  return <FloorControls tournamentId={id} />
}
