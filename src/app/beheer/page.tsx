import Link from 'next/link'
import { redirect } from 'next/navigation'
import { AreaLine, ClubBars, Panel, StackedMonths, Tile, money, num } from '@/components/admin/Charts'
import { LanguageSwitch } from '@/components/LanguageSwitch'
import { LocaleProvider } from '@/lib/i18n/context'
import { translator, type Locale, type T } from '@/lib/i18n/dictionaries'
import { publicLocale } from '@/lib/i18n/server'
import { createClient } from '@/lib/supabase/server'

/**
 * Het platform door de ogen van wie het bezit.
 *
 * Elk ander scherm in dit product kijkt naar één club of naar één speler. Dit
 * is het enige waar alles bij elkaar staat, en het beantwoordt vier vragen in
 * die volgorde:
 *
 *   1. **Loopt het?** Clubs, mensen, avonden. De bovenste rij.
 *   2. **Wat brengt het op?** De abonnementen, per maand en tot nu.
 *   3. **Hoeveel geld gaat er rond?** Wat er aan de deur binnenkomt bij de
 *      clubs — dat is niet mijn geld, maar het is wel de maat van wat er
 *      gebeurt. Een platform waar niets over de tafels gaat, doet niets.
 *   4. **Wie doet het?** Per club, en de spelers die het meest spelen.
 *
 * Alle cijfers komen uit zes functies in de database die elk hun eigen
 * rechtencontrole doen. Deze pagina is dus geen slot maar een venster: wie
 * hier zonder rechten komt, krijgt van de database niets terug, ook niet als
 * hij de URL raadt.
 *
 * **Geen keuzemenu's, geen periodefilters.** Die kwamen in de eerste opzet
 * bovenaan te staan en maakten van een overzicht een gereedschapskist. Wat je
 * 's avonds wil zien is de stand van zaken, niet een vraag over welke periode
 * je bedoelt. Twaalf maanden is het venster; de totalen staan ernaast.
 */

export const dynamic = 'force-dynamic'

interface Overview {
  clubs: number; clubs_active: number; staff: number
  players: number; players_claimed: number; players_shadow: number
  memberships: number; multi_club: number
  tournaments: number; upcoming: number
  entries: number; entries_30d: number; avg_field: number
  pot_cents: number; fee_cents: number; bounty_cents: number; prize_cents: number
  active_30d: number; active_90d: number; new_players_30d: number
  mrr_cents: number; arr_cents: number; setup_cents: number; revenue_cents: number
  first_night: string | null; last_night: string | null
}

interface ClubRow {
  slug: string; name: string; city: string | null; primary_color: string | null
  is_active: boolean; since: string
  members: number; claimed: number; staff: number
  tournaments: number; entries: number; avg_field: number
  pot_cents: number; fee_cents: number
  active_30d: number; last_night: string | null
  monthly_cents: number; revenue_cents: number
}

interface MonthRow {
  month: string; tournaments: number; entries: number
  pot_cents: number; fee_cents: number; prize_cents: number
  new_players: number; active_players: number; revenue_cents: number
}

interface ClubMonthRow {
  month: string; slug: string; name: string; primary_color: string | null
  tournaments: number; entries: number
}

interface TopRow {
  display_name: string; clubs: number; entries: number; wins: number; cashes: number
  invested_cents: number; won_cents: number; net_cents: number; last_played: string | null
}

interface RecentRow {
  slug: string; club: string; primary_color: string | null
  name: string; played_on: string; ended_at: string; entries: number; pot_cents: number; winner: string | null
}

export async function generateMetadata() {
  return { title: translator(await publicLocale())('adm.title') }
}

