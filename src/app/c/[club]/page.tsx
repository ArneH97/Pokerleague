import { notFound } from 'next/navigation'
import { ClubHeader } from '@/components/ClubHeader'
import { PublicClubHome } from '@/components/public/PublicClubHome'
import { ClubNav } from '@/components/ClubNav'
import {
  Badge, ButtonLink, Card, EmptyState, Notice, Page, SectionTitle,
} from '@/components/ui'
import { getClub, getClubRole } from '@/lib/club'
import { isLocale, translator, type Key, type T } from '@/lib/i18n/dictionaries'
import { createClient } from '@/lib/supabase/server'
import { formatMoney } from '@/lib/types'

interface Row {
  id: string
  name: string
  scheduled_at: string
  status: string
  buyin_cents: number
  fee_cents: number
}

const STATUS: Record<string, { key: Key; tone: 'neutral' | 'live' | 'ok' }> = {
  draft: { key: 'status.draft', tone: 'neutral' },
  scheduled: { key: 'status.scheduled', tone: 'neutral' },
  running: { key: 'status.running', tone: 'live' },
  paused: { key: 'status.paused', tone: 'neutral' },
  finished: { key: 'status.finished', tone: 'neutral' },
  cancelled: { key: 'status.cancelled', tone: 'neutral' },
}

export default async function Page_({ params }: PageProps<'/c/[club]'>) {
  const { club: slug } = await params
  const club = await getClub(slug)
  if (!club) notFound()

  const supabase = await createClient()
  const { data: claims } = await supabase.auth.getClaims()
  const role = claims?.claims ? await getClubRole(club.id) : null
  const t = translator(isLocale(club.locale) ? club.locale : 'nl')

  // Eén adres, twee gezichten. Wie hier binnenkomt zonder bij de club te
  // horen is een speler of een bezoeker en krijgt de publieke pagina; staf
  // krijgt het dashboard. Dat scheelt de club een tweede domein en de spelers
  // een URL die ze moeten onthouden — app.cutoff.be is gewoon "de club".
  if (role === null || !['owner', 'admin', 'floor'].includes(role)) {
    return <PublicClubHome club={club} t={t} />
  }

  const { data } = await supabase
    .from('tournaments')
    .select('id,name,scheduled_at,status,buyin_cents,fee_cents')
    .eq('club_id', club.id)
    .order('scheduled_at', { ascending: false })
    .limit(50)
    .overrideTypes<Row[]>()

  const all = data ?? []
  const live = all.filter((t) => t.status === 'running' || t.status === 'paused')
  const upcoming = all
    .filter((t) => t.status === 'scheduled' || t.status === 'draft')
    .reverse()
  const past = all.filter((t) => t.status === 'finished' || t.status === 'cancelled')

  const fmt = new Intl.DateTimeFormat(`${club.locale}-BE`, {
    weekday: 'short', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit',
    timeZone: club.timezone,
  })

  const canManage = role !== null && ['owner', 'admin', 'floor'].includes(role)

  return (
    <Page>
      <ClubHeader
        name={club.name}
        city={club.city}
        subtitle={t('club.subtitle')}
        logoUrl={club.logo_url}
        actions={
          <>
            {canManage && (
              <ButtonLink variant="brand" href={`/c/${slug}/tornooien/nieuw`}>
                {t('club.newTournament')}
              </ButtonLink>
            )}
            <form action="/auth/signout" method="post">
              <button className="inline-flex items-center rounded-[var(--radius)] border border-[var(--line-strong)] px-4 py-2.5 text-sm font-medium transition-colors hover:bg-[var(--surface-hover)]">
                {t('common.signOut')}
              </button>
            </form>
          </>
        }
      />

      {role && <ClubNav slug={slug} active="tournaments" canManage={canManage} t={t} />}

      {!role && (
        <Notice tone="warn">
          {t('club.notLinked')}
        </Notice>
      )}

      {role && all.length === 0 && (
        <EmptyState
          title={t('club.noTournaments')}
          action={
            canManage && (
              <ButtonLink variant="brand" href={`/c/${slug}/tornooien/nieuw`}>
                {t('club.firstTournament')}
              </ButtonLink>
            )
          }
        >
          {t('club.noTournamentsBody')}
        </EmptyState>
      )}

      {live.length > 0 && (
        <section>
          <SectionTitle>{t('club.nowPlaying')}</SectionTitle>
          <Card padded={false} className="overflow-hidden ring-1 ring-[color-mix(in_oklab,var(--ok)_25%,transparent)]">
            {live.map((x) => <Item key={x.id} t={x} club={club} fmt={fmt} tr={t} />)}
          </Card>
        </section>
      )}

      {upcoming.length > 0 && (
        <section>
          <SectionTitle>{t('club.scheduled')}</SectionTitle>
          <Card padded={false} className="overflow-hidden">
            {upcoming.map((x) => <Item key={x.id} t={x} club={club} fmt={fmt} tr={t} />)}
          </Card>
        </section>
      )}

      {past.length > 0 && (
        <section>
          <SectionTitle>{t('club.earlier')}</SectionTitle>
          <Card padded={false} className="overflow-hidden">
            {past.slice(0, 10).map((x) => <Item key={x.id} t={x} club={club} fmt={fmt} tr={t} />)}
          </Card>
        </section>
      )}

    </Page>
  )
}

function Item({
  t, club, fmt, tr,
}: {
  t: Row
  club: { slug: string; currency: string }
  fmt: Intl.DateTimeFormat
  tr: T
}) {
  const s = STATUS[t.status]
  return (
    <div className="hairline flex flex-wrap items-center justify-between gap-3 px-5 py-4 transition-colors hover:bg-[var(--surface-hover)]">
      <div className="min-w-0">
        <div className="flex items-center gap-2">
          <p className="truncate font-medium">{t.name}</p>
          <Badge tone={s?.tone ?? 'neutral'}>{s ? tr(s.key) : t.status}</Badge>
        </div>
        <p className="tnum mt-0.5 text-sm text-[var(--text-muted)]">
          {fmt.format(new Date(t.scheduled_at))}
          <span className="mx-1.5 text-[var(--text-faint)]">·</span>
          {formatMoney(t.buyin_cents + t.fee_cents, club.currency)}
        </p>
      </div>
      {/* Een afgelopen avond bedien je niet meer, die bekijk je. */}
      <div className="flex shrink-0 items-center gap-2">
        {t.status === 'finished' || t.status === 'cancelled' ? (
          <ButtonLink size="sm" variant="brand" href={`/c/${club.slug}/tornooien/${t.id}`}>
            {tr('result.view')}
          </ButtonLink>
        ) : (
          <>
            <ButtonLink size="sm" href={`/c/${club.slug}/klok/${t.id}`}>{tr('club.clock')}</ButtonLink>
            <ButtonLink size="sm" variant="brand" href={`/c/${club.slug}/floor/${t.id}`}>{tr('club.floor')}</ButtonLink>
          </>
        )}
      </div>
    </div>
  )
}
