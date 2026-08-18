import Link from 'next/link'
import { LanguageSwitch } from '@/components/LanguageSwitch'
import type { Locale, T } from '@/lib/i18n/dictionaries'

/**
 * De navigatie van de spelersapp.
 *
 * Stond eerst als een rij tekstlinks bovenaan, en dat liep op een telefoon
 * gewoon van het scherm af: "Mijn gegevens" brak over twee regels en
 * "Afmelden" viel er half buiten. Een balk die niet past is geen balk.
 *
 * Nu twee dingen die elk doen waar ze goed in zijn. Bovenaan een dunne balk
 * met het merk en het uitgangetje — die mag klein zijn, want je gebruikt hem
 * zelden. Onderaan, alleen op een telefoon, een tabbalk met duimbereik: dit is
 * een app die je met één hand in een zaal opent, en dan hoort de navigatie
 * onder je duim te zitten en niet bovenaan waar je hem niet bij kan.
 *
 * De tabbalk is `fixed` en heeft `pb-safe`, anders zit hij onder de streep van
 * de iPhone. Pagina's die hem tonen laten onderaan ruimte vrij; staat die
 * ruimte er niet, dan dekt de balk de laatste regel af.
 *
 * Op een breed scherm verdwijnt de tabbalk en staan dezelfde drie links wél
 * bovenaan — daar is plaats zat en een balk onderaan zou daar zwevend
 * aanvoelen.
 */

type Tab = 'home' | 'clubs' | 'settings'

export function PlayerNav({
  locale, t, active,
}: { locale: Locale; t: T; active: Tab }) {
  const items = [
    { key: 'home' as const, href: '/ik' as const, label: t('me.navHome'), icon: <IconChart /> },
    { key: 'clubs' as const, href: '/clubs' as const, label: t('me.navClubs'), icon: <IconClubs /> },
    { key: 'settings' as const, href: '/ik/gegevens' as const, label: t('me.navSettings'), icon: <IconUser /> },
  ]

  return (
    <>
      <header className="sticky top-0 z-30 border-b border-[var(--line)] bg-[color-mix(in_oklab,var(--bg)_82%,transparent)] backdrop-blur-xl">
        <div className="mx-auto flex max-w-3xl items-center gap-2 px-4 py-3 sm:px-5">
          <Link href="/ik" className="text-sm font-semibold uppercase tracking-[0.2em]">
            Poker<span className="text-[var(--brand)]">League</span>
          </Link>

          <span className="flex-1" />

          {/* Dezelfde drie bestemmingen als onderaan, maar alleen waar ze
              passen. Twee keer tonen zou op een telefoon dubbel zijn. */}
          <nav className="hidden items-center gap-1 sm:flex">
            {items.map((i) => (
              <Link
                key={i.key}
                href={i.href}
                aria-current={active === i.key ? 'page' : undefined}
                className={`rounded-full px-3.5 py-1.5 text-sm transition ${
                  active === i.key
                    ? 'bg-[var(--surface-2)] font-medium text-[var(--text)]'
                    : 'text-[var(--text-muted)] hover:bg-[var(--surface-hover)] hover:text-[var(--text)]'
                }`}
              >
                {i.label}
              </Link>
            ))}
          </nav>

          <span className="hidden sm:block">
            <LanguageSwitch current={locale} label={t('common.language')} />
          </span>

          <form action="/auth/signout" method="post">
            <button
              aria-label={t('common.signOut')}
              title={t('common.signOut')}
              className="flex size-9 items-center justify-center rounded-full text-[var(--text-faint)] transition hover:bg-[var(--surface-hover)] hover:text-[var(--text)]"
            >
              <IconExit />
            </button>
          </form>
        </div>
      </header>

      <nav className="pb-safe fixed inset-x-0 bottom-0 z-30 border-t border-[var(--line)] bg-[color-mix(in_oklab,var(--bg)_88%,transparent)] backdrop-blur-xl sm:hidden">
        <ul className="flex">
          {items.map((i) => {
            const on = active === i.key
            return (
              <li key={i.key} className="flex-1">
                <Link
                  href={i.href}
                  aria-current={on ? 'page' : undefined}
                  className={`relative flex flex-col items-center gap-1 px-2 pb-1.5 pt-2.5 text-[0.68rem] transition ${
                    on ? 'text-[var(--brand)]' : 'text-[var(--text-faint)]'
                  }`}
                >
                  {/* Een streepje bovenaan de actieve tab. Kleur alleen is te
                      weinig verschil als je het scherm schuin in je hand hebt. */}
                  <span
                    aria-hidden
                    className={`absolute inset-x-6 top-0 h-0.5 rounded-full transition ${
                      on ? 'bg-[var(--brand)]' : 'bg-transparent'
                    }`}
                  />
                  {i.icon}
                  <span className="font-medium">{i.label}</span>
                </Link>
              </li>
            )
          })}
        </ul>
      </nav>
    </>
  )
}

/* -------------------------------------------------------------------------
   Iconen als losse SVG'tjes en geen bibliotheek: het zijn er vier, ze erven
   `currentColor`, en een pictogrampakket weegt meer dan deze hele app.
------------------------------------------------------------------------- */

const stroke = {
  fill: 'none',
  stroke: 'currentColor',
  strokeWidth: 1.75,
  strokeLinecap: 'round' as const,
  strokeLinejoin: 'round' as const,
}

function IconChart() {
  return (
    <svg viewBox="0 0 24 24" className="size-[22px]" aria-hidden {...stroke}>
      <path d="M4 19V5" />
      <path d="M4 15.5 9.5 10l3.5 3.5L20 6.5" />
      <path d="M20 6.5h-4.2M20 6.5v4.2" />
    </svg>
  )
}

function IconClubs() {
  return (
    <svg viewBox="0 0 24 24" className="size-[22px]" aria-hidden {...stroke}>
      <path d="M12 3.8c1.9 2.3 3.4 3.7 3.4 5.4A3.4 3.4 0 0 1 12 12.6a3.4 3.4 0 0 1-3.4-3.4c0-1.7 1.5-3.1 3.4-5.4Z" />
      <path d="M8.3 12.1a3.1 3.1 0 1 0 1.9 5.5M15.7 12.1a3.1 3.1 0 1 1-1.9 5.5" />
      <path d="M12 13.6V20M9.6 20h4.8" />
    </svg>
  )
}

function IconUser() {
  return (
    <svg viewBox="0 0 24 24" className="size-[22px]" aria-hidden {...stroke}>
      <circle cx="12" cy="8.5" r="3.6" />
      <path d="M4.8 20a7.2 7.2 0 0 1 14.4 0" />
    </svg>
  )
}

function IconExit() {
  return (
    <svg viewBox="0 0 24 24" className="size-5" aria-hidden {...stroke}>
      <path d="M14 4.8h3.2A1.8 1.8 0 0 1 19 6.6v10.8a1.8 1.8 0 0 1-1.8 1.8H14" />
      <path d="M10 8.5 6.5 12 10 15.5M6.8 12H15" />
    </svg>
  )
}
