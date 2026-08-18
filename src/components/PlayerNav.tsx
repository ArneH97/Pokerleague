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
 *
 * **"Gegevens" hoort niet in de tabbalk.** Drie plaatsen onder je duim, en
 * eentje daarvan ging naar een formulier dat je twee keer per jaar opent. Dat
 * is de duurste plek van het scherm aan de zeldzaamste handeling geven. Het
 * staat nu als tandwiel rechtsboven, waar instellingen in elke app staan, en
 * de vrijgekomen tab gaat naar de kalender — de vraag die een speler wél elke
 * week heeft: waar wordt er gespeeld.
 */

type Tab = 'home' | 'clubs' | 'calendar' | 'settings'

export function PlayerNav({
  locale, t, active,
}: { locale: Locale; t: T; active: Tab }) {
  const items = [
    { key: 'home' as const, href: '/ik' as const, label: t('me.navHome'), icon: <IconChart /> },
    { key: 'clubs' as const, href: '/clubs' as const, label: t('me.navClubs'), icon: <IconClubs /> },
    { key: 'calendar' as const, href: '/ik/kalender' as const, label: t('me.navCalendar'), icon: <IconCalendar /> },
  ]

  return (
    <>
      {/* Geen `backdrop-blur` meer op deze twee balken.
          Een doorschijnende, vervaagde balk die vastgeplakt bovenaan staat,
          dwingt Safari om bij elke pixel scrollen het vlak eronder opnieuw te
          vervagen. Op een telefoon zie je dat: de balk loopt achter, hij
          schokt, en dat is precies wat er misging. Een effen achtergrond is
          hier geen compromis — hij is scherper te lezen én hij haakt niet. */}
      <header className="sticky top-0 z-30 border-b border-[var(--line)] bg-[var(--bg)]">
        <div className="pt-safe mx-auto flex max-w-3xl items-center gap-2 px-4 pb-3 sm:px-5">
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

          {/* Het tandwiel. Rechtsboven, waar niemand het hoeft te zoeken omdat
              het in elke app op die plek staat. Actief krijgt het een vlakje
              in plaats van alleen een kleur: op een scherm dat schuin in je
              hand ligt is kleur alleen te weinig verschil. */}
          <Link
            href="/ik/gegevens"
            aria-label={t('me.navSettings')}
            title={t('me.navSettings')}
            aria-current={active === 'settings' ? 'page' : undefined}
            className={`flex size-9 items-center justify-center rounded-full transition ${
              active === 'settings'
                ? 'bg-[var(--surface-2)] text-[var(--text)]'
                : 'text-[var(--text-faint)] hover:bg-[var(--surface-hover)] hover:text-[var(--text)]'
            }`}
          >
            <IconGear />
          </Link>

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

      <nav className="pb-safe fixed inset-x-0 bottom-0 z-30 border-t border-[var(--line)] bg-[var(--bg)] sm:hidden">
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

function IconCalendar() {
  return (
    <svg viewBox="0 0 24 24" className="size-[22px]" aria-hidden {...stroke}>
      <rect x="3.6" y="5.4" width="16.8" height="15" rx="2.6" />
      <path d="M3.6 10h16.8M8.4 3.6v3.4M15.6 3.6v3.4" />
      {/* Eén gevuld dagvakje. Zonder dat is het een leeg raster en leest het
          op 22 pixels als een venster in plaats van als een kalender. */}
      <rect x="7" y="13" width="3.2" height="3" rx="0.9" fill="currentColor" stroke="none" />
    </svg>
  )
}

/**
 * Het tandwiel.
 *
 * Twee keer overgetekend. Eerst als cirkel met acht dunne spaken: dat werd op
 * twintig pixels een zonnetje — het pictogram voor helderheid, niet voor
 * instellingen. Daarna als één omtreklijn met tanden erin, en dat werd een
 * vlek: op deze grootte lopen de tanden van een omtrek in elkaar.
 *
 * Wat wél werkt is de eenvoudigste vorm: een ring met acht korte, dikke
 * tanden erop. Kort en dik is precies het verschil met een zon, en de ring
 * blijft rond in plaats van gekarteld.
 */
function IconGear() {
  return (
    <svg viewBox="0 0 24 24" className="size-5" aria-hidden {...stroke}>
      <circle cx="12" cy="12" r="6.3" />
      <circle cx="12" cy="12" r="2.4" />
      <path
        strokeWidth={2.4}
        strokeLinecap="butt"
        d="M17.8 14.4L20.2 15.4M14.4 17.8L15.4 20.2M9.6 17.8L8.6 20.2M6.2 14.4L3.8 15.4M6.2 9.6L3.8 8.6M9.6 6.2L8.6 3.8M14.4 6.2L15.4 3.8M17.8 9.6L20.2 8.6"
      />
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
