import Link from 'next/link'
import Image from 'next/image'
import { DaysToGo } from '@/components/public/DaysToGo'
import { PublicShell } from '@/components/public/PublicShell'
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
 * Loopt er een avond, dan is dat het enige wat telt en krijgt die het hele
 * bovenstuk, mét de cijfers erbij — level, spelers over, prijzenpot. Een kaart
 * die alleen een naam toont is een link vermomd als kaart; hier hoort iets te
 * staan waar je iets aan hebt zonder door te klikken.
 *
 * Loopt er niets, dan wint de vraag wanneer de volgende is. En bestaat de club
 * nog niet echt — geen avonden gespeeld, openingsdag in de toekomst — dan zegt
 * de pagina dát, in plaats van drie lege kaders met nullen erin. Een pas
 * gebouwde clubsite die "0 tornooien, geen klassement" toont ziet er kapot
 * uit terwijl er niets kapot is.
 *
 * Op een breed scherm staan de avond en het klassement naast elkaar. De vorige
 * versie hield ook op een monitor één smalle kolom aan, en dan lees je een
 * telefoonschermpje in een zwart veld.
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

  // Alleen ophalen wat we tonen. Bij een lege club is dit nul netwerkverkeer.
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

  // Nog niets gespeeld en de deuren gaan pas open: dan is de openingsdag het
  // nieuws, niet het gebrek aan cijfers.
  const opensOn = club.opens_on ? new Date(`${club.opens_on}T00:00:00`) : null
  const preOpening = opensOn !== null && all.length === 0 && standings.length === 0

  return (
    <PublicShell club={club} locale={locale} active="home" wide>
      <Hero club={club} />

      <div className="mt-6 grid gap-4 lg:grid-cols-5">
        {/* -------------------------------------------------- linkerkolom */}
        <div className="space-y-4 lg:col-span-3">
          {preOpening ? (
            <section className="rounded-2xl border border-[var(--brand)] bg-[color-mix(in_oklab,var(--brand)_10%,transparent)] p-6">
              <p className="text-xs uppercase tracking-[0.2em] text-[var(--brand)]">
                {t('pub.opening')}
              </p>
              <p className="mt-2 text-3xl font-semibold leading-tight sm:text-4xl">
                {fmtDay.format(opensOn)}
              </p>
              <DaysToGo date={club.opens_on as string} />
              <p className="mt-4 max-w-prose text-sm leading-relaxed text-[var(--text-muted)]">
                {t('pub.openingBody')}
              </p>
            </section>
          ) : live && liveClock ? (
            <Link
              href={`/c/${club.slug}/live/${live.id}`}
              className="block rounded-2xl border border-[var(--brand)] bg-[color-mix(in_oklab,var(--brand)_12%,transparent)] p-5 transition hover:brightness-110 sm:p-6"
            >
              <span className="flex items-center gap-2 text-xs uppercase tracking-[0.2em] text-[var(--brand)]">
                <span className="inline-block size-2 animate-pulse rounded-full bg-[var(--brand)]" />
                {t('pub.nowPlaying')}
              </span>
              <span className="mt-1.5 block text-2xl font-semibold sm:text-3xl">{live.name}</span>

              <span className="mt-4 grid grid-cols-3 gap-3">
                <Stat label={t('clock.playersLeft')} value={`${liveClock.players_left}`}
                      sub={`${t('common.of')} ${liveClock.entries}`} />
                <Stat label={t('clock.prizePool')}
                      value={formatMoney(liveClock.prize_pool_cents, club.currency)} />
                <Stat label={t('pub.rebuys')} value={`${liveClock.rebuys}`} />
              </span>

              <span className="mt-4 block text-sm text-[var(--text-muted)]">
                {t('pub.followLive')} →
              </span>
            </Link>
          ) : next ? (
            <section className="rounded-2xl border border-[var(--line)] bg-[var(--surface)] p-5 sm:p-6">
              <p className="text-xs uppercase tracking-[0.2em] text-[var(--text-faint)]">
                {t('pub.nextUp')}
              </p>
              <p className="mt-1.5 text-2xl font-semibold sm:text-3xl">{next.name}</p>
              <p className="mt-1 text-[var(--text-muted)]">
                {fmtLong.format(new Date(next.scheduled_at))}
              </p>
              <p className="tnum mt-4 text-sm text-[var(--text-faint)]">
                {t('pub.entry')} {formatMoney(next.buyin_cents + next.fee_cents, club.currency)}
              </p>
            </section>
          ) : (
            <section className="rounded-2xl border border-[var(--line)] bg-[var(--surface)] p-6">
              <p className="text-[var(--text-muted)]">{t('pub.nothingPlanned')}</p>
            </section>
          )}

          {last && (
            <Link
              href={`/c/${club.slug}/live/${last.id}`}
              className="flex items-center gap-3 rounded-2xl border border-[var(--line)] bg-[var(--surface)] px-4 py-4 transition hover:bg-[var(--surface-hover)]"
            >
              <span className="min-w-0 flex-1">
                <span className="block text-xs uppercase tracking-[0.2em] text-[var(--text-faint)]">
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

        {/* ------------------------------------------------- rechterkolom */}
        <div className="lg:col-span-2">
          <section className="rounded-2xl border border-[var(--line)] bg-[var(--surface)] p-4">
            <h2 className="text-xs uppercase tracking-[0.2em] text-[var(--text-faint)]">
              {t('pub.standings')}
            </h2>

            {top.length === 0 ? (
              <p className="mt-2 text-sm text-[var(--text-muted)]">
                {preOpening ? t('pub.standingsSoon') : t('pub.noResult')}
              </p>
            ) : (
              <>
                <ol className="mt-2 divide-y divide-[var(--line)]">
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
                  className="mt-3 inline-block text-sm text-[var(--text-muted)] underline-offset-4 hover:underline"
                >
                  {t('pub.wholeStandings')} →
                </Link>
              </>
            )}
          </section>
        </div>
      </div>
    </PublicShell>
  )
}

/**
 * De kop van de pagina.
 *
 * Het beeldmerk van de club groot en zacht op de achtergrond, precies zoals op
 * de zaalklok. Dat is geen versiering: het is het enige wat deze pagina
 * onmiskenbaar van déze club maakt in plaats van van het platform eronder.
 */
function Hero({ club }: { club: Club }) {
  const mark = club.mark_url ?? club.logo_url

  return (
    <section className="relative overflow-hidden rounded-2xl border border-[var(--line)] bg-[var(--surface)] px-5 py-7 sm:px-8 sm:py-9">
      {mark && (
        <Image
          src={mark}
          alt=""
          aria-hidden
          width={420}
          height={420}
          unoptimized
          className="pointer-events-none absolute -right-10 -top-10 hidden size-64 object-contain opacity-[0.07] sm:block"
        />
      )}

      <h1 className="relative text-3xl font-semibold leading-tight sm:text-4xl">{club.name}</h1>
      {club.city && (
        <p className="relative mt-1 text-sm uppercase tracking-[0.18em] text-[var(--text-faint)]">
          {club.city}
        </p>
      )}
      {club.intro && (
        <p className="relative mt-4 max-w-prose text-[0.975rem] leading-relaxed text-[var(--text-muted)]">
          {club.intro}
        </p>
      )}
    </section>
  )
}

function Stat({ label, value, sub }: { label: string; value: string; sub?: string }) {
  return (
    <span className="block rounded-xl bg-[color-mix(in_oklab,var(--bg)_55%,transparent)] px-3 py-2.5">
      <span className="block text-[0.6rem] uppercase tracking-[0.16em] text-[var(--text-faint)]">
        {label}
      </span>
      <span className="tnum mt-0.5 block text-xl font-semibold leading-tight">{value}</span>
      {sub && <span className="block text-[0.7rem] text-[var(--text-faint)]">{sub}</span>}
    </span>
  )
}
