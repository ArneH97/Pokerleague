import Link from 'next/link'
import { LanguageSwitch } from '@/components/LanguageSwitch'
import type { Locale, T } from '@/lib/i18n/dictionaries'

/**
 * De balk boven de spelerspagina's.
 *
 * Stond eerst als losse regels in elke pagina, met per pagina net iets andere
 * knoppen. Nu op één plek, want dit is de enige navigatie die een speler
 * heeft: zijn overzicht, zijn gegevens, en eruit.
 */
export function PlayerNav({
  locale, t, active,
}: { locale: Locale; t: T; active: 'home' | 'settings' }) {
  return (
    <header className="border-b border-[var(--line)]">
      <div className="mx-auto flex max-w-3xl items-center gap-1 px-4 py-3 sm:gap-3 sm:px-5 sm:py-4">
        <Link href="/ik" className="text-sm font-semibold uppercase tracking-[0.2em]">
          Poker<span className="text-[var(--brand)]">League</span>
        </Link>
        <span className="flex-1" />

        <Link
          href="/ik"
          aria-current={active === 'home' ? 'page' : undefined}
          className={`rounded-full px-3 py-1.5 text-sm transition ${
            active === 'home'
              ? 'bg-[var(--surface-2)] font-medium'
              : 'text-[var(--text-muted)] hover:bg-[var(--surface-hover)] hover:text-[var(--text)]'
          }`}
        >
          {t('me.navHome')}
        </Link>
        <Link
          href="/ik/gegevens"
          aria-current={active === 'settings' ? 'page' : undefined}
          className={`rounded-full px-3 py-1.5 text-sm transition ${
            active === 'settings'
              ? 'bg-[var(--surface-2)] font-medium'
              : 'text-[var(--text-muted)] hover:bg-[var(--surface-hover)] hover:text-[var(--text)]'
          }`}
        >
          {t('me.navSettings')}
        </Link>

        <span className="hidden sm:block">
          <LanguageSwitch current={locale} label={t('common.language')} />
        </span>
        <form action="/auth/signout" method="post">
          <button className="rounded-full px-3 py-1.5 text-sm text-[var(--text-muted)] transition hover:bg-[var(--surface-hover)] hover:text-[var(--text)]">
            {t('common.signOut')}
          </button>
        </form>
      </div>
    </header>
  )
}
