import Link from 'next/link'
import Image from 'next/image'
import { LanguageSwitch } from '@/components/LanguageSwitch'
import type { Club } from '@/lib/club'
import { LocaleProvider } from '@/lib/i18n/context'
import { translator, type Locale } from '@/lib/i18n/dictionaries'

/**
 * Het omhulsel van de publieke clubpagina's.
 *
 * Mobiel eerst, en dat is hier geen slogan: dit wordt gelezen door iemand die
 * aan een pokertafel zit met één hand vrij. Grote raakvlakken, één kolom, en
 * een balk die bovenaan blijft plakken zodat je vanuit een lange lijst met één
 * tik terug bent.
 *
 * Op een breed scherm schuift de navigatie naast de clubnaam in plaats van
 * eronder. Drie tekstjes op een eigen regel onder een balk zien er verloren
 * uit op een monitor; naast het merk lezen ze als een menu.
 *
 * De taal is hier wél te kiezen, in tegenstelling tot de clubkant. Op de floor
 * en op de beamer staat de taal van de club vast — die hoort elke avond
 * hetzelfde te zijn. Maar dit is de bezoekerskant, en een Waalse speler die
 * bij Cutoff komt spelen hoort niet tegen Nederlands aan te kijken.
 *
 * Geen PokerLeague-merk. Dit is de pagina van de club.
 */
export function PublicShell({
  club, locale, active, children, signedIn = true,
}: {
  club: Club
  locale: Locale
  active: 'home' | 'calendar' | 'standings'
  children: React.ReactNode
  /** Zonder account tonen we geen menu-items die op een muur uitkomen. */
  signedIn?: boolean
}) {
  const t = translator(locale)
  // Kalender en klassement vragen een account. Ze in het menu laten staan voor
  // wie er niet in kan, is een deur schilderen op een muur — dan klikt iemand
  // drie keer voor hij begrijpt dat het aan hem ligt en niet aan de club.
  const items = [
    { key: 'home' as const, href: `/c/${club.slug}`, label: t('pub.now') },
    ...(signedIn
      ? [
          { key: 'calendar' as const, href: `/c/${club.slug}/kalender`, label: t('pub.calendar') },
          { key: 'standings' as const, href: `/c/${club.slug}/klassement`, label: t('pub.standings') },
        ]
      : []),
  ]
  const accent = club.primary_color ?? '#10b981'

  const pill = (i: (typeof items)[number]) => (
    <Link
      key={i.key}
      href={i.href}
      aria-current={i.key === active ? 'page' : undefined}
      className={`shrink-0 rounded-full px-4 py-2 text-sm transition ${
        i.key === active
          ? 'bg-[var(--brand)] font-medium text-[var(--on-brand)]'
          : 'text-[var(--text-muted)] hover:bg-[var(--surface-hover)] hover:text-[var(--text)]'
      }`}
    >
      {i.label}
    </Link>
  )

  return (
    <LocaleProvider locale={locale}>
      <div className="relative min-h-dvh overflow-x-hidden">
        <div
          aria-hidden
          className="pointer-events-none absolute inset-x-0 top-0 h-[70vh]"
          style={{ background: `radial-gradient(90vw 45vh at 50% -15%, ${accent}1c 0%, transparent 70%)` }}
        />

        <header className="sticky top-0 z-20 border-b border-[var(--line)] bg-[color-mix(in_oklab,var(--bg)_88%,transparent)] backdrop-blur">
          <div className="mx-auto flex max-w-6xl items-center gap-4 px-4 py-3 sm:px-6 lg:py-4">
            <Link href={`/c/${club.slug}`} className="flex min-w-0 items-center gap-3">
              {club.logo_url && (
                <Image
                  src={club.logo_url}
                  alt=""
                  width={48}
                  height={48}
                  unoptimized
                  className="size-10 shrink-0 rounded-xl object-contain lg:size-12"
                />
              )}
              <span className="truncate text-base font-semibold leading-tight lg:text-lg">
                {club.name}
              </span>
            </Link>

            {/* Vanaf tablet staat het menu op dezelfde regel als het merk. */}
            <nav className="ml-4 hidden gap-1 md:flex">{items.map(pill)}</nav>

            <span className="flex-1" />
            <LanguageSwitch current={locale} label={t('common.language')} />
          </div>

          <nav className="mx-auto flex max-w-6xl gap-1 overflow-x-auto px-4 pb-2 sm:px-6 md:hidden">
            {items.map(pill)}
          </nav>
        </header>

        <main className="relative mx-auto w-full max-w-6xl px-4 py-5 sm:px-6 sm:py-8">
          {children}
        </main>

        {/* Een dunne voet, en verder niets. Het praktische — adres, speeldag,
            contact — staat in de kop van de voorpagina, waar het gelezen
            wordt. Onderaan een tweede keer hetzelfde zetten maakte er een
            losse verzameling kleine kapitalen van. */}
        <footer className="relative mt-12 border-t border-[var(--line)]">
          <div className="mx-auto flex max-w-6xl flex-wrap items-center justify-between gap-3 px-4 py-6 text-xs text-[var(--text-faint)] sm:px-6">
            <span>
              {club.name}
              {club.city ? ` · ${club.city}` : ''}
            </span>
            <Link
              href={`/c/${club.slug}/login`}
              className="underline-offset-4 hover:text-[var(--text)] hover:underline"
            >
              {t('pub.staffLogin')}
            </Link>
          </div>
        </footer>
      </div>
    </LocaleProvider>
  )
}

