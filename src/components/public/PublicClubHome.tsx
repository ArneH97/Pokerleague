import Link from 'next/link'
import { DaysToGo } from '@/components/public/DaysToGo'
import { ClubMasthead, PublicShell } from '@/components/public/PublicShell'
import type { Club } from '@/lib/club'
import { translator, type Locale } from '@/lib/i18n/dictionaries'
import {
  getPublicClock, getPublicResult, getPublicStandings, getPublicTournaments,
} from '@/lib/publicClub'
import { formatMoney } from '@/lib/types'

/**
 * De voorpagina van een club voor wie niet inlogt.
 *
 * Eén vraag staat voorop en dat is niet "wie zijn wij" maar "wat is er nu".
 * Loopt er een avond, dan krijgt die het bovenstuk mét de cijfers erbij —
 * spelers over, prijzenpot, rebuys. Een kaart die alleen een naam toont is
 * een link vermomd als kaart.
 *
 * De indeling verandert mee met wat er te tonen valt, en dat is met opzet.
 * Een vaste kolomindeling ziet er goed uit op de dag dat alles gevuld is en
 * kapot op elke andere dag: een club die pas opent heeft geen klassement, en
 * dan staat er een lege rechterhelft naast een aankondiging. Voor de opening
 * is de aankondiging dus de volle breedte, met daaronder twee gelijke kaarten
 * die zeggen wat er komt. Draait de club eenmaal, dan gaat het naar twee
 * kolommen: de avond links, het klassement rechts.
 */
