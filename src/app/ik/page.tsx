import Link from 'next/link'
import { redirect } from 'next/navigation'
import { MyClubs, type MyClubRow } from '@/components/MyClubs'
import { MyLive, type LiveRow } from '@/components/MyLive'
import { PlayerNav } from '@/components/PlayerNav'
import { PlayerCharts } from '@/components/PlayerCharts'
import { Card, Notice } from '@/components/ui'
import { LocaleProvider } from '@/lib/i18n/context'
import { translator } from '@/lib/i18n/dictionaries'
import { publicLocale } from '@/lib/i18n/server'
import { createClient } from '@/lib/supabase/server'
import { formatMoney } from '@/lib/types'

/**
 * De spelerspagina.
 *
 * Wat een speler hier komt halen is niet zijn profiel maar zijn geschiedenis:
 * waar hij speelde, hoe hij eindigde, en hoeveel dat opbracht — over alle
 * clubs heen. Dat laatste is het enige wat geen enkele club hem kan tonen, en
 * dus de reden dat dit platform bestaat. Vandaar dat de resultaten bovenaan
 * staan en de instellingen eronder.
 *
 * Bij elk bezoek wordt het profiel opnieuw opgeeist. Dat klinkt overbodig maar
 * is het niet: iemand kan zich vandaag registreren en pas volgende week door
 * de floor aan de deur worden ingetikt. Op dat moment ontstaat er een tweede
 * rij op hetzelfde mailadres, en de eerstvolgende keer dat hij hier komt wordt
 * die alsnog aan hem gekoppeld. De functie is met opzet zo geschreven dat
 * tienmaal aanroepen hetzelfde doet als eenmaal.
 */

interface Me {
  id: string
  display_name: string
  first_name: string | null
  last_name: string | null
  username: string | null
  email: string | null
  locale: string
  public_listing: boolean
  public_profile: boolean
  onboarded_at: string | null
  clubs_count: number
  results_count: number
}

interface ClubRow {
  slug: string
  name: string
  city: string | null
  logo_url: string | null
  primary_color: string | null
}

/** Wat deze speler bij één club heeft staan. Zie migratie 0031. */
interface ClubStat {
  club_slug: string
  club_name: string
  club_city: string | null
  logo_url: string | null
  tournaments: number
  points: number
  best_position: number
  cashes: number
  knockouts: number
  prize_cents: number
  rank: number
  of_players: number
  last_played: string | null
}

interface StaffRow {
  slug: string
  name: string
  logo_url: string | null
  role: string
}

interface ResultRow {
  tournament_id: string
  tournament: string
  club_name: string
  club_slug: string
  played_on: string
  place: number
  entries: number
  prize_cents: number
  spent_cents: number
  points: number
  knockouts: number
}

export async function generateMetadata() {
  return { title: translator(await publicLocale())('me.title') }
}

