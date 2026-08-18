import { notFound, redirect } from 'next/navigation'
import { ClubNav } from '@/components/ClubNav'
import { SettingsForm } from '@/components/settings/SettingsForm'
import { Field, Notice, Page, PageHeader, SectionTitle, inputClass } from '@/components/ui'
import { getClub, getClubRole } from '@/lib/club'
import { LocaleProvider } from '@/lib/i18n/context'
import { translator } from '@/lib/i18n/dictionaries'
import { clubLocale } from '@/lib/i18n/server'
import {
  saveClubBasics, saveClubLook, saveClubPublic, saveCompliance,
  savePayoutTemplate, saveRankingConfig, saveSeason,
} from '@/lib/settingsActions'
import { createClient } from '@/lib/supabase/server'

/**
 * De instellingen van de club.
 *
 * Alles wat hier staat zat tot nu in de database en nergens anders. Dat werkt
 * zolang er iemand is die SQL schrijft, en het houdt op te werken op het
 * moment dat je het nodig hebt: een kwartier voor de eerste hand, wanneer de
 * prijzenverdeling toch anders moet.
 *
 * Alleen owner en admin. Een floor bedient de avond en verandert niet hoe de
 * punten geteld worden. Dat wordt ook niet hier bewaakt maar in de database —
 * zie de opmerking in settingsActions.ts.
 *
 * Wat er bewust níét in staat: de slug, want daar hangen alle adressen aan,
 * en het eigen domein, want dat vraagt ook DNS en een instelling bij de
 * hosting. Die twee horen bij een verhuizing, niet bij een instelling.
 */

interface PayoutRow {
  id: string
  name: string
  tiers: { min_entries: number; max_entries: number; percentages: number[] }[]
  rounding: number
}

interface RankingRow {
  id: string
  name: string
  method: string
  params: Record<string, unknown>
  bonus_per_ko: number
  bonus_entry: number
  count_best_n: number | null
  min_tournaments: number
}

interface SeasonRow {
  id: string
  name: string
  starts_on: string
  ends_on: string | null
  ranking_config_id: string | null
  is_active: boolean
}

