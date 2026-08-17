import Link from 'next/link'
import { PublicShell } from '@/components/public/PublicShell'
import type { Club } from '@/lib/club'
import { translator, type Locale } from '@/lib/i18n/dictionaries'
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
  club, locale, mode,
}: {
  club: Club
  locale: Locale
  mode: 'all' | 'year' | 'month'
}) {
  const t = translator(locale)
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
    <PublicShell club={club} locale={locale} active="standings">
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
        <p className="rounded-3xl border border-[var(--line)] bg-[var(--surface)] p-6 text-[var(--text-muted)]">
          {club.opens_on ? t('pub.standingsSoon') : t('pub.noResult')}
        </p>
      ) : (
        /* Op een telefoon één regel per speler met het bijkomstige klein
           eronder; vanaf tablet een echte tabel, want dan is er plaats voor
           kolommen en leest een rij met vijf getallen prettiger dan vijf
           regels tekst. */
        <div className="overflow-hidden rounded-3xl border border-[var(--line)] bg-[var(--surface)]">
          <table className="w-full text-left">
            <thead className="hidden sm:table-header-group">
              <tr className="border-b border-[var(--line)] text-[0.65rem] uppercase tracking-[0.2em] text-[var(--text-faint)]">
                <th className="w-14 px-5 py-3 font-medium">#</th>
                <th className="px-2 py-3 font-medium">{t('pub.player')}</th>
                <th className="w-24 px-2 py-3 text-right font-medium">{t('pub.games')}</th>
                <th className="w-24 px-2 py-3 text-right font-medium">{t('pub.best')}</th>
                <th className="w-28 px-5 py-3 text-right font-medium">{t('pub.pts')}</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r, i) => (
                <tr key={`${r.player_name}-${i}`} className="border-b border-[var(--line)] last:border-0">
                  <td className="px-5 py-3 align-baseline">
                    <span
                      className={`tnum text-sm ${
                        i < 3 ? 'font-semibold text-[var(--brand)]' : 'text-[var(--text-faint)]'
                      }`}
                    >
                      {i + 1}
                    </span>
                  </td>
                  <td className="px-2 py-3 align-baseline">
                    <span className="block truncate font-medium">{r.player_name}</span>
                    <span className="tnum block text-xs text-[var(--text-faint)] sm:hidden">
                      {r.tournaments} {t('pub.games').toLowerCase()} · {t('pub.best').toLowerCase()} {r.best_position}
                    </span>
                  </td>
                  <td className="tnum hidden px-2 py-3 text-right align-baseline text-sm text-[var(--text-muted)] sm:table-cell">
                    {r.tournaments}
                  </td>
                  <td className="tnum hidden px-2 py-3 text-right align-baseline text-sm text-[var(--text-muted)] sm:table-cell">
                    {r.best_position}
                  </td>
                  <td className="tnum px-5 py-3 text-right align-baseline text-lg font-semibold">
                    {Math.round(Number(r.points))}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

    </PublicShell>
  )
}
