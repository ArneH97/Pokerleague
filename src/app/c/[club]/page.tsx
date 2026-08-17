import Link from 'next/link'
import { notFound, redirect } from 'next/navigation'
import {
  Badge, ButtonLink, Card, EmptyState, Notice, Page, PageHeader, SectionTitle,
} from '@/components/ui'
import { getClub, getClubRole } from '@/lib/club'
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

const STATUS: Record<string, { label: string; tone: 'neutral' | 'live' | 'ok' }> = {
  draft: { label: 'Concept', tone: 'neutral' },
  scheduled: { label: 'Gepland', tone: 'neutral' },
  running: { label: 'Bezig', tone: 'live' },
  paused: { label: 'Gepauzeerd', tone: 'neutral' },
  finished: { label: 'Afgelopen', tone: 'neutral' },
  cancelled: { label: 'Geannuleerd', tone: 'neutral' },
}

export default async function Page_({ params }: PageProps<'/c/[club]'>) {
  const { club: slug } = await params
  const club = await getClub(slug)
  if (!club) notFound()

  const supabase = await createClient()
  const { data: claims } = await supabase.auth.getClaims()
  if (!claims?.claims) redirect(`/c/${slug}/login`)

  const role = await getClubRole(club.id)

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

  const fmt = new Intl.DateTimeFormat('nl-BE', {
    weekday: 'short', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit',
    timeZone: club.timezone,
  })

  const canManage = role !== null && ['owner', 'admin', 'floor'].includes(role)

  return (
    <Page>
      <PageHeader
        overline={club.city ?? undefined}
        title={club.name}
        subtitle="Tornooibeheer"
        actions={
          <>
            {canManage && (
              <ButtonLink variant="brand" href={`/c/${slug}/tornooien/nieuw`}>
                Nieuw tornooi
              </ButtonLink>
            )}
            <form action="/auth/signout" method="post">
              <button className="inline-flex items-center rounded-[var(--radius)] border border-[var(--line-strong)] px-4 py-2.5 text-sm font-medium transition-colors hover:bg-[var(--surface-hover)]">
                Afmelden
              </button>
            </form>
          </>
        }
      />

      {club.logo_url && (
        <div className="flex items-center gap-3">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={club.logo_url} alt="" className="size-12 rounded-[var(--radius)] object-contain" />
        </div>
      )}

      {!role && (
        <Notice tone="warn">
          Je account is niet gekoppeld aan deze club, dus je ziet hier niets.
          Vraag een beheerder om je toe te voegen.
        </Notice>
      )}

      {role && all.length === 0 && (
        <EmptyState
          title="Nog geen tornooien"
          action={
            canManage && (
              <ButtonLink variant="brand" href={`/c/${slug}/tornooien/nieuw`}>
                Eerste tornooi aanmaken
              </ButtonLink>
            )
          }
        >
          Maak er een aan om de klok te kunnen gebruiken.
        </EmptyState>
      )}

      {live.length > 0 && (
        <section>
          <SectionTitle>Nu bezig</SectionTitle>
          <Card padded={false} className="overflow-hidden ring-1 ring-[color-mix(in_oklab,var(--ok)_25%,transparent)]">
            {live.map((t) => <Item key={t.id} t={t} club={club} fmt={fmt} />)}
          </Card>
        </section>
      )}

      {upcoming.length > 0 && (
        <section>
          <SectionTitle>Gepland</SectionTitle>
          <Card padded={false} className="overflow-hidden">
            {upcoming.map((t) => <Item key={t.id} t={t} club={club} fmt={fmt} />)}
          </Card>
        </section>
      )}

      {past.length > 0 && (
        <section>
          <SectionTitle>Eerder</SectionTitle>
          <Card padded={false} className="overflow-hidden">
            {past.slice(0, 10).map((t) => <Item key={t.id} t={t} club={club} fmt={fmt} />)}
          </Card>
        </section>
      )}

      {canManage && (
        <p className="pt-2 text-sm text-[var(--text-faint)]">
          <Link href={`/c/${slug}/structuren`} className="underline underline-offset-4 hover:text-[var(--text-muted)]">
            Blindstructuren beheren
          </Link>
        </p>
      )}
    </Page>
  )
}

function Item({
  t, club, fmt,
}: {
  t: Row
  club: { slug: string; currency: string }
  fmt: Intl.DateTimeFormat
}) {
  const s = STATUS[t.status] ?? { label: t.status, tone: 'neutral' as const }
  return (
    <div className="hairline flex flex-wrap items-center justify-between gap-3 px-5 py-4 transition-colors hover:bg-[var(--surface-hover)]">
      <div className="min-w-0">
        <div className="flex items-center gap-2">
          <p className="truncate font-medium">{t.name}</p>
          <Badge tone={s.tone}>{s.label}</Badge>
        </div>
        <p className="tnum mt-0.5 text-sm text-[var(--text-muted)]">
          {fmt.format(new Date(t.scheduled_at))}
          <span className="mx-1.5 text-[var(--text-faint)]">·</span>
          {formatMoney(t.buyin_cents + t.fee_cents, club.currency)}
        </p>
      </div>
      <div className="flex shrink-0 items-center gap-2">
        <ButtonLink size="sm" href={`/c/${club.slug}/klok/${t.id}`}>Klok</ButtonLink>
        <ButtonLink size="sm" variant="brand" href={`/c/${club.slug}/floor/${t.id}`}>Floor</ButtonLink>
      </div>
    </div>
  )
}