export default async function Page_({ params }: PageProps<'/c/[club]/instellingen'>) {
  const { club: slug } = await params
  const club = await getClub(slug)
  if (!club) notFound()

  const supabase = await createClient()
  const { data: claims } = await supabase.auth.getClaims()
  const accountEmail = (claims?.claims?.email as string | undefined) ?? null
  if (!claims?.claims) redirect(`/c/${slug}/login?next=/c/${slug}/instellingen`)

  const role = await getClubRole(club.id)
  const locale = await clubLocale(club.locale)
  const t = translator(locale)
  const canManage = role !== null && ['owner', 'admin', 'floor'].includes(role)
  const canEdit = role === 'owner' || role === 'admin'

  if (!canEdit) {
    return (
      <Page>
        <PageHeader
          backHref={`/c/${slug}`}
          backLabel={t('result.backToClub')}
          title={t('settings.title')}
          subtitle={club.name}
          logoUrl={club.logo_url}
        />
        <Notice tone="warn">{t('settings.onlyOwner')}</Notice>
      </Page>
    )
  }

  const [payoutRes, rankingRes, seasonRes] = await Promise.all([
    supabase.from('payout_templates').select('id,name,tiers,rounding')
      .eq('club_id', club.id).order('name').overrideTypes<PayoutRow[]>(),
    supabase.from('ranking_configs').select('id,name,method,params,bonus_per_ko,bonus_entry,count_best_n,min_tournaments')
      .eq('club_id', club.id).order('name').overrideTypes<RankingRow[]>(),
    supabase.from('seasons').select('id,name,starts_on,ends_on,ranking_config_id,is_active')
      .eq('club_id', club.id).order('starts_on', { ascending: false }).overrideTypes<SeasonRow[]>(),
  ])

  const payout = payoutRes.data?.[0] ?? null
  const ranking = rankingRes.data?.[0] ?? null
  const seasons = seasonRes.data ?? []
  const rankings = rankingRes.data ?? []

  const comp = club.compliance ?? {}
  const c = (k: string, d: number) => Number(comp[k] ?? d)
  const cs = (k: string, d: string) => String(comp[k] ?? d)

  // De rijen van het prijzensjabloon als bewerkbare tekst. Eén regel per
  // veldgrootte leest en typt sneller dan tien invoervakjes die je met tab
  // moet doorlopen.
  const tiersText = (payout?.tiers ?? [])
    .map((x) => `${x.min_entries};${x.max_entries};${x.percentages.join(', ')}`)
    .join('\n')

  const p = (ranking?.params ?? {}) as Record<string, unknown>
  const pn = (k: string, d: number) => Number(p[k] ?? d)

  const hidden = (extra?: Record<string, string>) => (
    <>
      <input type="hidden" name="slug" value={slug} />
      {Object.entries(extra ?? {}).map(([k, v]) => (
        <input key={k} type="hidden" name={k} value={v} />
      ))}
    </>
  )

  return (
    <LocaleProvider locale={locale}>
      <Page>
        <PageHeader
          title={t('settings.title')}
          subtitle={club.name}
          logoUrl={club.logo_url}
        />
        <ClubNav slug={slug} active="settings" canManage={canManage} t={t} locale={locale} account={accountEmail} />

        <div className="mt-2 space-y-4">
          {/* ------------------------------------------------------- club */}
          <SettingsForm action={saveClubBasics} title={t('settings.club')} description={t('settings.clubBody')}>
            {hidden({ id: club.id })}
            <div className="grid gap-4 sm:grid-cols-2">
              <Field label={t('settings.name')}>
                <input name="name" defaultValue={club.name} className={inputClass} required />
              </Field>
              <Field label={t('settings.city')} hint={t('settings.cityHint')}>
                <input name="city" defaultValue={club.city ?? ''} className={inputClass} />
              </Field>
              <Field label={t('settings.locale')} hint={t('settings.localeHint')}>
                <select name="locale" defaultValue={club.locale} className={inputClass}>
                  <option value="nl">Nederlands</option>
                  <option value="fr">Français</option>
                  <option value="en">English</option>
                </select>
              </Field>
              <Field label={t('settings.timezone')}>
                <input name="timezone" defaultValue={club.timezone} className={inputClass} />
              </Field>
              <Field label={t('settings.currency')}>
                <input name="currency" defaultValue={club.currency} maxLength={3} className={inputClass} />
              </Field>
            </div>
          </SettingsForm>

          {/* --------------------------------------------------- huisstijl */}
          <SettingsForm action={saveClubLook} title={t('settings.look')} description={t('settings.lookBody')}>
            {hidden({ id: club.id })}
            <Field label={t('settings.logo')} hint={t('settings.logoHint')}>
              <input name="logo_url" defaultValue={club.logo_url ?? ''} className={inputClass} />
            </Field>
            <Field label={t('settings.mark')} hint={t('settings.markHint')}>
              <input name="mark_url" defaultValue={club.mark_url ?? ''} className={inputClass} />
            </Field>
            <Field label={t('settings.color')} hint={t('settings.colorHint')}>
              <div className="flex items-center gap-3">
                <input
                  name="primary_color"
                  defaultValue={club.primary_color ?? ''}
                  placeholder="#c9a227"
                  className={inputClass}
                />
                <span
                  aria-hidden
                  className="size-10 shrink-0 rounded-[var(--radius)] border border-[var(--line-strong)]"
                  style={{ background: club.primary_color ?? 'transparent' }}
                />
              </div>
            </Field>
          </SettingsForm>

          {/* ---------------------------------------------- publieke kant */}
          <SettingsForm action={saveClubPublic} title={t('settings.public')} description={t('settings.publicBody')}>
            {hidden({ id: club.id })}
            <Field label={t('settings.intro')} hint={t('settings.introHint')}>
              <textarea name="intro" defaultValue={club.intro ?? ''} rows={3} className={inputClass} />
            </Field>
            <div className="grid gap-4 sm:grid-cols-2">
              <Field label={t('settings.address')}>
                <input name="address_line" defaultValue={club.address_line ?? ''} className={inputClass} />
              </Field>
              <Field label={t('settings.maps')} hint={t('settings.mapsHint')}>
                <input name="maps_url" defaultValue={club.maps_url ?? ''} className={inputClass} />
              </Field>
              <Field label={t('settings.rhythm')} hint={t('settings.rhythmHint')}>
                <input name="play_rhythm" defaultValue={club.play_rhythm ?? ''} className={inputClass} />
              </Field>
              <Field label={t('settings.opens')} hint={t('settings.opensHint')}>
                <input type="date" name="opens_on" defaultValue={club.opens_on ?? ''} className={inputClass} />
              </Field>
              <Field label={t('settings.email')}>
                <input type="email" name="contact_email" defaultValue={club.contact_email ?? ''} className={inputClass} />
              </Field>
              <Field label={t('settings.phone')}>
                <input name="contact_phone" defaultValue={club.contact_phone ?? ''} className={inputClass} />
              </Field>
            </div>
            <label className="flex items-start gap-3 rounded-[var(--radius)] border border-[var(--line)] p-3.5">
              <input
                type="checkbox"
                name="public_names"
                defaultChecked={club.public_names}
                className="mt-0.5 size-4 shrink-0"
              />
              <span>
                <span className="block text-sm font-medium">{t('settings.publicNames')}</span>
                <span className="mt-0.5 block text-xs leading-relaxed text-[var(--text-faint)]">
                  {t('settings.publicNamesHint')}
                </span>
              </span>
            </label>
          </SettingsForm>

          {/* -------------------------------------------------- prijzengeld */}
          <SectionTitle>{t('settings.money')}</SectionTitle>

          {payout ? (
            <SettingsForm action={savePayoutTemplate} title={t('settings.payout')} description={t('settings.payoutBody')}>
              {hidden({ id: payout.id })}
              <div className="grid gap-4 sm:grid-cols-2">
                <Field label={t('settings.name')}>
                  <input name="name" defaultValue={payout.name} className={inputClass} />
                </Field>
                <Field label={t('settings.rounding')} hint={t('settings.roundingHint')}>
                  <input
                    type="number" name="rounding" min={1} step={1}
                    defaultValue={Math.max(1, Math.round(payout.rounding / 100))}
                    className={inputClass}
                  />
                </Field>
              </div>
              <Field label={t('settings.tiers')} hint={t('settings.tiersHint')}>
                <textarea
                  name="tiers"
                  defaultValue={tiersText}
                  rows={Math.max(4, (payout.tiers?.length ?? 0) + 1)}
                  spellCheck={false}
                  className={`${inputClass} font-mono text-sm`}
                />
              </Field>
            </SettingsForm>
          ) : (
            <Notice tone="warn">{t('settings.noPayout')}</Notice>
          )}

          {/* -------------------------------------------------------- punten */}
          {ranking ? (
            <SettingsForm action={saveRankingConfig} title={t('settings.points')} description={t('settings.pointsBody')}>
              {hidden({ id: ranking.id })}
              <div className="grid gap-4 sm:grid-cols-2">
                <Field label={t('settings.name')}>
                  <input name="name" defaultValue={ranking.name} className={inputClass} />
                </Field>
                <Field label={t('settings.method')} hint={t('settings.methodHint')}>
                  <select name="method" defaultValue={ranking.method} className={inputClass}>
                    <option value="sqrt_ratio">{t('settings.mSqrt')}</option>
                    <option value="pokerstars">{t('settings.mStars')}</option>
                    <option value="linear">{t('settings.mLinear')}</option>
                    <option value="fixed_table">{t('settings.mTable')}</option>
                  </select>
                </Field>
              </div>

              {/* Alle parameters staan er altijd; welke meetelt hangt af van
                  de formule hierboven. Velden laten verschijnen en verdwijnen
                  vraagt JavaScript en levert een scherm op dat springt. */}
              <div className="grid gap-4 sm:grid-cols-3">
                <Field label={t('settings.multiplier')} hint={t('settings.forSqrt')}>
                  <input type="number" step="0.5" name="multiplier" defaultValue={pn('multiplier', 10)} className={inputClass} />
                </Field>
                <Field label={t('settings.base')} hint={t('settings.forLinear')}>
                  <input type="number" step="1" name="base" defaultValue={pn('base', 100)} className={inputClass} />
                </Field>
                <Field label={t('settings.decrement')} hint={t('settings.forLinear')}>
                  <input type="number" step="1" name="decrement" defaultValue={pn('decrement', 5)} className={inputClass} />
                </Field>
                <Field label={t('settings.floorPts')} hint={t('settings.forLinear')}>
                  <input type="number" step="1" name="floor" defaultValue={pn('floor', 1)} className={inputClass} />
                </Field>
                <Field label={t('settings.table')} hint={t('settings.forTable')}>
                  <input
                    name="table"
                    defaultValue={(p.table as number[] | undefined)?.join(', ') ?? ''}
                    placeholder="100, 80, 65, 50"
                    className={inputClass}
                  />
                </Field>
                <Field label={t('settings.tail')} hint={t('settings.forTable')}>
                  <input type="number" step="1" name="tail" defaultValue={pn('tail', 0)} className={inputClass} />
                </Field>
              </div>

              <div className="grid gap-4 sm:grid-cols-4">
                <Field label={t('settings.bonusKo')}>
                  <input type="number" step="0.5" name="bonus_per_ko" defaultValue={ranking.bonus_per_ko} className={inputClass} />
                </Field>
                <Field label={t('settings.bonusEntry')}>
                  <input type="number" step="0.5" name="bonus_entry" defaultValue={ranking.bonus_entry} className={inputClass} />
                </Field>
                <Field label={t('settings.bestN')} hint={t('settings.bestNHint')}>
                  <input type="number" step="1" min={1} name="count_best_n" defaultValue={ranking.count_best_n ?? ''} className={inputClass} />
                </Field>
                <Field label={t('settings.minEvents')} hint={t('settings.minEventsHint')}>
                  <input type="number" step="1" min={0} name="min_tournaments" defaultValue={ranking.min_tournaments} className={inputClass} />
                </Field>
              </div>
            </SettingsForm>
          ) : (
            <Notice tone="warn">{t('settings.noRanking')}</Notice>
          )}

          {/* ----------------------------------------------------- seizoenen */}
          <SectionTitle>{t('settings.seasons')}</SectionTitle>

          {seasons.map((s) => (
            <SettingsForm
              key={s.id}
              action={saveSeason}
              title={s.name}
              description={s.is_active ? t('settings.seasonActive') : t('settings.seasonClosed')}
            >
              {hidden({ id: s.id, club_id: club.id })}
              <SeasonFields season={s} rankings={rankings} t={t} />
            </SettingsForm>
          ))}

          <SettingsForm action={saveSeason} title={t('settings.newSeason')} description={t('settings.newSeasonBody')}>
            {hidden({ club_id: club.id })}
            <SeasonFields season={null} rankings={rankings} t={t} />
          </SettingsForm>

          {/* -------------------------------------------------- gedoogbeleid */}
          <SectionTitle>{t('settings.compliance')}</SectionTitle>

          <SettingsForm
            action={saveCompliance}
            title={t('settings.limits')}
            description={t('settings.limitsBody')}
            danger
          >
            {hidden({ id: club.id })}
            <input type="hidden" name="profile" value={cs('profile', 'be_tolerance')} />
            <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
              <Field label={t('settings.maxBuyin')} hint={t('settings.euro')}>
                <input type="number" step="1" min={0} name="max_buyin"
                       defaultValue={Math.round(c('max_buyin_cents', 5000) / 100)} className={inputClass} />
              </Field>
              <Field label={t('settings.maxDaily')} hint={t('settings.euro')}>
                <input type="number" step="1" min={0} name="max_daily"
                       defaultValue={Math.round(c('max_daily_cents', 10000) / 100)} className={inputClass} />
              </Field>
              <Field label={t('settings.maxReentries')}>
                <input type="number" step="1" min={0} name="max_reentries"
                       defaultValue={c('max_reentries', 1)} className={inputClass} />
              </Field>
              <Field label={t('settings.minAge')}>
                <input type="number" step="1" min={0} name="min_age"
                       defaultValue={c('min_age', 18)} className={inputClass} />
              </Field>
              <Field label={t('settings.enforce')} hint={t('settings.enforceHint')}>
                <select name="enforce" defaultValue={cs('enforce', 'warn')} className={inputClass}>
                  <option value="off">{t('settings.enforceOff')}</option>
                  <option value="warn">{t('settings.enforceWarn')}</option>
                  <option value="block">{t('settings.enforceBlock')}</option>
                </select>
              </Field>
            </div>
            <label className="flex items-center gap-3">
              <input type="checkbox" name="allow_cash_games"
                     defaultChecked={Boolean(comp.allow_cash_games)} className="size-4" />
              <span className="text-sm">{t('settings.cashGames')}</span>
            </label>
          </SettingsForm>

          <Notice>{t('settings.notHere')}</Notice>
        </div>
      </Page>
    </LocaleProvider>
  )
}

