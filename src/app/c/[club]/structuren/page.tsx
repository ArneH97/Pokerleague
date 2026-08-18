import { ClubNav } from '@/components/ClubNav'
import { notFound, redirect } from 'next/navigation'
import { NewStructureButton } from '@/components/NewStructureButton'
import { ButtonLink, Card, EmptyState, Page, PageHeader, SectionTitle } from '@/components/ui'
import { getClub, getClubRole } from '@/lib/club'
import { translator, type T } from '@/lib/i18n/dictionaries'
import { clubLocale } from '@/lib/i18n/server'
import { createClient } from '@/lib/supabase/server'



interface Row {
  id: string
  name: string
  club_id: string | null
  blind_levels: { duration_s: number; is_break: boolean }[]
}

export default async function Page_({ params }: PageProps<'/c/[club]/structuren'>) {
  const { club: slug } = await params
  const club = await getClub(slug)
  if (!club) notFound()

  const supabase = await createClient()
  const { data: claims } = await supabase.auth.getClaims()
  const accountEmail = (claims?.claims?.email as string | undefined) ?? null
  if (!claims?.claims) redirect(`/c/${slug}/login?next=/c/${slug}/structuren`)

  const role = await getClubRole(club.id)
  const canManage = role !== null && ['owner', 'admin', 'floor'].includes(role)
  const locale = await clubLocale(club.locale)
  const t = translator(locale)

  const { data } = await supabase
    .from('blind_structures')
    .select('id,name,club_id,blind_levels(duration_s,is_break)')
    .or(`club_id.eq.${club.id},club_id.is.null`)
    .order('name')
    .overrideTypes<Row[]>()

  const rows = data ?? []
  const own = rows.filter((r) => r.club_id === club.id)
  const templates = rows.filter((r) => r.club_id === null)

  return (
    <Page>
      <PageHeader
        title={t('struct.title')}
        subtitle={t('struct.subtitle')}
        actions={canManage && <NewStructureButton clubId={club.id} clubSlug={slug} />}
      />
      <ClubNav slug={slug} active="structures" canManage t={t} locale={locale} account={accountEmail} />

      {own.length === 0 ? (
        <EmptyState
          title={t('struct.none')}
          action={canManage && <NewStructureButton clubId={club.id} clubSlug={slug} />}
        >
          {t('struct.noneBody')}
        </EmptyState>
      ) : (
        <section>
          <SectionTitle>{t('struct.ownOf')} {club.name}</SectionTitle>
          <List items={own} slug={slug} clubId={club.id} t={t} />
        </section>
      )}

      {templates.length > 0 && (
        <section>
          <SectionTitle>{t('struct.templates')}</SectionTitle>
          <List items={templates} slug={slug} clubId={club.id} template t={t} />
        </section>
      )}
    </Page>
  )
}

function List({
  items, slug, clubId, template, t,
}: {
  items: Row[]
  slug: string
  clubId: string
  template?: boolean
  t: T
}) {
  return (
    <Card padded={false} className="overflow-hidden">
      {items.map((s) => {
        const minutes = Math.round(s.blind_levels.reduce((a, l) => a + l.duration_s, 0) / 60)
        const play = s.blind_levels.filter((l) => !l.is_break).length
        return (
          <div
            key={s.id}
            className="hairline flex flex-wrap items-center justify-between gap-3 px-5 py-4 transition-colors hover:bg-[var(--surface-hover)]"
          >
            <div className="min-w-0">
              <p className="truncate font-medium">{s.name}</p>
              <p className="tnum mt-0.5 text-sm text-[var(--text-muted)]">
                {play} {t('struct.levels')}
                <span className="mx-1.5 text-[var(--text-faint)]">·</span>
                {Math.floor(minutes / 60)}u{String(minutes % 60).padStart(2, '0')} {t('struct.playTime')}
              </p>
            </div>
            {template ? (
              <NewStructureButton
                clubId={clubId}
                clubSlug={slug}
                copyFrom={s.id}
                label={t('struct.copy')}
                suggestedName={`${s.name} (${t('struct.copySuffix')})`}
              />
            ) : (
              <ButtonLink size="sm" href={`/c/${slug}/structuren/${s.id}`}>{t('struct.edit')}</ButtonLink>
            )}
          </div>
        )
      })}
    </Card>
  )
}
