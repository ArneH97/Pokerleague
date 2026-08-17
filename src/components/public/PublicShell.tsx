import Link from 'next/link'
import Image from 'next/image'
import type { T } from '@/lib/i18n/dictionaries'

/**
 * Het omhulsel van de publieke clubpagina's.
 *
 * Mobiel eerst, en dat is hier geen slogan: dit wordt gelezen door iemand die
 * aan een pokertafel zit met één hand vrij. Vandaar een smalle kolom, grote
 * raakvlakken, en een navigatie van drie woorden die onderaan het duimbereik
 * blijft op een telefoon en bovenaan meeschuift op een groter scherm.
 *
 * Geen PokerLeague-merk. Dit is de club zijn pagina; wie hier komt heeft het
 * adres van de club ingetypt.
 */
export function PublicShell({
  club, active, t, children,
}: {
  club: { slug: string; name: string; city: string | null; logo_url: string | null }
  active: 'home' | 'calendar' | 'standings'
  t: T
  children: React.ReactNode
}) {
  const items = [
    { key: 'home' as const, href: `/c/${club.slug}`, label: t('pub.now') },
    { key: 'calendar' as const, href: `/c/${club.slug}/kalender`, label: t('pub.calendar') },
    { key: 'standings' as const, href: `/c/${club.slug}/klassement`, label: t('pub.standings') },
  ]

  return (
    <div className="min-h-dvh pb-[env(safe-area-inset-bottom)]">
      <header className="border-b border-[var(--line)] px-4 pb-3 pt-5 sm:px-6">
        <Link href={`/c/${club.slug}`} className="flex items-center gap-3">
          {club.logo_url && (
            <Image
              src={club.logo_url}
              alt=""
              width={40}
              height={40}
              unoptimized
              className="size-10 shrink-0 rounded-lg object-contain"
            />
          )}
          <span className="min-w-0">
            <span className="block truncate text-lg font-semibold leading-tight">{club.name}</span>
            {club.city && (
              <span className="block text-xs text-[var(--text-faint)]">{club.city}</span>
            )}
          </span>
        </Link>

        {/* Op een telefoon staat dit gewoon onder de naam; vanaf tablet komt
            het op dezelfde regel. Drie woorden, dus dat past altijd. */}
        <nav className="mt-3 flex gap-1 overflow-x-auto">
          {items.map((i) => (
            <Link
              key={i.key}
              href={i.href}
              className={`shrink-0 rounded-full px-4 py-2 text-sm transition ${
                i.key === active
                  ? 'bg-[var(--brand)] font-medium text-[var(--on-brand)]'
                  : 'text-[var(--text-muted)] hover:bg-[var(--surface-hover)] hover:text-[var(--text)]'
              }`}
            >
              {i.label}
            </Link>
          ))}
        </nav>
      </header>

      <main className="mx-auto w-full max-w-2xl px-4 py-5 sm:px-6">{children}</main>

      <footer className="mx-auto w-full max-w-2xl px-4 pb-8 pt-2 text-center sm:px-6">
        <Link
          href={`/c/${club.slug}/login`}
          className="text-xs text-[var(--text-faint)] underline-offset-4 hover:underline"
        >
          {t('pub.staffLogin')}
        </Link>
      </footer>
    </div>
  )
}