export default async function Page() {
  const supabase = await createClient()
  const { data: claims } = await supabase.auth.getClaims()
  if (!claims?.claims) redirect('/login?next=/ik')

  const locale = await publicLocale()
  const t = translator(locale)

  // Ophalen of aanmaken. Zie de uitleg hierboven.
  //
  // De fout hiervan werd vroeger weggegooid, en dat kostte een avond zoeken:
  // ging het opeisen mis, dan zag de speler alleen "we konden je profiel niet
  // vinden of aanmaken" — een zin die klopt en niets zegt. Wat er misging
  // stond in een variabele die niemand las.
  const claim = await supabase.rpc('claim_my_player', {})

  // 28000: het token is geldig, maar het account erachter bestaat niet meer —
  // verwijderd terwijl deze browser nog aangemeld was. Zonder dit blijft
  // dezelfde fout bij elke verversing terugkomen en komt niemand er nog uit
  // zonder zijn koekjes te wissen. Zie migratie 0039.
  if (claim.error?.code === '28000') {
    await supabase.auth.signOut()
    redirect('/login?verlopen=1')
  }

  const [meRes, resultsRes, clubsRes, staffRes, statsRes, liveRes, discoverRes] = await Promise.all([
    supabase.rpc('my_player'),
    supabase.rpc('my_results'),
    supabase.rpc('my_clubs'),
    supabase.rpc('my_staff_clubs'),
    supabase.rpc('my_club_stats', {}),
    supabase.rpc('my_live_tournaments'),
    supabase.rpc('clubs_open_to_join'),
  ])

  const me = ((meRes.data ?? []) as unknown as Me[])[0] ?? null
  const results = (resultsRes.data ?? []) as unknown as ResultRow[]
  const clubs = (clubsRes.data ?? []) as unknown as ClubRow[]
  const staff = (staffRes.data ?? []) as unknown as StaffRow[]
  const stats = (statsRes.data ?? []) as unknown as ClubStat[]
  const live = (liveRes.data ?? []) as unknown as LiveRow[]
  const discover = (discoverRes.data ?? []) as unknown as {
    slug: string; name: string; city: string | null; logo_url: string | null
    intro: string | null; members: number
  }[]

  // Lidmaatschap en resultaten zijn twee verschillende dingen, en ze lopen
  // niet gelijk. Je bent lid vanaf het moment dat de floor je toevoegt; je
  // hebt pas cijfers nadat er een avond afgesloten is. Een club waar je vorige
  // week voor het eerst was hoort dus in de lijst te staan, met een lege
  // regel — anders lijkt het alsof je er niet bij hoort.
  const byClub = new Map(stats.map((s) => [s.club_slug, s]))
  const mijnClubs: MyClubRow[] = [
    ...clubs.map((c) => {
      const st = byClub.get(c.slug)
      return {
        slug: c.slug, name: c.name, city: c.city, logo_url: c.logo_url,
        primary_color: c.primary_color,
        rank: st?.rank ?? null, of_players: st?.of_players ?? null,
        tournaments: st?.tournaments ?? 0, points: Number(st?.points ?? 0),
        prize_cents: Number(st?.prize_cents ?? 0),
      }
    }),
    // En omgekeerd: wie ergens speelde maar uit het ledenbestand verdween,
    // heeft daar wél een verleden. Dat hoor je niet stil te laten vallen.
    ...stats
      .filter((s) => !clubs.some((c) => c.slug === s.club_slug))
      .map((s) => ({
        slug: s.club_slug, name: s.club_name, city: s.club_city, logo_url: s.logo_url,
        primary_color: null as string | null,
        rank: s.rank, of_players: s.of_players, tournaments: s.tournaments,
        points: Number(s.points), prize_cents: Number(s.prize_cents),
      })),
  ]

  if (!me) {
    return (
      <LocaleProvider locale={locale}>
        <main className="mx-auto max-w-2xl px-5 py-10">
          <Notice tone="error">
            {t('me.noProfile')}
            {(claim.error ?? meRes.error) && (
              <span className="mt-2 block text-xs opacity-80">
                {(claim.error ?? meRes.error)?.message}
              </span>
            )}
          </Notice>
          <p className="mt-4 text-center text-sm">
            <Link href="/welkom" className="text-[var(--brand)] underline-offset-4 hover:underline">
              {t('me.retry')} →
            </Link>
          </p>
        </main>
      </LocaleProvider>
    )
  }

  // Nog nooit door het welkomstscherm geweest? Dan eerst daarheen. Zonder
  // clubs en zonder resultaten is deze pagina een rij nullen, en dat is geen
  // begin maar een foutmelding zonder tekst.
  if (!me.onboarded_at) redirect('/welkom')

  const totalPrize = results.reduce((s, r) => s + Number(r.prize_cents ?? 0), 0)
  const totalSpent = results.reduce((s, r) => s + Number(r.spent_cents ?? 0), 0)
  const net = totalPrize - totalSpent
  const wins = results.filter((r) => r.place === 1).length
  const cashes = results.filter((r) => Number(r.prize_cents ?? 0) > 0).length
  const itm = results.length > 0 ? Math.round((cashes / results.length) * 100) : 0
  const best = results.length > 0 ? Math.min(...results.map((r) => r.place)) : null
  const points = results.reduce((s, r) => s + Number(r.points ?? 0), 0)

  const fmt = new Intl.DateTimeFormat(`${locale}-BE`, {
    day: 'numeric', month: 'short', year: 'numeric', timeZone: 'Europe/Brussels',
  })

  return (
    <LocaleProvider locale={locale}>
      <div data-site lang={locale} className="min-h-dvh bg-[var(--bg)] text-[var(--text)]">
        <PlayerNav locale={locale} t={t} active="home" />

        <main className="mx-auto max-w-3xl space-y-6 px-4 py-6 sm:px-5 sm:py-7">
          <div>
            <h1 className="text-2xl font-semibold tracking-tight sm:text-3xl">
              {me.display_name}
            </h1>
            <p className="mt-1 text-sm text-[var(--text-faint)]">
              {me.username && <span>@{me.username} · </span>}
              {t('nav.signedInAs')} {me.email}
            </p>
            {/* Eén regel die zegt wat deze pagina is. Zonder die regel is dit
                gewoon "een tweede site met ook iets van mij erop" — en dat is
                precies de verwarring die dit platform veroorzaakte. */}
            <p className="mt-2 max-w-prose text-sm leading-relaxed text-[var(--text-muted)]">
              {t('me.lede')}
            </p>
          </div>

          {/* ------------------------------------------------ nu aan tafel
              Boven alles, want zolang je speelt is dit het enige op deze
              pagina dat op dat moment telt. Speel je niet, dan staat er
              niets. */}
          <MyLive rows={live} />

          {/* --------------------------------------------------- de cijfers
              Netto krijgt de volle breedte en een kleur. Dat is het enige
              getal waar een pokerspeler op terugkomt; prijzengeld zonder
              inleg ernaast is structureel te mooi. */}
          {results.length > 0 && (
            <>
              <section className="rounded-[var(--radius)] border border-[var(--line)] bg-[var(--surface)] p-5">
                <p className="text-xs uppercase tracking-[0.22em] text-[var(--text-faint)]">
                  {t('me.net')}
                </p>
                <p
                  className={`tnum mt-1 text-4xl font-semibold tracking-tight sm:text-5xl ${
                    net > 0 ? 'text-[var(--ok)]' : net < 0 ? 'text-[var(--danger)]' : ''
                  }`}
                >
                  {net > 0 ? '+' : ''}{formatMoney(net, 'EUR')}
                </p>
                <p className="tnum mt-1 text-sm text-[var(--text-faint)]">
                  {formatMoney(totalPrize, 'EUR')} {t('me.won').toLowerCase()} ·{' '}
                  {formatMoney(totalSpent, 'EUR')} {t('me.spent').toLowerCase()}
                </p>
              </section>

              <PlayerCharts rows={results} t={t} locale={locale} />

              <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
                <Stat label={t('me.played')} value={String(results.length)} />
                <Stat label={t('me.wins')} value={String(wins)} />
                <Stat label={t('me.itm')} value={`${itm}%`} sub={`${cashes}×`} />
                <Stat
                  label={t('me.bestPlace')}
                  value={best ? `${best}e` : '—'}
                  sub={`${Math.round(points)} ${t('me.points').toLowerCase()}`}
                />
              </div>
            </>
          )}

          {/* ----------------------------------------------------- mijn clubs
              Speler zijn bij een club en medewerker zijn van een club zijn
              twee losse dingen, en wie net een account maakte is meestal geen
              van beide. Dan is "0 clubs" geen informatie maar een raadsel —
              vandaar dat er ook zonder clubs iets staat, met de deur naar de
              rest erbij. */}
          <MyClubs mine={mijnClubs} discover={discover} />

          {/* ------------------------------------------------------ personeel
              Beheer je een club, dan hangt dat aan het account dat die club
              als bestuur heeft opgegeven — en dat hoeft niet hetzelfde account
              te zijn als waarmee je speelt. Zolang dat nergens staat kan een
              scherm heel redelijk niets tonen zonder dat iemand begrijpt
              waarom. Precies dat is misgelopen bij de uitnodigingen. */}
          {staff.length > 0 ? (
            <section className="rounded-[var(--radius)] border border-[var(--line)] bg-[var(--surface)] p-4 sm:p-5">
              <h2 className="text-xs uppercase tracking-[0.22em] text-[var(--text-faint)]">
                {t('me.staffAt')}
              </h2>
              <p className="mt-1.5 text-sm leading-relaxed text-[var(--text-muted)]">
                {t('me.staffBody')}
              </p>
              <ul className="mt-3 flex flex-wrap gap-2">
                {staff.map((c) => (
                  <li key={c.slug}>
                    <Link
                      href={`/c/${c.slug}`}
                      className="inline-flex items-center gap-2 rounded-full bg-[var(--brand)] px-4 py-2 text-sm font-medium text-[var(--on-brand)] transition hover:brightness-110"
                    >
                      {t('me.manage')} {c.name} →
                    </Link>
                  </li>
                ))}
              </ul>
            </section>
          ) : (
            <p className="text-xs leading-relaxed text-[var(--text-faint)]">
              {t('me.staffElsewhere')}
            </p>
          )}

          {/* ------------------------------------------------- de resultaten */}
          <section>
            <h2 className="mb-2 text-xs uppercase tracking-[0.22em] text-[var(--text-faint)]">
              {t('me.results')}
            </h2>

            {results.length === 0 ? (
              <Card>
                <p className="text-sm leading-relaxed text-[var(--text-muted)]">{t('me.noResults')}</p>
                <Link
                  href="/clubs"
                  className="mt-3 inline-block text-sm text-[var(--brand)] underline-offset-4 hover:underline"
                >
                  {t('me.findClub')} →
                </Link>
              </Card>
            ) : (
              <div className="overflow-hidden rounded-[var(--radius)] border border-[var(--line)] bg-[var(--surface)]">
                <table className="w-full text-left">
                  <thead className="hidden sm:table-header-group">
                    <tr className="border-b border-[var(--line)] text-[0.65rem] uppercase tracking-[0.2em] text-[var(--text-faint)]">
                      <th className="px-4 py-3 font-medium">{t('me.tournament')}</th>
                      <th className="w-20 px-2 py-3 text-right font-medium">{t('me.place')}</th>
                      <th className="w-24 px-2 py-3 text-right font-medium">{t('me.prize')}</th>
                      <th className="w-20 px-4 py-3 text-right font-medium">{t('pub.pts')}</th>
                    </tr>
                  </thead>
                  <tbody>
                    {results.map((r) => (
                      <tr key={r.tournament_id} className="border-b border-[var(--line)] last:border-0">
                        <td className="px-4 py-3 align-baseline">
                          <span className="block truncate font-medium">{r.tournament}</span>
                          <span className="block text-xs text-[var(--text-faint)]">
                            {r.club_name} · {fmt.format(new Date(r.played_on))}
                          </span>
                          <span className="tnum block text-xs text-[var(--text-faint)] sm:hidden">
                            {r.place} / {r.entries}
                            {r.prize_cents > 0 ? ` · ${formatMoney(r.prize_cents, 'EUR')}` : ''}
                            {` · ${Math.round(Number(r.points))} ${t('pub.pts')}`}
                          </span>
                        </td>
                        <td className="tnum hidden px-2 py-3 text-right align-baseline text-sm sm:table-cell">
                          {r.place}
                          <span className="text-[var(--text-faint)]"> / {r.entries}</span>
                        </td>
                        <td className="tnum hidden px-2 py-3 text-right align-baseline text-sm sm:table-cell">
                          {r.prize_cents > 0 ? formatMoney(r.prize_cents, 'EUR') : '—'}
                        </td>
                        <td className="tnum hidden px-4 py-3 text-right align-baseline font-semibold sm:table-cell">
                          {Math.round(Number(r.points))}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </section>

          {/* Gegevens staan niet meer onderaan deze pagina maar op /ik/gegevens.
              Ze stonden hier onder de resultaten: je scrolt er bij elk bezoek
              overheen terwijl je er hooguit twee keer per jaar iets wijzigt. */}
          <p className="pt-1 text-center text-sm">
            <Link
              href="/ik/gegevens"
              className="text-[var(--text-muted)] underline-offset-4 hover:text-[var(--text)] hover:underline"
            >
              {t('me.navSettings')} →
            </Link>
          </p>
        </main>
      </div>
    </LocaleProvider>
  )
}

function Stat({ label, value, sub }: { label: string; value: string; sub?: string }) {
  return (
    <div className="rounded-[var(--radius)] border border-[var(--line)] bg-[var(--surface)] p-4">
      <p className="text-[0.6rem] uppercase tracking-[0.18em] text-[var(--text-faint)]">{label}</p>
      <p className="tnum mt-1 text-2xl font-semibold leading-tight">{value}</p>
      {sub && <p className="tnum mt-0.5 text-xs text-[var(--text-faint)]">{sub}</p>}
    </div>
  )
}
