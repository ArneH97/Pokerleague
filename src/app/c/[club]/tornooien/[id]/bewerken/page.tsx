import Link from 'next/link'
import { notFound, redirect } from 'next/navigation'
import { TournamentForm, type Existing, type Option } from '@/components/TournamentForm'
import { getClub, getClubRole } from '@/lib/club'
import { translator } from '@/lib/i18n/dictionaries'
import { clubLocale } from '@/lib/i18n/server'
import { createClient } from '@/lib/supabase/server'

/**
 * Een avond bijstellen nadat ze is aangemaakt.
 *
 * Hetzelfde formulier als bij het aanmaken, met de bestaande waarden erin.
 * Twee schermen die hetzelfde tonen lopen na een half jaar uit elkaar — dan
 * staat het ene veld er wel en het andere niet, en niemand weet nog welke van
 * de twee de waarheid is.
 *
 * Wat er nog mag wijzigen, bepaalt de databank; dit scherm leest dezelfde
 * toestand en zet alvast de velden op slot die toch geweigerd zouden worden.
 */

interface Row {
  id: string
  club_id: string
  name: string
  scheduled_at: string
  status: string
  player_visibility: string
  season_id: string | null
  structure_id: string | null
  payout_template_id: string | null
  buyin_cents: number
  fee_cents: number
  rebuy_cents: number | null
  rebuy_fee_cents: number | null
  addon_cents: number | null
  addon_fee_cents: number | null
  addon_stack: number | null
  bounty_mode: string
  bounty_cents: number
  starting_stack: number
  max_reentries: number
  late_reg_level: number | null
  prereg_bonus_stack: number
  started_at: string | null
  level_idx: number
}

export default async function Page({ params }: PageProps<'/c/[club]/tornooien/[id]/bewerken'>) {
  const { club: slug, id } = await params
  const club = await getClub(slug)
  if (!club) notFound()

  const supabase = await createClient()
  const { data: claims } = await supabase.auth.getClaims()
  if (!claims?.claims) redirect(`/c/${slug}/login?next=/c/${slug}/tornooien/${id}/bewerken`)

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

  const [tourRes, structRes, payoutRes, seasonRes] = await Promise.all([
    supabase
      .from('tournaments')
      .select(
        'id,club_id,name,scheduled_at,status,player_visibility,season_id,structure_id,payout_template_id,'
        + 'buyin_cents,fee_cents,rebuy_cents,rebuy_fee_cents,addon_cents,addon_fee_cents,addon_stack,'
        + 'bounty_mode,bounty_cents,starting_stack,max_reentries,late_reg_level,prereg_bonus_stack,'
        + 'started_at,level_idx',
      )
      .eq('id', id)
      .eq('club_id', club.id)
      .maybeSingle<Row>(),
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
  ])

  const row = tourRes.data
  if (!row) notFound()

  const structures: Option[] = (structRes.data ?? []).map((s) => {
    const minutes = Math.round(s.blind_levels.reduce((sum, l) => sum + l.duration_s, 0) / 60)
    return {
      id: s.id,
      name: s.name,
      extra: `${s.blind_levels.length} levels, ${Math.floor(minutes / 60)}u${String(minutes % 60).padStart(2, '0')}`,
    }
  })

  const existing: Existing = {
    id: row.id,
    name: row.name,
    scheduledAt: row.scheduled_at,
    buyinCents: row.buyin_cents,
    feeCents: row.fee_cents,
    rebuyCents: row.rebuy_cents,
    rebuyFeeCents: row.rebuy_fee_cents,
    addonCents: row.addon_cents,
    addonFeeCents: row.addon_fee_cents,
    addonStack: row.addon_stack,
    bountyMode: row.bounty_mode,
    bountyCents: row.bounty_cents,
    startingStack: row.starting_stack,
    maxReentries: row.max_reentries,
    lateRegLevel: row.late_reg_level,
    preregBonusStack: row.prereg_bonus_stack,
    structureId: row.structure_id,
    payoutTemplateId: row.payout_template_id,
    seasonId: row.season_id,
    membersOnly: row.player_visibility === 'members',
    clockRan: row.started_at !== null || row.level_idx > 0,
    finished: row.status === 'finished' || row.status === 'cancelled',
  }

  return (
    <main className="mx-auto min-h-dvh max-w-2xl space-y-8 bg-[var(--bg)] p-6 text-white">
      <header>
        <Link
          href={`/c/${slug}/tornooien/${id}`}
          className="text-sm text-[var(--text-faint)] hover:text-[var(--text-muted)]"
        >
          ← {row.name}
        </Link>
        <h1 className="mt-1 text-2xl font-semibold">{t('tour.edit')}</h1>
      </header>

      <TournamentForm
        clubSlug={slug}
        clubId={club.id}
        currency={club.currency}
        structures={structures}
        payouts={payoutRes.data ?? []}
        seasons={seasonRes.data ?? []}
        existing={existing}
      />
    </main>
  )
}