function SeasonFields({
  season, rankings, t,
}: {
  season: SeasonRow | null
  rankings: RankingRow[]
  t: ReturnType<typeof translator>
}) {
  return (
    <>
      <div className="grid gap-4 sm:grid-cols-2">
        <Field label={t('settings.name')}>
          <input name="name" defaultValue={season?.name ?? ''} className={inputClass} required />
        </Field>
        <Field label={t('settings.ranking')}>
          <select name="ranking_config_id" defaultValue={season?.ranking_config_id ?? ''} className={inputClass}>
            <option value="">—</option>
            {rankings.map((r) => (
              <option key={r.id} value={r.id}>{r.name}</option>
            ))}
          </select>
        </Field>
        <Field label={t('settings.startsOn')}>
          <input type="date" name="starts_on" defaultValue={season?.starts_on ?? ''} className={inputClass} required />
        </Field>
        <Field label={t('settings.endsOn')} hint={t('settings.endsOnHint')}>
          <input type="date" name="ends_on" defaultValue={season?.ends_on ?? ''} className={inputClass} />
        </Field>
      </div>
      <label className="flex items-center gap-3">
        <input type="checkbox" name="is_active" defaultChecked={season?.is_active ?? true} className="size-4" />
        <span className="text-sm">{t('settings.seasonIsActive')}</span>
      </label>
    </>
  )
}
