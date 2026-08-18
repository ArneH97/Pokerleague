import Link from 'next/link'
import { notFound, redirect } from 'next/navigation'
import { TournamentForm, type Option } from '@/components/TournamentForm'
import { getClub, getClubRole } from '@/lib/club'
import { translator } from '@/lib/i18n/dictionaries'
import { clubLocale } from '@/lib/i18n/server'
import { createClient } from '@/lib/supabase/server'



export default async function Page({ params }: PageProps<'/c/[club]/tornooien/nieuw'>) {
  const { club: slug } = await params
  const club = await getClub(slug)
  if (!club) notFound()

  const supabase = await createClient()
  const { data: claims } = await supabase.auth.getClaims()
  if (!claims?.claims) redirect(`/c/${slug}/login?next=/c/${slug}/tornooien/nieuw`)

  const role = await getClubRole(club.id)
  const t = translator(await clubLocale(club.locale))
  if (!role || !['owner', 'admin', 'floor'].includes(role)) {
    return (
      <main className="mx-auto min-h-dvh max-w-2xl p-6">
        <p className="rounded-xl border border-[color-mix(in_oklab,var(--warn)_35%,transparent)] bg-[color-mix(in_oklab,var(--warn)_10%,transparent)] p-4 text-sm text-[var(--warn)]">
          {t('tour.noRights')}
        </p>
      </main>
    )
  }

  const [structRes, payoutRes, seasonRes, lastRes] = await Promise.all([
    supabase
      .from('blind_structures')
      .select('id,name,blind_levels(duration_s)')
      .or(`club_id.eq.${club.id},club_id.is.null`)
      .order('name')
      .overrideTypes<{ id: string; name: string; blind_levels: { duration_s: number }[] }[]>(),
    supabase
      .from('payout_templates')
      .select('id,name')
      .or(`club_id.eq.${club.id},club_id.is.null`)
      .order('name')
      .overrideTypes<Option[]>(),
    supabase
      .from('seasons')
      .select('id,name')
      .eq('club_id', club.id)
      .eq('is_active', true)
      .order('starts_on', { ascending: false })
      .overrideTypes<Option[]>(),
    // Neem de instellingen van het vorige tornooi over als startpunt: clubs
    // draaien week na week vrijwel hetzelfde formaat.
    supabase
      .from('tournaments')
      .select('buyin_cents,fee_cents,starting_stack')
      .eq('club_id', club.id)
      .order('scheduled_at', { ascending: false })
      .limit(1)
      .maybeSingle<{ buyin_cents: number; fee_cents: number; starting_stack: number }>(),
  ])

  const structures: Option[] = (structRes.data ?? []).map((s) => {
    const minutes = Math.round(
      s.blind_levels.reduce((sum, l) => sum + l.duration_s, 0) / 60,
    )
    return {
      id: s.id,
      name: s.name,
      extra: `${s.blind_levels.length} levels, ${Math.floor(minutes / 60)}u${String(minutes % 60).padStart(2, '0')}`,
    }
  })

  return (
    <main className="mx-auto min-h-dvh max-w-2xl space-y-8 bg-[var(--bg)] p-6 text-white">
      <header>
        <Link href={`/c/${slug}`} className="text-sm text-[var(--text-faint)] hover:text-[var(--text-muted)]">
          ← {club.name}
        </Link>
        <h1 className="mt-1 text-2xl font-semibold">{t('tour.new')}</h1>
      </header>

      <TournamentForm
        clubSlug={slug}
        clubId={club.id}
        currency={club.currency}
        structures={structures}
        payouts={payoutRes.data ?? []}
        seasons={seasonRes.data ?? []}
        defaults={
          lastRes.data
            ? {
                buyinCents: lastRes.data.buyin_cents,
                feeCents: lastRes.data.fee_cents,
                startingStack: lastRes.data.starting_stack,
              }
            : undefined
        }
      />
    </main>
  )
}
