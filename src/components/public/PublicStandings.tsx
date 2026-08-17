import Link from 'next/link'
import { PublicShell } from '@/components/public/PublicShell'
import type { Club } from '@/lib/club'
import type { T } from '@/lib/i18n/dictionaries'
import { getPublicStandings } from '@/lib/publicClub'

/**
 * Het klassement voor de zaal.
 *
 * Bewust zonder prijzengeld. Een naam naast een klassering is iets anders dan
 * een naam naast een bedrag, en wat iemand won is een zaak tussen hem en de
 * club. Punten, aantal avonden en de beste plaats — dat is wat een klassement
 * is.
 *
 * Alleen afgesloten publieke avonden tellen mee, zodat de stand hier nooit
 * kan afwijken van wat er publiek te zien was.
 */
export async function PublicStandings({
  club, t, mode,
}: {
  club: Club
  t: T
  mode: 'all' | 'year' | 'month'
}) {
  const now = new Date()
  const year = now.getFullYear()
  const pad = (n: number) => String(n).padStart(2, '0')
  const month = now.getMonth() + 1
  const lastDay = new Date(year, month, 0).getDate()

  const [from, to] =
    mode === 'year' ? [`${year}-01-01`, `${year}-12-31`]
      : mode === 'month' ? [`${year}-${pad(month)}-01`, `${year}-${pad(month)}-${pad(lastDay)}`]
        : [undefined, undefined]

  const rows = await getPublicStandings(club.slug, from, to)
  const base = `/c/${club.slug}/klassement`

  const tabs = [
    { key: 'all' as const, href: base, label: t('pub.allTime') },
    { key: 'year' as const, href: `${base}?p=year`, label: t('pub.thisYear') },
    { key: 'month' as const, href: `${base}?p=month`, label: t('pub.thisMonth') },
  ]

  return (
    <PublicShell club={club} active="standings" t={t}>
      <div className="mb-4 flex gap-1 overflow-x-auto">
        {tabs.map((x) => (
          <Link
            key={x.key}
            href={x.href}
            className={`shrink-0 rounded-full border px-3.5 py-1.5 text-sm transition ${
              x.key === mode
                ? 'border-[var(--brand)] bg-[color-mix(in_oklab,var(--brand)_14%,transparent)] text-[var(--text)]'
                : 'border-[var(--line)] text-[var(--text-muted)] hover:bg-[var(--surface-hover)]'
            }`}
          >
            {x.label}
          </Link>
        ))}
      </div>

      {rows.length === 0 ? (
        <p className="text-[var(--text-muted)]">{t('pub.noResult')}</p>
      ) : (
        <ol className="divide-y divide-[var(--line)] overflow-hidden rounded-2xl border border-[var(--line)] bg-[var(--surface)]">
          {rows.map((r, i) => (
            <li key={r.player_name} className="flex items-center gap-3 px-4 py-3">
              <span
                className={`tnum w-7 shrink-0 text-sm ${
                  i < 3 ? 'font-semibold text-[var(--brand)]' : 'text-[var(--text-faint)]'
                }`}
              >
                {i + 1}
              </span>
              <span className="min-w-0 flex-1">
                <span className="block truncate font-medium">{r.player_name}</span>
                {/* Op een telefoon past er geen tabel met vijf kolommen, dus
                    de bijzaken staan klein onder de naam in plaats van
                    afgekapt ernaast. */}
                <span className="tnum block text-xs text-[var(--text-faint)]">
                  {r.tournaments} {t('pub.games').toLowerCase()} · {t('pub.best').toLowerCase()} {r.best_position}
                </span>
              </span>
              <span className="tnum shrink-0 text-lg font-semibold">
                {Math.round(Number(r.points))}
              </span>
            </li>
          ))}
        </ol>
      )}
    </PublicShell>
  )
}
