import Link from 'next/link'
import { notFound } from 'next/navigation'
import { ClubNav } from '@/components/ClubNav'
import { PublicStandings } from '@/components/public/PublicStandings'
import { Card, EmptyState, Notice, Page, PageHeader } from '@/components/ui'
import { getClub, getClubRole } from '@/lib/club'
import { isLocale, translator, type T } from '@/lib/i18n/dictionaries'
import { visitorLocale } from '@/lib/i18n/server'
import { createClient } from '@/lib/supabase/server'
import { formatMoney } from '@/lib/types'

/**
 * Klassement van de club.
 *
 * Het rekenwerk zit in de database en niet hier. Dat is geen detail: "tel
 * alleen je beste tien resultaten" en "minstens drie tornooien gespeeld" zijn
 * regels per club, en die hoor je op één plek te hebben staan. Zou de browser
 * het uitrekenen, dan moet elk scherm — en straks ook de spelersapp —
 * diezelfde regels opnieuw kennen.
 *
 * Twee soorten klassement, met opzet uit elkaar gehouden:
 *
 * - Seizoen: season_standings(), mét de beste-N-regel van de club.
 * - Jaar of maand: club_standings_period(), alles telt mee. Een beste-N-regel
 *   over "maart" zou betekenen dat maart iets anders is dan wat er in maart
 *   gebeurd is.
 *
 * De keuze staat in de URL, zodat je een klassement kan doorsturen en de
 * ander precies hetzelfde ziet.
 */

interface Standing {
  player_id: string
  display_name: string
  tournaments: number
  counted?: number
  points: number
  best_position: number
  cashes: number
  total_prize: number
  knockouts: number
}

interface Season {
  id: string
  name: string
  starts_on: string
  ends_on: string | null
  ranking_config_id: string | null
}

interface RankingConfig {
  method: string
  params: Record<string, unknown> | null
  bonus_per_ko: number
  bonus_entry: number
  count_best_n: number | null
}

/** De puntenformule van de club in één zin, in plaats van in de documentatie. */
function explainPoints(cfg: RankingConfig | null, t: T): string[] {
  if (!cfg) return []
  const p = (cfg.params ?? {}) as Record<string, number>
  const out: string[] = []

  if (cfg.method === 'sqrt_ratio') {
    out.push(t('points.sqrt').replace('{mult}', String(p.multiplier ?? 10)))
  } else if (cfg.method === 'linear') {
    out.push(
      t('points.linear')
        .replace('{base}', String(p.base ?? 100))
        .replace('{dec}', String(p.decrement ?? 5))
        .replace('{floor}', String(p.floor ?? 1)),
    )
  } else if (cfg.method === 'pokerstars') {
    out.push(t('points.pokerstars').replace('{mult}', String(p.multiplier ?? 10)))
  } else {
    out.push(t('points.fixed'))
  }

  if (cfg.bonus_per_ko > 0) out.push(t('points.bonusKo').replace('{n}', String(cfg.bonus_per_ko)))
  if (cfg.bonus_entry > 0) out.push(t('points.bonusEntry').replace('{n}', String(cfg.bonus_entry)))
  return out
}

/**
 * Wat één overwinning tegen twintig spelers oplevert. Dezelfde formule als
 * calc_points in de database — hier alleen om te tónen, nooit om iets mee te
 * berekenen dat bewaard wordt. De echte punten komen altijd van de server.
 */
function examplePoints(cfg: RankingConfig): number {
  const p = (cfg.params ?? {}) as Record<string, number>
  let v = 0
  if (cfg.method === 'sqrt_ratio' || cfg.method === 'pokerstars') {
    v = (p.multiplier ?? 10) * Math.sqrt(20)
  } else if (cfg.method === 'linear') {
    v = p.base ?? 100
  }
  return Math.round((v + cfg.bonus_entry) * 100) / 100
}

const MONTHS = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]