export async function PublicClubHome({ club, locale }: { club: Club; locale: Locale }) {
  const t = translator(locale)

  const [all, standings] = await Promise.all([
    getPublicTournaments(club.id, 30),
    getPublicStandings(club.slug),
  ])

  const live = all.find((x) => x.status === 'running' || x.status === 'paused')
  const next = all.filter((x) => x.status === 'scheduled').at(-1)
  const last = all.find((x) => x.status === 'finished')
  const top = standings.slice(0, 8)

  const [liveClock, lastResult] = await Promise.all([
    live ? getPublicClock(live.id) : Promise.resolve(null),
    last ? getPublicResult(last.id) : Promise.resolve([]),
  ])
  const winner = lastResult.find((r) => r.place === 1) ?? null

  const fmtLong = new Intl.DateTimeFormat(`${locale}-BE`, {
    weekday: 'long', day: 'numeric', month: 'long',
    hour: '2-digit', minute: '2-digit', timeZone: club.timezone,
  })
  const fmtDay = new Intl.DateTimeFormat(`${locale}-BE`, {
    weekday: 'long', day: 'numeric', month: 'long', timeZone: club.timezone,
  })

  const opensOn = club.opens_on ? new Date(`${club.opens_on}T00:00:00`) : null
  const preOpening = opensOn !== null && all.length === 0 && standings.length === 0

  // ------------------------------------------------------------- opening ---
  if (preOpening) {
    return (
      <PublicShell club={club} locale={locale} active="home">
        <ClubMasthead club={club} locale={locale} />

        <section className="mt-5 overflow-hidden rounded-3xl border border-[var(--brand)] bg-[color-mix(in_oklab,var(--brand)_10%,transparent)] px-5 py-8 sm:px-8 sm:py-10 lg:px-12 lg:py-14">
          <p className="text-xs uppercase tracking-[0.22em] text-[var(--brand)]">
            {t('pub.opening')}
          </p>
          <p className="mt-3 text-4xl font-semibold leading-[1.05] tracking-tight sm:text-5xl lg:text-6xl">
            {fmtDay.format(opensOn)}
          </p>
          <DaysToGo date={club.opens_on as string} />
          <p className="mt-5 max-w-prose text-sm leading-relaxed text-[var(--text-muted)] sm:text-base">
            {t('pub.openingBody')}
          </p>
        </section>

        {/* Twee gelijke kaarten in plaats van één korte naast een lege helft. */}
        <div className="mt-4 grid gap-4 sm:grid-cols-2">
          <Soon title={t('pub.calendar')} body={t('pub.calendarSoon')}
                href={`/c/${club.slug}/kalender`} />
          <Soon title={t('pub.standings')} body={t('pub.standingsSoon')}
                href={`/c/${club.slug}/klassement`} />
        </div>
      </PublicShell>
    )
  }

  // ---------------------------------------------------------- gewone dag ---
  return (
    <PublicShell club={club} locale={locale} active="home">
      <ClubMasthead club={club} locale={locale} />

      <div className="mt-5 grid gap-4 lg:grid-cols-5">
        <div className="space-y-4 lg:col-span-3">
          {live && liveClock ? (
            <Link
              href={`/c/${club.slug}/live/${live.id}`}
              className="block rounded-3xl border border-[var(--brand)] bg-[color-mix(in_oklab,var(--brand)_12%,transparent)] p-5 transition hover:brightness-110 sm:p-7"
            >
              <span className="flex items-center gap-2 text-xs uppercase tracking-[0.22em] text-[var(--brand)]">
                <span className="inline-block size-2 animate-pulse rounded-full bg-[var(--brand)]" />
                {t('pub.nowPlaying')}
              </span>
              <span className="mt-2 block text-2xl font-semibold sm:text-3xl">{live.name}</span>

              <span className="mt-5 grid grid-cols-3 gap-3">
                <Stat label={t('clock.playersLeft')} value={`${liveClock.players_left}`}
                      sub={`${t('common.of')} ${liveClock.entries}`} />
                <Stat label={t('clock.prizePool')}
                      value={formatMoney(liveClock.prize_pool_cents, club.currency)} />
                <Stat label={t('pub.rebuys')} value={`${liveClock.rebuys}`} />
              </span>

              <span className="mt-5 block text-sm text-[var(--text-muted)]">
                {t('pub.followLive')} →
              </span>
            </Link>
          ) : next ? (
            <section className="rounded-3xl border border-[var(--line)] bg-[var(--surface)] p-5 sm:p-7">
              <p className="text-xs uppercase tracking-[0.22em] text-[var(--text-faint)]">
                {t('pub.nextUp')}
              </p>
              <p className="mt-2 text-2xl font-semibold sm:text-3xl">{next.name}</p>
              <p className="mt-1 text-[var(--text-muted)]">
                {fmtLong.format(new Date(next.scheduled_at))}
              </p>
              <p className="tnum mt-5 text-sm text-[var(--text-faint)]">
                {t('pub.entry')} {formatMoney(next.buyin_cents + next.fee_cents, club.currency)}
              </p>
            </section>
          ) : (
            <section className="rounded-3xl border border-[var(--line)] bg-[var(--surface)] p-7">
              <p className="text-[var(--text-muted)]">{t('pub.nothingPlanned')}</p>
            </section>
          )}

          {last && (
            <Link
              href={`/c/${club.slug}/live/${last.id}`}
              className="flex items-center gap-3 rounded-3xl border border-[var(--line)] bg-[var(--surface)] px-5 py-4 transition hover:bg-[var(--surface-hover)]"
            >
              <span className="min-w-0 flex-1">
                <span className="block text-xs uppercase tracking-[0.22em] text-[var(--text-faint)]">
                  {t('pub.lastResult')}
                </span>
                <span className="mt-0.5 block truncate font-medium">{last.name}</span>
                {winner && (
                  <span className="mt-0.5 block truncate text-sm text-[var(--text-muted)]">
                    {t('pub.won')} {winner.player_name}
                  </span>
                )}
              </span>
              <span aria-hidden className="text-[var(--text-faint)]">›</span>
            </Link>
          )}
        </div>

        <section className="rounded-3xl border border-[var(--line)] bg-[var(--surface)] p-5 lg:col-span-2">
          <h2 className="text-xs uppercase tracking-[0.22em] text-[var(--text-faint)]">
            {t('pub.standings')}
          </h2>

          {top.length === 0 ? (
            <p className="mt-2 text-sm text-[var(--text-muted)]">{t('pub.noResult')}</p>
          ) : (
            <>
              <ol className="mt-3 divide-y divide-[var(--line)]">
                {top.map((s, i) => (
                  <li key={s.player_name} className="flex items-baseline gap-3 py-2.5">
                    <span
                      className={`tnum w-6 shrink-0 text-sm ${
                        i < 3 ? 'font-semibold text-[var(--brand)]' : 'text-[var(--text-faint)]'
                      }`}
                    >
                      {i + 1}
                    </span>
                    <span className="min-w-0 flex-1 truncate">{s.player_name}</span>
                    <span className="tnum shrink-0 font-semibold">
                      {Math.round(Number(s.points))}
                    </span>
                  </li>
                ))}
              </ol>
              <Link
                href={`/c/${club.slug}/klassement`}
                className="mt-4 inline-block text-sm text-[var(--text-muted)] underline-offset-4 hover:underline"
              >
                {t('pub.wholeStandings')} →
              </Link>
            </>
          )}
        </section>
      </div>
    </PublicShell>
  )
}

/** Een kaart die eerlijk zegt dat er nog niets is, en waar het komt te staan. */
function Soon({ title, body, href }: { title: string; body: string; href: string }) {
  return (
    <Link
      href={href}
      className="group flex min-h-[8rem] flex-col justify-between rounded-3xl border border-[var(--line)] bg-[var(--surface)] p-5 transition hover:bg-[var(--surface-hover)] sm:p-6"
    >
      <span>
        <span className="block text-xs uppercase tracking-[0.22em] text-[var(--text-faint)]">
          {title}
        </span>
        <span className="mt-2 block text-sm leading-relaxed text-[var(--text-muted)]">{body}</span>
      </span>
      <span aria-hidden className="mt-4 block text-[var(--text-faint)] transition group-hover:text-[var(--text)]">
        →
      </span>
    </Link>
  )
}

function Stat({ label, value, sub }: { label: string; value: string; sub?: string }) {
  return (
    <span className="block rounded-2xl bg-[color-mix(in_oklab,var(--bg)_55%,transparent)] px-3 py-3">
      <span className="block text-[0.6rem] uppercase tracking-[0.16em] text-[var(--text-faint)]">
        {label}
      </span>
      <span className="tnum mt-1 block text-xl font-semibold leading-tight sm:text-2xl">{value}</span>
      {sub && <span className="block text-[0.7rem] text-[var(--text-faint)]">{sub}</span>}
    </span>
  )
}
