import Link from 'next/link'
import { notFound, redirect } from 'next/navigation'
import { LiveBoard } from '@/components/public/LiveBoard'
import { PublicShell } from '@/components/public/PublicShell'
import { getClub } from '@/lib/club'
import { createClient } from '@/lib/supabase/server'
import { translator } from '@/lib/i18n/dictionaries'
import { clubLocale } from '@/lib/i18n/server'
import {
  getPrizeLadder, getPublicClock, getPublicLevels, getPublicResult, getPublicSeats,
} from '@/lib/publicClub'

/**
 * Een avond volgen zonder account.
 *
 * Draait het tornooi nog, dan komt hier het live-bord. Is het afgelopen, dan
 * de uitslag — hetzelfde adres, zodat een link die tijdens de avond rondging
 * daarna nog altijd naar iets zinnigs wijst in plaats van naar een lege klok.
 */

export async function generateMetadata({ params }: PageProps<'/c/[club]/live/[id]'>) {
  const { club: slug, id } = await params
  const club = await getClub(slug)
  const clock = await getPublicClock(id)
  return { title: clock ? `${clock.name} · ${club?.name ?? ''}` : (club?.name ?? 'Club') }
}

export default async function Page_({ params }: PageProps<'/c/[club]/live/[id]'>) {
  const { club: slug, id } = await params
  const club = await getClub(slug)
  if (!club) notFound()

  // Ook een lopende avond is een deelnemerslijst. Zie migratie 0034.
  const gate = await createClient()
  const { data: gateClaims } = await gate.auth.getClaims()
  if (!gateClaims?.claims) redirect(`/login?next=/c/${slug}/live/${id}`)

  const locale = await clubLocale(club.locale)
  const t = translator(locale)
  const clock = await getPublicClock(id)

  // Geen rij betekent: bestaat niet, of staat niet publiek. Dat verschil
  // hoort een buitenstaander niet te zien.
  if (!clock) notFound()

  const done = clock.status === 'finished' || clock.status === 'cancelled'
  const fmt = new Intl.DateTimeFormat(`${locale}-BE`, {
    weekday: 'long', day: 'numeric', month: 'long',
    hour: '2-digit', minute: '2-digit', timeZone: club.timezone,
  })

  if (done) {
    const rows = await getPublicResult(id)
    return (
      <PublicShell club={club} locale={locale} active="calendar">
        <h1 className="text-2xl font-semibold">{clock.name}</h1>
        <p className="mt-1 text-sm text-[var(--text-faint)]">
          {fmt.format(new Date(clock.scheduled_at))} · {clock.entries} {t('pub.entriesWord')}
        </p>

        {rows.length === 0 ? (
          <p className="mt-6 text-[var(--text-muted)]">{t('pub.noResult')}</p>
        ) : (
          <ol className="mt-5 divide-y divide-[var(--line)] overflow-hidden rounded-2xl border border-[var(--line)] bg-[var(--surface)]">
            {rows.map((r) => (
              <li key={r.place} className="flex items-baseline gap-3 px-4 py-3">
                <span className="tnum w-7 shrink-0 text-sm text-[var(--text-faint)]">{r.place}</span>
                <span className="min-w-0 flex-1 truncate font-medium">{r.player_name}</span>
                <span className="tnum shrink-0 text-sm text-[var(--text-muted)]">
                  {Math.round(Number(r.points))} {t('pub.pts')}
                </span>
              </li>
            ))}
          </ol>
        )}

        <Link
          href={`/c/${club.slug}/klassement`}
          className="mt-5 inline-block rounded-xl border border-[var(--line-strong)] px-4 py-2.5 text-sm transition hover:bg-[var(--surface-hover)]"
        >
          {t('pub.standings')} →
        </Link>
      </PublicShell>
    )
  }

  const [levels, seats, prizes] = await Promise.all([
    getPublicLevels(id), getPublicSeats(id), getPrizeLadder(id),
  ])

  return (
    <PublicShell club={club} locale={locale} active="home">
      <h1 className="text-xl font-semibold">{clock.name}</h1>
      <p className="mb-4 mt-0.5 text-sm text-[var(--text-faint)]">
        {fmt.format(new Date(clock.scheduled_at))}
      </p>
      <LiveBoard
        tournamentId={id}
        initialClock={clock}
        initialLevels={levels}
        initialSeats={seats}
        prizes={prizes}
      />
    </PublicShell>
  )
}