export default async function Page() {
  const supabase = await createClient()
  const { data: claims } = await supabase.auth.getClaims()
  if (!claims?.claims) redirect('/login?next=/beheer')

  const locale = await publicLocale()
  const t = translator(locale)

  const [ovRes, clubRes, monthRes, clubMonthRes, topRes, recentRes] = await Promise.all([
    supabase.rpc('platform_overview'),
    supabase.rpc('platform_clubs'),
    supabase.rpc('platform_month_series', { p_months: 12 }),
    supabase.rpc('platform_club_month_series', { p_months: 12 }),
    supabase.rpc('platform_top_players', { p_limit: 8 }),
    supabase.rpc('platform_recent', { p_limit: 6 }),
  ])

  const ov = ((ovRes.data ?? []) as unknown as Overview[])[0]

  // Geen rechten: geen uitleg over wat hier zou staan. Wie hier per ongeluk
  // belandt, hoeft niet te weten dat hij iets mist.
  if (ovRes.error || !ov) {
    return (
      <LocaleProvider locale={locale}>
        <div data-site lang={locale} className="grid min-h-dvh place-items-center bg-[var(--bg)] px-6 text-center text-[var(--text)]">
          <div>
            <p className="text-lg font-medium">{t('adm.denied')}</p>
            <p className="mt-2 text-sm text-[var(--text-muted)]">{t('adm.deniedBody')}</p>
            <Link
              href="/ik"
              className="mt-6 inline-block rounded-full border border-[var(--line-strong)] px-5 py-2.5 text-sm transition hover:bg-[var(--surface-hover)]"
            >
              {t('adm.toProfile')} →
            </Link>
          </div>
        </div>
      </LocaleProvider>
    )
  }

  const clubs = (clubRes.data ?? []) as unknown as ClubRow[]
  const months = (monthRes.data ?? []) as unknown as MonthRow[]
  const clubMonths = (clubMonthRes.data ?? []) as unknown as ClubMonthRow[]
  const top = (topRes.data ?? []) as unknown as TopRow[]
  const recent = (recentRes.data ?? []) as unknown as RecentRow[]

  return (
    <LocaleProvider locale={locale}>
      <div
        data-site
        lang={locale}
        className="app-glow relative min-h-dvh overflow-x-clip bg-[var(--bg)] text-[var(--text)]"
      >
        <Dashboard
          ov={ov} clubs={clubs} months={months} clubMonths={clubMonths}
          top={top} recent={recent} t={t} locale={locale}
        />
      </div>
    </LocaleProvider>
  )
}

