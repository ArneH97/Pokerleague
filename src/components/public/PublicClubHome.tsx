import Link from 'next/link'
import { PublicShell } from '@/components/public/PublicShell'
import type { Club } from '@/lib/club'
import type { T } from '@/lib/i18n/dictionaries'
import { getPublicStandings, getPublicTournaments } from '@/lib/publicClub'
import { formatMoney } from '@/lib/types'

/**
 * De voorpagina van een club voor wie niet inlogt.
 *
 * Eén vraag staat hier voorop en dat is niet "wie zijn wij" maar "wat is er
 * nu". Loopt er een avond, dan is dat het enige wat telt en krijgt die een
 * volle knop. Loopt er niets, dan wil je weten wanneer de volgende is. De
 * korte kop van het klassement staat eronder omdat dat de reden is dat mensen
 * terugkomen tussen twee avonden door.
 */
export async function PublicClubHome({ club, t }: { club: Club; t: T }) {
  const [all, standings] = await Promise.all([
    getPublicTournaments(club.id, 30),
    getPublicStandings(club.slug),
  ])

  const live = all.find((x) => x.status === 'running' || x.status === 'paused')
  const next = all.filter((x) => x.status === 'scheduled').at(-1)
  const last = all.find((x) => x.status === 'finished')
  const top = standings.slice(0, 5)

  const fmtLong = new Intl.DateTimeFormat(`${club.locale}-BE`, {
    weekday: 'long', day: 'numeric', month: 'long',
    hour: '2-digit', minute: '2-digit', timeZone: club.timezone,
  })

  return (
    <PublicShell club={club} active="home" t={t}>
      {live ? (
        <Link
          href={`/c/${club.slug}/live/${live.id}`}
          className="block rounded-2xl border border-[var(--brand)] bg-[color-mix(in_oklab,var(--brand)_12%,transparent)] p-5 transition hover:brightness-110"
        >
          <span className="flex items-center gap-2 text-xs uppercase tracking-[0.2em] text-[var(--brand)]">
            <span className="inline-block size-2 animate-pulse rounded-full bg-[var(--brand)]" />
            {t('pub.nowPlaying')}
          </span>
          <span className="mt-1.5 block text-2xl font-semibold">{live.name}</span>
          <span className="mt-1 block text-sm text-[var(--text-muted)]">{t('pub.followLive')} →</span>
        </Link>
      ) : next ? (
        <div className="rounded-2xl border border-[var(--line)] bg-[var(--surface)] p-5">
          <p className="text-xs uppercase tracking-[0.2em] text-[var(--text-faint)]">
            {t('pub.nextUp')}
          </p>
          <p className="mt-1.5 text-2xl font-semibold">{next.name}</p>
          <p className="mt-1 text-sm text-[var(--text-muted)]">
            {fmtLong.format(new Date(next.scheduled_at))}
          </p>
          <p className="mt-3 tnum text-sm text-[var(--text-faint)]">
            {t('pub.entry')} {formatMoney(next.buyin_cents + next.fee_cents, club.currency)}
          </p>
        </div>
      ) : (
        <div className="rounded-2xl border border-[var(--line)] bg-[var(--surface)] p-5">
          <p className="text-[var(--text-muted)]">{t('pub.nothingPlanned')}</p>
        </div>
      )}

      {last && (
        <Link
          href={`/c/${club.slug}/live/${last.id}`}
          className="mt-3 flex items-center gap-3 rounded-2xl border border-[var(--line)] bg-[var(--surface)] px-4 py-3.5 transition hover:bg-[var(--surface-hover)]"
        >
          <span className="min-w-0 flex-1">
            <span className="block text-xs uppercase tracking-[0.2em] text-[var(--text-faint)]">
              {t('pub.lastResult')}
            </span>
            <span className="mt-0.5 block truncate font-medium">{last.name}</span>
          </span>
          <span aria-hidden className="text-[var(--text-faint)]">›</span>
        </Link>
      )}

      {top.length > 0 && (
        <section className="mt-6">
          <h2 className="mb-2 text-xs uppercase tracking-[0.2em] text-[var(--text-faint)]">
            {t('pub.standings')}
          </h2>
          <ol className="divide-y divide-[var(--line)] overflow-hidden rounded-2xl border border-[var(--line)] bg-[var(--surface)]">
            {top.map((s, i) => (
              <li key={s.player_name} className="flex items-baseline gap-3 px-4 py-2.5">
                <span className="tnum w-6 shrink-0 text-sm text-[var(--text-faint)]">{i + 1}</span>
                <span className="min-w-0 flex-1 truncate">{s.player_name}</span>
                <span className="tnum shrink-0 font-semibold">
                  {Math.round(Number(s.points))}
                </span>
              </li>
            ))}
          </ol>
          <Link
            href={`/c/${club.slug}/klassement`}
            className="mt-2 inline-block text-sm text-[var(--text-muted)] underline-offset-4 hover:underline"
          >
            {t('pub.wholeStandings')} →
          </Link>
        </section>
      )}
    </PublicShell>
  )
}