export default async function Page_({ params, searchParams }: PageProps<'/c/[club]/klassement'>) {
  const { club: slug } = await params
  const q = await searchParams
  const club = await getClub(slug)
  if (!club) notFound()

  const supabase = await createClient()
  const { data: claims } = await supabase.auth.getClaims()
  const role = claims?.claims ? await getClubRole(club.id) : null
  const canManage = role !== null && ['owner', 'admin', 'floor'].includes(role)
  const locale = isLocale(club.locale) ? club.locale : 'nl'
  const t = translator(locale)

  const one = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v)

  // Het klassement is de reden dat spelers tussen twee avonden door
  // terugkomen; dat achter een login zetten is het weggooien. Wie geen staf
  // is krijgt de publieke versie: dezelfde telling, zonder prijzengeld, en
  // met de naamregeling van de club erop.
  if (!canManage) {
    const p = one(q.p)
    return (
      <PublicStandings
        club={club}
        locale={(await visitorLocale()) ?? locale}
        mode={p === 'year' ? 'year' : p === 'month' ? 'month' : 'all'}
      />
    )
  }
  const mode = one(q.p) === 'year' ? 'year' : one(q.p) === 'month' ? 'month' : 'season'

  const [seasonRes, yearRes] = await Promise.all([
    supabase
      .from('seasons')
      .select('id,name,starts_on,ends_on,ranking_config_id')
      .eq('club_id', club.id)
      .order('starts_on', { ascending: false })
      .overrideTypes<Season[]>(),
    supabase
      .from('tournament_results')
      .select('finished_at')
      .eq('club_id', club.id)
      .order('finished_at', { ascending: false })
      .limit(2000)
      .overrideTypes<{ finished_at: string }[]>(),
  ])

  const seasons = seasonRes.data ?? []
  const years = [...new Set((yearRes.data ?? []).map((r) => new Date(r.finished_at).getFullYear()))]
    .sort((a, b) => b - a)
  if (years.length === 0) years.push(new Date().getFullYear())

  const season = seasons.find((s) => s.id === one(q.s)) ?? seasons[0]
  const year = Number(one(q.y) ?? years[0])
  const month = Number(one(q.m) ?? new Date().getMonth() + 1)

  // ------------------------------------------------------------------ ophalen
  let rows: Standing[] = []
  let error: string | null = null
  let cfg: RankingConfig | null = null

  if (mode === 'season') {
    if (season) {
      const { data, error: err } = await supabase
        .rpc('season_standings', { p_season_id: season.id })
      rows = (data ?? []) as unknown as Standing[]
      error = err?.message ?? null

      if (season.ranking_config_id) {
        const { data: rc } = await supabase
          .from('ranking_configs')
          .select('method,params,bonus_per_ko,bonus_entry,count_best_n')
          .eq('id', season.ranking_config_id)
          .maybeSingle<RankingConfig>()
        cfg = rc ?? null
      }
    }
  } else {
    const from = mode === 'year' ? `${year}-01-01` : monthStart(year, month)
    const to = mode === 'year' ? `${year}-12-31` : monthEnd(year, month)
    const { data, error: err } = await supabase
      .rpc('club_standings_period', { p_club_id: club.id, p_from: from, p_to: to })
    rows = (data ?? []) as unknown as Standing[]
    error = err?.message ?? null
  }

  // De volgorde komt al gesorteerd uit de database, maar we leggen hem hier
  // nog eens vast. Een klassement dat in een andere volgorde staat dan de
  // puntenkolom is geen klassement, en dat mag niet afhangen van of iemand
  // ooit de ORDER BY in een functie aanpast.
  rows = [...rows].sort((a, b) =>
    Number(b.points) - Number(a.points) || a.best_position - b.best_position)

  // De knock-outkolom heeft alleen zin als er bounty gespeeld is. Bij een
  // gewone freezeout staat er anders een kolom streepjes.
  const showKo = rows.some((r) => r.knockouts > 0)
  const showCounted = rows.some((r) => r.counted !== undefined && r.counted !== r.tournaments)
  const explain = explainPoints(cfg, t)

  const monthName = (m: number) =>
    new Intl.DateTimeFormat(`${locale}-BE`, { month: 'long' }).format(new Date(2000, m - 1, 1))

  const base = `/c/${slug}/klassement`
  const periodLabel =
    mode === 'season' ? (season?.name ?? '—')
      : mode === 'year' ? String(year)
      : `${monthName(month)} ${year}`

  return (
    <Page width="xl">
      <PageHeader
        overline={`${club.name} · ${periodLabel}`}
        title={t('standings.title')}
        logoUrl={club.logo_url}
      />
      <ClubNav slug={slug} active="standings" canManage={canManage} t={t} />

      {/* -------------------------------------------------------------- filter */}
      <div className="flex flex-wrap items-center gap-2">
        <Tabs
          items={[
            { href: `${base}?p=season`, label: t('standings.bySeason'), on: mode === 'season' },
            { href: `${base}?p=year&y=${years[0]}`, label: t('standings.byYear'), on: mode === 'year' },
            {
              href: `${base}?p=month&y=${years[0]}&m=${new Date().getMonth() + 1}`,
              label: t('standings.byMonth'),
              on: mode === 'month',
            },
          ]}
        />

        {mode === 'season' && seasons.length > 1 && (
          <Chips
            items={seasons.map((s) => ({
              href: `${base}?p=season&s=${s.id}`,
              label: s.name,
              on: s.id === season?.id,
            }))}
          />
        )}

        {mode !== 'season' && (
          <Chips
            items={years.map((y) => ({
              href: mode === 'year' ? `${base}?p=year&y=${y}` : `${base}?p=month&y=${y}&m=${month}`,
              label: String(y),
              on: y === year,
            }))}
          />
        )}

        {mode === 'month' && (
          <Chips
            items={MONTHS.map((m) => ({
              href: `${base}?p=month&y=${year}&m=${m}`,
              label: monthName(m).slice(0, 3),
              on: m === month,
            }))}
          />
        )}
      </div>

      {error && <Notice tone="error">{error}</Notice>}
      {mode === 'season' && !season && <Notice tone="warn">{t('standings.noSeason')}</Notice>}

      {rows.length === 0 && !error ? (
        <EmptyState title={t('standings.noneInPeriod')}>{t('standings.noneInPeriodBody')}</EmptyState>
      ) : (
        <Card padded={false} className="overflow-x-auto">
          <table className="w-full min-w-[34rem] text-sm">
            <thead>
              <tr className="border-b border-[var(--line)] text-left text-xs uppercase tracking-widest text-[var(--text-faint)]">
                <th className="px-4 py-2.5 font-medium">{t('standings.rank')}</th>
                <th className="px-4 py-2.5 font-medium">{t('standings.player')}</th>
                <th className="px-4 py-2.5 text-right font-medium">{t('standings.points')}</th>
                <th className="px-4 py-2.5 text-right font-medium">{t('standings.played')}</th>
                {showCounted && (
                  <th className="px-4 py-2.5 text-right font-medium">{t('standings.counted')}</th>
                )}
                <th className="px-4 py-2.5 text-right font-medium">{t('standings.best')}</th>
                <th className="px-4 py-2.5 text-right font-medium">{t('standings.cashes')}</th>
                {showKo && (
                  <th className="px-4 py-2.5 text-right font-medium">{t('standings.knockouts')}</th>
                )}
                <th className="px-4 py-2.5 text-right font-medium">{t('standings.prize')}</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r, i) => (
                <tr key={r.player_id} className="border-b border-[var(--line)] last:border-0">
                  <td className="tnum px-4 py-2.5 font-semibold text-[var(--text-faint)]">
                    <span style={i < 3 ? { color: 'var(--brand)' } : undefined}>{i + 1}</span>
                  </td>
                  <td className="px-4 py-2.5 font-medium">{r.display_name}</td>
                  <td className="tnum px-4 py-2.5 text-right font-semibold">
                    {Math.round(Number(r.points)).toLocaleString('nl-BE')}
                  </td>
                  <td className="tnum px-4 py-2.5 text-right text-[var(--text-muted)]">{r.tournaments}</td>
                  {showCounted && (
                    <td className="tnum px-4 py-2.5 text-right text-[var(--text-faint)]">
                      {r.counted ?? '—'}
                    </td>
                  )}
                  <td className="tnum px-4 py-2.5 text-right text-[var(--text-muted)]">{r.best_position}</td>
                  <td className="tnum px-4 py-2.5 text-right text-[var(--text-muted)]">{r.cashes}</td>
                  {showKo && (
                    <td className="tnum px-4 py-2.5 text-right text-[var(--text-muted)]">
                      {r.knockouts > 0 ? r.knockouts : '—'}
                    </td>
                  )}
                  <td className="tnum px-4 py-2.5 text-right">
                    {r.total_prize > 0 ? formatMoney(r.total_prize, club.currency) : '—'}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </Card>
      )}

      {/* Hoe de punten tot stand komen, in het scherm zelf. Anders is de
          eerste vraag van elke speler "waarom heeft hij er meer dan ik". */}
      {explain.length > 0 && (
        <div className="rounded-[var(--radius-lg)] border border-[var(--line)] p-4 text-sm">
          <p className="font-medium">{t('standings.howPoints')}</p>
          <p className="tnum mt-1.5 text-[var(--text-muted)]">{explain.join('   ')}</p>
          {cfg && (
            <p className="mt-1 text-xs text-[var(--text-faint)]">
              {t('points.example')
                .replace('{n}', '20')
                .replace('{pts}', String(examplePoints(cfg)))}
            </p>
          )}
          {cfg?.count_best_n && mode === 'season' && (
            <p className="mt-1 text-xs text-[var(--text-faint)]">
              {t('standings.bestNote').replace('{n}', String(cfg.count_best_n))}
            </p>
          )}
        </div>
      )}
    </Page>
  )
}