/**
 * De kop van de voorpagina: wie de club is, en het praktische ernaast.
 *
 * Twee dingen die de vorm bepalen. Het beeldmerk moet groot — klein naast een
 * naam is het een gunstbewijs, groot is het de club. En de rechterhelft moet
 * gevuld zijn: een brede band met alleen links tekst is precies wat een
 * pagina leeg doet lijken op een monitor. Vandaar dat adres, speeldag en
 * contact hier staan en niet in de voet.
 *
 * Op een telefoon valt alles onder elkaar en staat het merk klein bovenaan.
 */
export function ClubMasthead({ club, locale }: { club: Club; locale: Locale }) {
  const t = translator(locale)
  const mark = club.mark_url ?? club.logo_url

  // "Baardegem-Dorp 63, 9310 Aalst · Baardegem" leest als een fout. Staat de
  // gemeente al in de adresregel, dan laten we hem daar staan.
  const stad = club.city ?? ''
  const adres = club.address_line
    ? (stad && !club.address_line.toLowerCase().includes(stad.toLowerCase())
        ? `${club.address_line}, ${stad}`
        : club.address_line)
    : stad || null

  const info = [
    adres ? { k: t('pub.where'), v: adres, href: club.maps_url } : null,
    club.play_rhythm ? { k: t('pub.when'), v: club.play_rhythm, href: null } : null,
    club.contact_email
      ? { k: t('pub.contact'), v: club.contact_email, href: `mailto:${club.contact_email}` }
      : null,
    club.contact_phone
      ? {
          k: club.contact_email ? '' : t('pub.contact'),
          v: club.contact_phone,
          href: `tel:${club.contact_phone.replace(/[^\d+]/g, '')}`,
        }
      : null,
  ].filter((x): x is { k: string; v: string; href: string | null } => x !== null)

  return (
    <section className="relative overflow-hidden rounded-3xl border border-[var(--line)] bg-[var(--surface)]">
      {mark && (
        <Image
          src={mark}
          alt=""
          aria-hidden
          width={640}
          height={640}
          unoptimized
          className="pointer-events-none absolute -bottom-24 -right-16 hidden w-[26rem] object-contain opacity-[0.06] lg:block"
        />
      )}

      <div className="relative grid gap-8 px-5 py-8 sm:px-8 sm:py-10 lg:grid-cols-[1.5fr_1fr] lg:gap-12 lg:px-12 lg:py-14">
        <div className="min-w-0">
          {mark && (
            <Image
              src={mark}
              alt=""
              width={160}
              height={160}
              unoptimized
              className="mb-5 size-16 object-contain object-left sm:size-20 lg:size-24"
            />
          )}
          <h1 className="text-3xl font-semibold leading-[1.05] tracking-tight sm:text-4xl lg:text-5xl">
            {club.name}
          </h1>
          {club.city && (
            <p className="mt-2 text-xs uppercase tracking-[0.22em] text-[var(--text-faint)] sm:text-sm">
              {club.city}
            </p>
          )}
          {club.intro && (
            <p className="mt-5 max-w-prose text-[0.975rem] leading-relaxed text-[var(--text-muted)] sm:text-base">
              {club.intro}
            </p>
          )}
        </div>

        {info.length > 0 && (
          <dl className="grid content-start gap-4 border-t border-[var(--line)] pt-6 lg:border-l lg:border-t-0 lg:pl-12 lg:pt-0">
            {info.map((x, i) => (
              <div key={i}>
                {x.k && (
                  <dt className="text-[0.65rem] uppercase tracking-[0.2em] text-[var(--text-faint)]">
                    {x.k}
                  </dt>
                )}
                <dd className={x.k ? 'mt-1 text-sm' : 'text-sm'}>
                  {x.href ? (
                    <a
                      href={x.href}
                      target={x.href.startsWith('http') ? '_blank' : undefined}
                      rel={x.href.startsWith('http') ? 'noreferrer' : undefined}
                      className="underline-offset-4 hover:underline"
                    >
                      {x.v}
                    </a>
                  ) : x.v}
                </dd>
              </div>
            ))}
          </dl>
        )}
      </div>
    </section>
  )
}
