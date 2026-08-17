import { notFound, redirect } from 'next/navigation'
import { ClubNav } from '@/components/ClubNav'
import { MemberList, type Member } from '@/components/MemberList'
import { Notice, Page, PageHeader } from '@/components/ui'
import { getClub, getClubRole } from '@/lib/club'
import { isLocale, translator } from '@/lib/i18n/dictionaries'
import { createClient } from '@/lib/supabase/server'

/**
 * Het ledenbestand van de club.
 *
 * Alleen voor staf: hier staan mailadressen. De database dwingt dat af in
 * club_member_overview(); de controle hieronder is er zodat een speler een
 * nette uitleg krijgt in plaats van een foutmelding.
 */

interface Row {
  player_id: string
  display_name: string
  username: string | null
  email: string | null
  no_email_reason: string | null
  link_state: string
  entries: number
  last_played: string | null
  best_position: number | null
  cashes: number
  total_prize: number
  total_spent: number
  knockouts: number
}

export default async function Page_({ params }: PageProps<'/c/[club]/leden'>) {
  const { club: slug } = await params
  const club = await getClub(slug)
  if (!club) notFound()

  const supabase = await createClient()
  const { data: claims } = await supabase.auth.getClaims()
  if (!claims?.claims) redirect(`/c/${slug}/login?next=/c/${slug}/leden`)

  const role = await getClubRole(club.id)
  const locale = isLocale(club.locale) ? club.locale : 'nl'
  const t = translator(locale)
  const canSee = role !== null && ['owner', 'admin', 'floor'].includes(role)

  if (!canSee) {
    return (
      <Page>
        <PageHeader
          backHref={`/c/${slug}`}
          backLabel={t('result.backToClub')}
          title={t('members.title')}
          subtitle={club.name}
          logoUrl={club.logo_url}
        />
        <Notice tone="warn">{t('members.onlyStaff')}</Notice>
      </Page>
    )
  }

  const { data, error } = await supabase.rpc('club_member_overview', { p_club_id: club.id })
  const rows = (data ?? []) as unknown as Row[]

  const members: Member[] = rows.map((r) => ({
    playerId: r.player_id,
    name: r.display_name,
    username: r.username,
    email: r.email,
    noEmailReason: r.no_email_reason,
    linkState: r.link_state,
    entries: r.entries,
    lastPlayed: r.last_played,
    bestPosition: r.best_position,
    cashes: r.cashes,
    totalPrize: r.total_prize,
    totalSpent: r.total_spent,
    knockouts: r.knockouts,
  }))

  return (
    <Page width="xl">
      <PageHeader overline={club.name} title={t('members.title')} logoUrl={club.logo_url} />
      <ClubNav slug={slug} active="members" canManage t={t} />

      {error && <Notice tone="error">{error.message}</Notice>}

      <MemberList
        clubId={club.id}
        currency={club.currency}
        locale={locale}
        initial={members}
      />
    </Page>
  )
}
