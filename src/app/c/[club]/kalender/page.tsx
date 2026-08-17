import Link from 'next/link'
import { notFound } from 'next/navigation'
import { PublicShell } from '@/components/public/PublicShell'
import { getClub } from '@/lib/club'
import { isLocale, translator } from '@/lib/i18n/dictionaries'
import { getPublicTournaments, type PublicTournament } from '@/lib/publicClub'
import { formatMoney } from '@/lib/types'

/**
 * De agenda van de club.
 *
 * Komende avonden bovenaan, want dat is waarvoor je hier komt. Daaronder wat
 * er gespeeld is, zodat iemand die een avond miste alsnog de uitslag vindt
 * zonder ernaar te moeten vragen.
 */

export async function generateMetadata({ params }: PageProps<'/c/[club]/kalender'>) {
  const { club: slug } = await params
  const club = await getClub(slug)
  const t = translator(isLocale(club?.locale ?? 'nl') ? (club?.locale as 'nl') : 'nl')
  return { title: `${t('pub.calendar')} · ${club?.name ?? ''}` }
}

export default async function Page_({ params }: PageProps<'/c/[club]/kalender'>) {
  const { club: slug } = await params
  const club = await getClub(slug)
  if (!club) notFound()

  const t = translator(isLocale(club.locale) ? club.locale : 'nl')
  const all = await getPublicTournaments(club.id)

  const live = all.filter((x) => x.status === 'running' || x.status === 'paused')
  const upcoming = all.filter((x) => x.status === 'scheduled').reverse()
  const past = all.filter((x) => x.status === 'finished')

  const fmt = new Intl.DateTimeFormat(`${club.locale}-BE`, {
    weekday: 'short', day: 'numeric', month: 'short',
    hour: '2-digit', minute: '2-digit', timeZone: club.timezone,
  })

  const row = (x: PublicTournament, tone: 'live' | 'next' | 'past') => (
    <li key={x.id}>
      <Link
        href={`/c/${club.slug}/live/${x.id}`}
        className="flex items-center gap-3 px-4 py-3.5 transition hover:bg-[var(--surface-hover)]"
      >
        <span className="min-w-0 flex-1">
          <span className="flex items-center gap-2">
            {tone === 'live' && (
              <span className="inline-block size-2 shrink-0 animate-pulse rounded-full bg-[var(--ok)]" />
            )}
            <span className="truncate font-medium">{x.name}</span>
          </span>
          <span className="mt-0.5 block text-xs text-[var(--text-faint)]">
            {fmt.format(new Date(x.scheduled_at))}
          </span>
        </span>
        <span className="tnum shrink-0 text-sm text-[var(--text-muted)]">
          {formatMoney(x.buyin_cents + x.fee_cents, club.currency)}
        </span>
        <span aria-hidden className="shrink-0 text-[var(--text-faint)]">›</span>
      </Link>
    </li>
  )

  const block = (title: string, items: PublicTournament[], tone: 'live' | 'next' | 'past') =>
    items.length === 0 ? null : (
      <section className="mt-5 first:mt-0">
        <h2 className="mb-2 text-xs uppercase tracking-[0.2em] text-[var(--text-faint)]">{title}</h2>
        <ul className="divide-y divide-[var(--line)] overflow-hidden rounded-2xl border border-[var(--line)] bg-[var(--surface)]">
          {items.map((x) => row(x, tone))}
        </ul>
      </section>
    )

  return (
    <PublicShell club={club} active="calendar" t={t}>
      {all.length === 0 && (
        <p className="text-[var(--text-muted)]">{t('pub.noTournaments')}</p>
      )}
      {block(t('pub.nowPlaying'), live, 'live')}
      {block(t('pub.upcoming'), upcoming, 'next')}
      {block(t('pub.played'), past, 'past')}
    </PublicShell>
  )
}