function monthStart(y: number, m: number) {
  return `${y}-${String(m).padStart(2, '0')}-01`
}
function monthEnd(y: number, m: number) {
  const last = new Date(Date.UTC(y, m, 0)).getUTCDate()
  return `${y}-${String(m).padStart(2, '0')}-${String(last).padStart(2, '0')}`
}

function Tabs({ items }: { items: { href: string; label: string; on: boolean }[] }) {
  return (
    <div className="flex items-center gap-0.5 rounded-[var(--radius)] border border-[var(--line)] p-0.5">
      {items.map((i) => (
        <Link
          key={i.href}
          href={i.href}
          className={`rounded-[calc(var(--radius)-2px)] px-3 py-1.5 text-sm transition ${
            i.on
              ? 'bg-[var(--brand)] font-medium text-[var(--on-brand)]'
              : 'text-[var(--text-muted)] hover:bg-[var(--surface-hover)] hover:text-[var(--text)]'
          }`}
        >
          {i.label}
        </Link>
      ))}
    </div>
  )
}

function Chips({ items }: { items: { href: string; label: string; on: boolean }[] }) {
  return (
    <div className="flex flex-wrap items-center gap-1.5">
      {items.map((i) => (
        <Link
          key={i.href}
          href={i.href}
          className={`rounded-full border px-3 py-1.5 text-sm capitalize transition ${
            i.on
              ? 'border-[var(--brand)] bg-[color-mix(in_oklab,var(--brand)_14%,transparent)] text-[var(--text)]'
              : 'border-[var(--line)] text-[var(--text-muted)] hover:bg-[var(--surface-hover)]'
          }`}
        >
          {i.label}
        </Link>
      ))}
    </div>
  )
}
