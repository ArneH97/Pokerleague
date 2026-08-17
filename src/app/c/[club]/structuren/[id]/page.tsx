import { notFound, redirect } from 'next/navigation'
import { StructureEditor } from '@/components/StructureEditor'
import { makeLevel, type EditorLevel } from '@/lib/tournament/structure'
import { Notice, Page, PageHeader } from '@/components/ui'
import { getClub, getClubRole } from '@/lib/club'
import { isLocale, translator } from '@/lib/i18n/dictionaries'
import { createClient } from '@/lib/supabase/server'



interface StructureRow {
  id: string
  name: string
  club_id: string | null
}

interface LevelRow {
  idx: number
  is_break: boolean
  label: string | null
  small_blind: number
  big_blind: number
  ante: number
  duration_s: number
}

export default async function Page_({ params }: PageProps<'/c/[club]/structuren/[id]'>) {
  const { club: slug, id } = await params
  const club = await getClub(slug)
  if (!club) notFound()

  const supabase = await createClient()
  const { data: claims } = await supabase.auth.getClaims()
  if (!claims?.claims) redirect(`/c/${slug}/login?next=/c/${slug}/structuren/${id}`)

  const role = await getClubRole(club.id)
  const canManage = role !== null && ['owner', 'admin', 'floor'].includes(role)
  const t = translator(isLocale(club.locale) ? club.locale : 'nl')

  const [structRes, levelRes] = await Promise.all([
    supabase.from('blind_structures').select('id,name,club_id').eq('id', id)
      .maybeSingle<StructureRow>(),
    supabase.from('blind_levels')
      .select('idx,is_break,label,small_blind,big_blind,ante,duration_s')
      .eq('structure_id', id).order('idx').overrideTypes<LevelRow[]>(),
  ])

  const structure = structRes.data
  if (!structure) notFound()

  const levels: EditorLevel[] = (levelRes.data ?? []).map((l) =>
    makeLevel({
      isBreak: l.is_break,
      label: l.label ?? '',
      smallBlind: l.small_blind,
      bigBlind: l.big_blind,
      ante: l.ante,
      minutes: Math.max(1, Math.round(l.duration_s / 60)),
    }),
  )

  const isTemplate = structure.club_id === null

  return (
    <Page>
      <PageHeader
        backHref={`/c/${slug}/structuren`}
        backLabel={t('struct.title')}
        title={structure.name}
        subtitle={club.name}
      />

      {isTemplate && (
        <Notice tone="warn">
          {t('struct.templateReadOnly')}
        </Notice>
      )}

      {!isTemplate && !canManage && (
        <Notice tone="warn">{t('struct.noRights')}</Notice>
      )}

      {!isTemplate && canManage && (
        <StructureEditor
          structureId={structure.id}
          clubSlug={slug}
          initialName={structure.name}
          initialLevels={levels}
        />
      )}
    </Page>
  )
}