function Dashboard({
  ov, clubs, months, clubMonths, top, recent, t, locale,
}: {
  ov: Overview
  clubs: ClubRow[]
  months: MonthRow[]
  clubMonths: ClubMonthRow[]
  top: TopRow[]
  recent: RecentRow[]
  t: T
  locale: Locale
}) {
  const monthLabel = new Intl.DateTimeFormat(`${locale}-BE`, { month: 'short', timeZone: 'Europe/Brussels' })
  const dayLabel = new Intl.DateTimeFormat(`${locale}-BE`, { day: 'numeric', month: 'short', timeZone: 'Europe/Brussels' })
  const labels = months.map((m) => monthLabel.format(new Date(m.month)).replace('.', ''))

  // ---------------------------------------------------------------- afgeleid
  // Wat de database niet geeft omdat het rekenwerk is en geen gegeven.
  const doorCents = Number(ov.pot_cents) + Number(ov.fee_cents) + Number(ov.bounty_cents)
  const perEntry = ov.entries > 0 ? Math.round(doorCents / ov.entries) : 0
  const perNight = ov.tournaments > 0 ? Math.round(Number(ov.fee_cents) / ov.tournaments) : 0
  const claimShare = ov.players > 0 ? Math.round((ov.players_claimed / ov.players) * 100) : 0
  const activeShare = ov.players > 0 ? Math.round((ov.active_90d / ov.players) * 100) : 0

  // De laatste drie maanden tegenover de drie daarvoor. Eén maand vergelijken
  // met de vorige is ruis — een club die een week later speelde kantelt het
  // hele cijfer.
  const tail = months.slice(-3)
  const prev = months.slice(-6, -3)
  const sum = (rows: MonthRow[], pick: (m: MonthRow) => number) =>
    rows.reduce((a, m) => a + Number(pick(m)), 0)
  const entriesNow = sum(tail, (m) => m.entries)
  const entriesBefore = sum(prev, (m) => m.entries)
  const trend = entriesBefore > 0
    ? Math.round(((entriesNow - entriesBefore) / entriesBefore) * 100)
    : null

  // Omzet, opgeteld over de maanden — de lijn die alleen maar omhoog hoort.
  const cumulative = months.reduce<number[]>((acc, m) => {
    acc.push((acc[acc.length - 1] ?? 0) + Number(m.revenue_cents))
    return acc
  }, [])

  // Spelers, opgeteld: hoeveel mensen ooit een avond speelden.
  const players = months.reduce<number[]>((acc, m) => {
    acc.push((acc[acc.length - 1] ?? 0) + Number(m.new_players))
    return acc
  }, [])

  // Deelnames per club per maand, gestapeld. De clubs in vaste volgorde en in
  // hun eigen kleur, zodat een club niet van kleur verandert wanneer er eentje
  // bijkomt.
  const clubKeys = [...new Set(clubMonths.map((r) => r.slug))]
  const stack = clubKeys.map((slug) => {
    const rows = clubMonths.filter((r) => r.slug === slug)
    return {
      key: slug,
      label: rows[0]?.name ?? slug,
      color: rows[0]?.primary_color || 'var(--accent)',
      values: months.map((m) => rows.find((r) => r.month === m.month)?.entries ?? 0),
    }
  })

  const played = clubs.filter((c) => c.entries > 0)

  return (
    <main className="mx-auto w-full max-w-[92rem] space-y-8 px-4 pb-16 pt-6 sm:px-7 sm:pt-8">
      {/* --------------------------------------------------------------- kop */}
      <header className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <p className="text-[0.7rem] font-semibold uppercase tracking-[0.2em] text-[var(--brand)]">
            ◆ {t('adm.overline')}
          </p>
          <h1 className="mt-1.5 text-[1.9rem] font-semibold leading-tight tracking-tight sm:text-4xl">
            {t('adm.title')}
          </h1>
          <p className="mt-1.5 text-sm text-[var(--text-muted)]">
            {/* De punt van "4 sept." eraf: de zin zet er zelf al een. In het
                Frans stond er anders "le 4 sept.." en dat leest als een fout. */}
            {ov.first_night
              ? t('adm.since').replace('{d}', dayLabel.format(new Date(ov.first_night)).replace(/\.$/, ''))
              : t('adm.noNights')}
          </p>
        </div>
        <div className="flex items-center gap-2">
          <LanguageSwitch current={locale} label={t('common.language')} />
          <Link
            href="/ik"
            className="rounded-full border border-[var(--line-strong)] px-4 py-2 text-sm transition hover:bg-[var(--surface-hover)]"
          >
            {t('adm.toProfile')}
          </Link>
        </div>
      </header>

      {/* ------------------------------------------------------- loopt het? */}
      <section>
        <div className="grid grid-cols-2 gap-2.5 sm:grid-cols-3 lg:grid-cols-6">
          <Tile label={t('adm.clubs')} value={num(ov.clubs)} sub={t('adm.clubsSub').replace('{n}', String(ov.clubs_active))} tone="brand" />
          <Tile label={t('adm.players')} value={num(ov.players)} sub={t('adm.playersSub').replace('{n}', String(claimShare))} />
          <Tile label={t('adm.memberships')} value={num(ov.memberships)} sub={t('adm.multiClub').replace('{n}', String(ov.multi_club))} />
          <Tile label={t('adm.nights')} value={num(ov.tournaments)} sub={t('adm.upcoming').replace('{n}', String(ov.upcoming))} />
          <Tile label={t('adm.entries')} value={num(ov.entries)} sub={t('adm.avgField').replace('{n}', String(ov.avg_field))} tone="accent" />
          <Tile label={t('adm.staff')} value={num(ov.staff)} sub={t('adm.staffSub')} />
        </div>
      </section>

      {/* ------------------------------------------------------- wat het opbrengt */}
      <section className="grid items-start gap-4 lg:grid-cols-[1fr_1.25fr]">
        <div className="grid grid-cols-2 gap-2.5 self-start">
          <Tile label={t('adm.mrr')} value={money(ov.mrr_cents)} sub={t('adm.mrrSub')} tone="ok" />
          <Tile label={t('adm.arr')} value={money(ov.arr_cents)} sub={t('adm.arrSub')} />
          <Tile label={t('adm.revenue')} value={money(ov.revenue_cents)} sub={t('adm.revenueSub')} tone="brand" />
          <Tile label={t('adm.setup')} value={money(ov.setup_cents)} sub={t('adm.setupSub')} />
        </div>

        <Panel
          title={t('adm.revenueChart')}
          right={
            <span className="flex items-baseline gap-2">
              <span className="tnum text-sm font-semibold">{money(cumulative[cumulative.length - 1] ?? 0)}</span>
              <span className="text-xs text-[var(--text-faint)]">{t('adm.months12')}</span>
            </span>
          }
        >
          <AreaLine
            labels={labels}
            values={cumulative}
            format={(v) => money(v)}
            color="var(--brand)"
            caption={t('adm.revenueChart')}
          />
          <p className="mt-3 border-t border-[var(--line)] pt-3 text-xs leading-relaxed text-[var(--text-muted)]">
            {t('adm.revenueNote')}
          </p>
        </Panel>
      </section>

      {/* --------------------------------------------------- hoeveel geld er rondgaat */}
      <section className="grid items-start gap-4 lg:grid-cols-2">
        <Panel
          title={t('adm.doorChart')}
          right={<span className="tnum text-sm font-semibold">{money(doorCents)}</span>}
        >
          <StackedMonths
            labels={labels}
            format={(v) => money(v)}
            emptyLabel={t('adm.nothingYet')}
            wideLabels
            series={[
              { key: 'pot', label: t('adm.pot'), color: 'var(--accent)', values: months.map((m) => Number(m.pot_cents)) },
              { key: 'fee', label: t('adm.fee'), color: 'var(--brand)', values: months.map((m) => Number(m.fee_cents)) },
            ]}
          />
          <p className="mt-3 text-xs leading-relaxed text-[var(--text-muted)]">
            {t('adm.doorNote')}
          </p>
        </Panel>

        <Panel
          title={t('adm.entriesChart')}
          right={
            trend !== null && (
              <span className={`text-sm font-medium ${trend >= 0 ? 'text-[var(--ok)]' : 'text-[var(--danger)]'}`}>
                {trend >= 0 ? '+' : ''}{trend}% <span className="text-[var(--text-faint)]">{t('adm.vsBefore')}</span>
              </span>
            )
          }
        >
          <StackedMonths
            labels={labels}
            format={(v) => num(v)}
            emptyLabel={t('adm.nothingYet')}
            series={stack}
          />
        </Panel>
      </section>

      {/* ------------------------------------------------------------ inzichten */}
      <section>
        <div className="grid grid-cols-2 gap-2.5 sm:grid-cols-3 lg:grid-cols-5">
          <Tile label={t('adm.perEntry')} value={money(perEntry)} sub={t('adm.perEntrySub')} />
          <Tile label={t('adm.perNight')} value={money(perNight)} sub={t('adm.perNightSub')} />
          <Tile label={t('adm.active90')} value={`${activeShare}%`} sub={t('adm.active90Sub').replace('{n}', String(ov.active_90d))} />
          <Tile label={t('adm.active30')} value={num(ov.active_30d)} sub={t('adm.active30Sub').replace('{n}', String(ov.entries_30d))} />
          <Tile label={t('adm.newPlayers')} value={num(ov.new_players_30d)} sub={t('adm.newPlayersSub')} />
        </div>
      </section>

      {/* --------------------------------------------------------------- clubs */}
      <section className="grid items-start gap-4 lg:grid-cols-[1.35fr_1fr]">
        <Panel title={t('adm.perClub')}>
          <div className="-mx-1 overflow-x-auto">
            <table className="w-full min-w-[38rem] border-collapse text-sm">
              <thead>
                <tr className="text-left text-[0.65rem] uppercase tracking-[0.14em] text-[var(--text-faint)]">
                  <th className="px-1 pb-2 font-medium">{t('adm.club')}</th>
                  <th className="px-1 pb-2 text-right font-medium">{t('adm.members')}</th>
                  <th className="px-1 pb-2 text-right font-medium">{t('adm.nightsShort')}</th>
                  <th className="px-1 pb-2 text-right font-medium">{t('adm.entriesShort')}</th>
                  <th className="px-1 pb-2 text-right font-medium">{t('adm.fieldShort')}</th>
                  <th className="px-1 pb-2 text-right font-medium">{t('adm.feeShort')}</th>
                  <th className="px-1 pb-2 text-right font-medium">{t('adm.lastShort')}</th>
                </tr>
              </thead>
              <tbody>
                {clubs.map((c) => (
                  <tr key={c.slug} className="border-t border-[var(--line)]">
                    <td className="px-1 py-2.5">
                      <span className="flex items-center gap-2">
                        <span
                          aria-hidden
                          className="size-2.5 shrink-0 rounded-full"
                          style={{ background: c.primary_color || 'var(--accent)' }}
                        />
                        <span className="min-w-0">
                          <Link href={`/c/${c.slug}`} className="font-medium hover:underline">{c.name}</Link>
                          {c.city && <span className="ml-1.5 text-xs text-[var(--text-faint)]">{c.city}</span>}
                        </span>
                      </span>
                    </td>
                    <td className="tnum px-1 py-2.5 text-right">
                      {num(c.members)}
                      <span className="ml-1 text-xs text-[var(--text-faint)]">/ {num(c.claimed)}</span>
                    </td>
                    <td className="tnum px-1 py-2.5 text-right">{num(c.tournaments)}</td>
                    <td className="tnum px-1 py-2.5 text-right">{num(c.entries)}</td>
                    <td className="tnum px-1 py-2.5 text-right text-[var(--text-muted)]">{c.avg_field}</td>
                    <td className="tnum px-1 py-2.5 text-right">{money(c.fee_cents)}</td>
                    <td className="px-1 py-2.5 text-right text-xs text-[var(--text-muted)]">
                      {c.last_night ? dayLabel.format(new Date(c.last_night)) : '—'}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <p className="mt-3 text-xs text-[var(--text-faint)]">{t('adm.perClubNote')}</p>
        </Panel>

        <div className="space-y-4">
          <Panel title={t('adm.shareChart')}>
            <ClubBars
              format={(v) => num(v)}
              emptyLabel={t('adm.nothingYet')}
              rows={played.map((c) => ({
                label: c.name,
                value: c.entries,
                color: c.primary_color || 'var(--accent)',
                sub: t('adm.nightsCount').replace('{n}', String(c.tournaments)),
              }))}
            />
          </Panel>

          <Panel title={t('adm.recent')}>
            {recent.length === 0 ? (
              <p className="text-sm text-[var(--text-faint)]">{t('adm.nothingYet')}</p>
            ) : (
              <ul className="divide-y divide-[var(--line)]">
                {recent.map((r, i) => (
                  <li key={i} className="flex items-center gap-3 py-2.5 first:pt-0 last:pb-0">
                    <span
                      aria-hidden
                      className="size-2.5 shrink-0 rounded-full"
                      style={{ background: r.primary_color || 'var(--accent)' }}
                    />
                    <span className="min-w-0 flex-1">
                      <span className="block truncate text-sm font-medium">{r.name}</span>
                      <span className="block truncate text-xs text-[var(--text-faint)]">
                        {r.club} · {dayLabel.format(new Date(r.played_on))}
                        {r.winner && ` · ${t('adm.won')} ${r.winner}`}
                      </span>
                    </span>
                    <span className="shrink-0 text-right">
                      <span className="tnum block text-sm">{num(r.entries)}</span>
                      <span className="tnum block text-xs text-[var(--text-faint)]">{money(r.pot_cents)}</span>
                    </span>
                  </li>
                ))}
              </ul>
            )}
          </Panel>
        </div>
      </section>

      {/* -------------------------------------------------------------- mensen */}
      <section className="grid items-start gap-4 lg:grid-cols-2">
        <Panel title={t('adm.growth')} right={<span className="tnum text-sm font-semibold">{num(players[players.length - 1] ?? 0)}</span>}>
          <AreaLine
            labels={labels}
            values={players}
            format={(v) => num(v)}
            color="var(--accent)"
            caption={t('adm.growth')}
          />
          <p className="mt-3 border-t border-[var(--line)] pt-3 text-xs leading-relaxed text-[var(--text-muted)]">
            {t('adm.growthNote')}
          </p>
        </Panel>

        <Panel title={t('adm.topPlayers')}>
          {top.length === 0 ? (
            <p className="text-sm text-[var(--text-faint)]">{t('adm.nothingYet')}</p>
          ) : (
            <ul className="divide-y divide-[var(--line)]">
              {top.map((p, i) => (
                <li key={i} className="flex items-center gap-3 py-2 first:pt-0 last:pb-0">
                  <span className="tnum w-5 shrink-0 text-xs text-[var(--text-faint)]">{i + 1}</span>
                  <span className="min-w-0 flex-1">
                    <span className="block truncate text-sm font-medium">{p.display_name}</span>
                    <span className="block text-xs text-[var(--text-faint)]">
                      {t('adm.nightsCount').replace('{n}', String(p.entries))}
                      {p.wins > 0 && ` · ${t('adm.winsCount').replace('{n}', String(p.wins))}`}
                      {p.clubs > 1 && ` · ${t('adm.clubsCount').replace('{n}', String(p.clubs))}`}
                    </span>
                  </span>
                  <span
                    className={`tnum shrink-0 text-sm ${
                      Number(p.net_cents) > 0 ? 'text-[var(--ok)]'
                        : Number(p.net_cents) < 0 ? 'text-[var(--danger)]' : 'text-[var(--text-muted)]'
                    }`}
                  >
                    {Number(p.net_cents) > 0 ? '+' : ''}{money(p.net_cents)}
                  </span>
                </li>
              ))}
            </ul>
          )}
          <p className="mt-3 border-t border-[var(--line)] pt-3 text-xs leading-relaxed text-[var(--text-muted)]">
            {t('adm.topNote')}
          </p>
        </Panel>
      </section>

      <footer className="border-t border-[var(--line)] pt-5 text-xs text-[var(--text-faint)]">
        {t('adm.footer')}
      </footer>
    </main>
  )
}
