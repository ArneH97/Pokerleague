import Link from 'next/link'
import { notFound } from 'next/navigation'
import { PublicShell } from '@/components/public/PublicShell'
import { getClub } from '@/lib/club'
import { isLocale, translator } from '@/lib/i18n/dictionaries'
import { visitorLocale } from '@/lib/i18n/server'
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

  // De taal van de bezoeker wint van die van de club; wie niets koos krijgt
  // de taal waarin de club zijn zaal bedient.
  const locale = (await visitorLocale()) ?? (isLocale(club.locale) ? club.locale : 'nl')
  const t = translator(locale)
  const all = await getPublicTournaments(club.id)

  const live = all.filter((x) => x.status === 'running' || x.status === 'paused')
  const upcoming = all.filter((x) => x.status === 'scheduled').reverse()
  const past = all.filter((x) => x.status === 'finished')

  const fmt = new Intl.DateTimeFormat(`${club.locale}-BE`, {
    weekday: 'short', day: 'numeric', month: 'short',
    hour: '2-digit', minute: '2-digit', timeZone: club.timezone,
  })

  // Kaarten en geen regels. Een lijst van volle-breedte-regels op een monitor
  // laat de naam links en de prijs rechts staan met een halve meter niets
  // ertussen; in een raster staan ze naast elkaar en vult de pagina zich.
  const card = (x: PublicTournament, tone: 'live' | 'next' | 'past') => (
    <li key={x.id}>
      <Link
        href={`/c/${club.slug}/live/${x.id}`}
        className={`group flex h-full flex-col justify-between rounded-2xl border p-4 transition sm:p-5 ${
          tone === 'live'
            ? 'border-[var(--brand)] bg-[color-mix(in_oklab,var(--brand)_10%,transparent)] hover:brightness-110'
            : 'border-[var(--line)] bg-[var(--surface)] hover:bg-[var(--surface-hover)]'
        }`}
      >
        <span>
          <span className="flex items-center gap-2">
            {tone === 'live' && (
              <span className="inline-block size-2 shrink-0 animate-pulse rounded-full bg-[var(--brand)]" />
            )}
            <span className={`truncate font-medium ${tone === 'past' ? 'text-[var(--text-muted)]' : ''}`}>
              {x.name}
            </span>
          </span>
          <span className="mt-1 block text-xs text-[var(--text-faint)]">
            {fmt.format(new Date(x.scheduled_at))}
          </span>
        </span>
        <span className="mt-4 flex items-baseline justify-between">
          <span className="tnum text-sm text-[var(--text-muted)]">
            {formatMoney(x.buyin_cents + x.fee_cents, club.currency)}
          </span>
          <span aria-hidden className="text-[var(--text-faint)] transition group-hover:text-[var(--text)]">
            →
          </span>
        </span>
      </Link>
    </li>
  )

  const block = (title: string, items: PublicTournament[], tone: 'live' | 'next' | 'past') =>
    items.length === 0 ? null : (
      <section className="mt-6 first:mt-0">
        <h2 className="mb-3 text-xs uppercase tracking-[0.22em] text-[var(--text-faint)]">{title}</h2>
        <ul className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {items.map((x) => card(x, tone))}
        </ul>
      </section>
    )

  return (
    <PublicShell club={club} locale={locale} active="calendar">
      {all.length === 0 && (
        <p className="rounded-3xl border border-[var(--line)] bg-[var(--surface)] p-6 text-[var(--text-muted)]">
          {club.opens_on ? t('pub.calendarSoon') : t('pub.noTournaments')}
        </p>
      )}
      {block(t('pub.nowPlaying'), live, 'live')}
      {block(t('pub.upcoming'), upcoming, 'next')}
      {block(t('pub.played'), past, 'past')}
    </PublicShell>
  )
}
