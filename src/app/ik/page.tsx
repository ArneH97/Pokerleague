import Link from 'next/link'
import { redirect } from 'next/navigation'
import { LanguageSwitch } from '@/components/LanguageSwitch'
import { PlayerProfileForm } from '@/components/PlayerProfileForm'
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
  clubs_count: number
  results_count: number
}

interface ClubRow {
  slug: string
  name: string
  city: string | null
  logo_url: string | null
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
  await supabase.rpc('claim_my_player', {})

  const [meRes, resultsRes, clubsRes, staffRes] = await Promise.all([
    supabase.rpc('my_player'),
    supabase.rpc('my_results'),
    supabase.rpc('my_clubs'),
    supabase.rpc('my_staff_clubs'),
  ])

  const me = ((meRes.data ?? []) as unknown as Me[])[0] ?? null
  const results = (resultsRes.data ?? []) as unknown as ResultRow[]
  const clubs = (clubsRes.data ?? []) as unknown as ClubRow[]
  const staff = (staffRes.data ?? []) as unknown as StaffRow[]

  if (!me) {
    return (
      <LocaleProvider locale={locale}>
        <main className="mx-auto max-w-2xl px-5 py-10">
          <Notice tone="error">{meRes.error?.message ?? t('me.noProfile')}</Notice>
        </main>
      </LocaleProvider>
    )
  }

  const totalPrize = results.reduce((s, r) => s + (r.prize_cents ?? 0), 0)
  const wins = results.filter((r) => r.place === 1).length
  const cashes = results.filter((r) => (r.prize_cents ?? 0) > 0).length

  const fmt = new Intl.DateTimeFormat(`${locale}-BE`, {
    day: 'numeric', month: 'short', year: 'numeric', timeZone: 'Europe/Brussels',
  })

  return (
    <LocaleProvider locale={locale}>
      <div data-site lang={locale} className="min-h-dvh bg-[var(--bg)] text-[var(--text)]">
        <header className="border-b border-[var(--line)]">
          <div className="mx-auto flex max-w-3xl items-center gap-3 px-5 py-4">
            <Link href="/" className="text-sm font-semibold tracking-[0.18em]">POKERLEAGUE</Link>
            <span className="flex-1" />
            <LanguageSwitch current={locale} label={t('common.language')} />
            <form action="/auth/signout" method="post">
              <button className="rounded-full px-3 py-1.5 text-sm text-[var(--text-muted)] transition hover:bg-[var(--surface-hover)] hover:text-[var(--text)]">
                {t('common.signOut')}
              </button>
            </form>
          </div>
        </header>

        <main className="mx-auto max-w-3xl space-y-5 px-5 py-7">
          <div>
            <h1 className="text-3xl font-semibold tracking-tight">{me.display_name}</h1>
            {me.username && (
              <p className="mt-1 text-sm text-[var(--text-faint)]">@{me.username}</p>
            )}
          </div>

          {/* --------------------------------------------------- waar hoor ik
              De vraag die deze pagina eerst onbeantwoord liet. Speler zijn bij
              een club en medewerker zijn van een club zijn twee losse dingen,
              en wie net een account maakte is meestal geen van beide. Dan is
              "0 clubs" geen informatie maar een raadsel. */}
          <section className="rounded-[var(--radius)] border border-[var(--line)] bg-[var(--surface)] p-5">
            <h2 className="text-xs uppercase tracking-[0.22em] text-[var(--text-faint)]">
              {t('me.where')}
            </h2>

            {clubs.length === 0 ? (
              <p className="mt-2 text-sm leading-relaxed text-[var(--text-muted)]">
                {t('me.noClubs')}
              </p>
            ) : (
              <ul className="mt-3 space-y-1.5">
                {clubs.map((c) => (
                  <li key={c.slug}>
                    <Link
                      href={`/c/${c.slug}`}
                      className="text-sm underline-offset-4 hover:underline"
                    >
                      {c.name}
                      {c.city ? <span className="text-[var(--text-faint)]"> · {c.city}</span> : null}
                    </Link>
                  </li>
                ))}
              </ul>
            )}

            {staff.length > 0 && (
              <div className="mt-5 border-t border-[var(--line)] pt-4">
                <h3 className="text-xs uppercase tracking-[0.22em] text-[var(--text-faint)]">
                  {t('me.staffAt')}
                </h3>
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
              </div>
            )}
          </section>

          {/* --------------------------------------------------- de cijfers */}
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
            <Stat label={t('me.played')} value={String(results.length)} />
            <Stat label={t('me.wins')} value={String(wins)} />
            <Stat label={t('me.cashes')} value={String(cashes)} />
            <Stat label={t('me.won')} value={formatMoney(totalPrize, 'EUR')} />
          </div>

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

          {/* ---------------------------------------------------- instellingen */}
          <PlayerProfileForm
            me={{
              first_name: me.first_name,
              last_name: me.last_name,
              username: me.username,
              email: me.email,
              public_listing: me.public_listing,
              public_profile: me.public_profile,
            }}
          />
        </main>
      </div>
    </LocaleProvider>
  )
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-[var(--radius)] border border-[var(--line)] bg-[var(--surface)] p-4">
      <p className="text-[0.6rem] uppercase tracking-[0.18em] text-[var(--text-faint)]">{label}</p>
      <p className="tnum mt-1 text-2xl font-semibold leading-tight">{value}</p>
    </div>
  )
}
