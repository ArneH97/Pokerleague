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
 * aan een pokertafel zit met één hand vrij. De kolom is smal, de raakvlakken
 * zijn groot, en de navigatie blijft bovenaan plakken zodat je vanuit een
 * lange klassementslijst met één tik terug bent.
 *
 * Op een breed scherm gaat de kolom niet mee groeien tot een leeglopende
 * bladzijde. In plaats daarvan legt de pagina zelf twee kolommen naast elkaar
 * (zie PublicClubHome) en blijft de leesbreedte hier begrensd. Een smalle
 * kolom in een zwart veld ziet er niet uit; een gevulde raster wel.
 *
 * De taal is hier wél te kiezen, in tegenstelling tot de clubkant. Op de floor
 * en op de beamer staat de taal van de club vast — die hoort elke avond
 * hetzelfde te zijn. Maar dit is de bezoekerskant, en een Waalse speler die
 * bij Cutoff komt spelen hoort niet tegen Nederlands aan te kijken. De keuze
 * gaat in een koekje en geldt daarna overal op het platform.
 *
 * Geen PokerLeague-merk. Dit is de pagina van de club; wie hier komt heeft het
 * adres van de club ingetypt.
 */
export function PublicShell({
  club, locale, active, wide, children,
}: {
  club: Club
  locale: Locale
  active: 'home' | 'calendar' | 'standings'
  /** Zet de inhoud in de brede kolom. Voor pagina's die zelf een raster maken. */
  wide?: boolean
  children: React.ReactNode
}) {
  const t = translator(locale)
  const items = [
    { key: 'home' as const, href: `/c/${club.slug}`, label: t('pub.now') },
    { key: 'calendar' as const, href: `/c/${club.slug}/kalender`, label: t('pub.calendar') },
    { key: 'standings' as const, href: `/c/${club.slug}/klassement`, label: t('pub.standings') },
  ]

  const accent = club.primary_color ?? '#10b981'
  const max = wide ? 'max-w-5xl' : 'max-w-2xl'

  return (
    <LocaleProvider locale={locale}>
      <div className="relative min-h-dvh overflow-x-hidden">
        {/* Zachte gloed in de clubkleur, zodat de pagina niet als een zwart
            gat opent. Dezelfde behandeling als de zaalklok: het hoort één
            product te zijn. */}
        <div
          aria-hidden
          className="pointer-events-none absolute inset-x-0 top-0 h-[60vh]"
          style={{ background: `radial-gradient(80vw 40vh at 50% -10%, ${accent}1f 0%, transparent 70%)` }}
        />

        <header className="sticky top-0 z-20 border-b border-[var(--line)] bg-[color-mix(in_oklab,var(--bg)_86%,transparent)] backdrop-blur">
          <div className={`mx-auto flex ${max} items-center gap-3 px-4 py-3 sm:px-6`}>
            <Link href={`/c/${club.slug}`} className="flex min-w-0 items-center gap-2.5">
              {club.logo_url && (
                <Image
                  src={club.logo_url}
                  alt=""
                  width={36}
                  height={36}
                  unoptimized
                  className="size-9 shrink-0 rounded-lg object-contain"
                />
              )}
              <span className="truncate text-base font-semibold leading-tight">{club.name}</span>
            </Link>
            <span className="flex-1" />
            <LanguageSwitch current={locale} label={t('common.language')} />
          </div>

          {/* Drie woorden, dus dit past op elke telefoon. Wel scrollbaar voor
              het geval een taal er lange woorden van maakt. */}
          <nav className={`mx-auto flex ${max} gap-1 overflow-x-auto px-4 pb-2 sm:px-6`}>
            {items.map((i) => (
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
            ))}
          </nav>
        </header>

        <main className={`relative mx-auto w-full ${max} px-4 py-5 sm:px-6 sm:py-7`}>
          {children}
        </main>

        <PublicFooter club={club} locale={locale} max={max} />
      </div>
    </LocaleProvider>
  )
}

/**
 * De voet met het praktische.
 *
 * Adres, speeldag en contact staan hier en niet bovenaan: wie de club kent
 * scrolt er nooit heen, en wie hem niet kent leest eerst wat er te doen is en
 * pas daarna waar het is. Wat niet ingevuld is verdwijnt — een kop "Adres"
 * met een streepje eronder is erger dan geen kop.
 */
function PublicFooter({ club, locale, max }: { club: Club; locale: Locale; max: string }) {
  const t = translator(locale)
  const heeftInfo = club.address_line || club.play_rhythm || club.contact_email || club.contact_phone
  const plaats = [club.address_line, club.city].filter(Boolean).join(' · ')

  return (
    <footer className="relative mt-10 border-t border-[var(--line)]">
      <div className={`mx-auto ${max} px-4 py-8 sm:px-6`}>
        {heeftInfo && (
          <dl className="grid gap-5 sm:grid-cols-3">
            {plaats && (
              <div>
                <dt className="text-xs uppercase tracking-[0.18em] text-[var(--text-faint)]">
                  {t('pub.where')}
                </dt>
                <dd className="mt-1 text-sm">
                  {club.maps_url ? (
                    <a
                      href={club.maps_url}
                      target="_blank"
                      rel="noreferrer"
                      className="underline-offset-4 hover:underline"
                    >
                      {plaats}
                    </a>
                  ) : plaats}
                </dd>
              </div>
            )}

            {club.play_rhythm && (
              <div>
                <dt className="text-xs uppercase tracking-[0.18em] text-[var(--text-faint)]">
                  {t('pub.when')}
                </dt>
                <dd className="mt-1 text-sm">{club.play_rhythm}</dd>
              </div>
            )}

            {(club.contact_email || club.contact_phone) && (
              <div>
                <dt className="text-xs uppercase tracking-[0.18em] text-[var(--text-faint)]">
                  {t('pub.contact')}
                </dt>
                <dd className="mt-1 space-y-0.5 text-sm">
                  {club.contact_email && (
                    <a href={`mailto:${club.contact_email}`} className="block underline-offset-4 hover:underline">
                      {club.contact_email}
                    </a>
                  )}
                  {club.contact_phone && (
                    <a
                      href={`tel:${club.contact_phone.replace(/[^\d+]/g, '')}`}
                      className="block underline-offset-4 hover:underline"
                    >
                      {club.contact_phone}
                    </a>
                  )}
                </dd>
              </div>
            )}
          </dl>
        )}

        <p className="mt-8 text-center">
          <Link
            href={`/c/${club.slug}/login`}
            className="text-xs text-[var(--text-faint)] underline-offset-4 hover:underline"
          >
            {t('pub.staffLogin')}
          </Link>
        </p>
      </div>
    </footer>
  )
}
