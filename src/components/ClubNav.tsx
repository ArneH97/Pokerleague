import Link from 'next/link'
import type { T } from '@/lib/i18n/dictionaries'

/**
 * De navigatie van de clubomgeving.
 *
 * Stond eerst als een rijtje links onderaan de pagina. Dat werkt zolang er
 * één pagina is, maar met tornooien, klassement, ledenbestand, cijfers en
 * structuren moet je eerst langs de hele tornooilijst scrollen om ergens
 * anders te geraken. Nu staat het bovenaan, op elke pagina dezelfde volgorde,
 * met de huidige pagina gemarkeerd.
 *
 * Wat je niet mag zien staat er ook niet: het ledenbestand en de cijfers zijn
 * voor staf. Een link tonen die op een weigering uitloopt is erger dan geen
 * link.
 */
export function ClubNav({
  slug, active, canManage, t, account,
}: {
  slug: string
  active: 'tournaments' | 'standings' | 'members' | 'stats' | 'structures' | 'settings'
  canManage: boolean
  t: T
  /** Het mailadres waarmee je hier aangemeld bent. Zie de uitleg hieronder. */
  account?: string | null
}) {
  const items: { key: typeof active; href: string; label: string; staff?: boolean }[] = [
    { key: 'tournaments', href: `/c/${slug}`, label: t('club.tournaments') },
    { key: 'standings', href: `/c/${slug}/klassement`, label: t('standings.title') },
    { key: 'members', href: `/c/${slug}/leden`, label: t('members.title'), staff: true },
    { key: 'stats', href: `/c/${slug}/statistieken`, label: t('stats.title'), staff: true },
    { key: 'structures', href: `/c/${slug}/structuren`, label: t('struct.title'), staff: true },
    { key: 'settings', href: `/c/${slug}/instellingen`, label: t('settings.title'), staff: true },
  ]

  return (
    <nav className="-mx-1 flex flex-wrap items-center gap-1 overflow-x-auto border-b border-[var(--line)] pb-2">
      {items
        .filter((i) => !i.staff || canManage)
        .map((i) => (
          <Link
            key={i.key}
            href={i.href}
            aria-current={i.key === active ? 'page' : undefined}
            className={`whitespace-nowrap rounded-[var(--radius)] px-3 py-2 text-sm transition ${
              i.key === active
                ? 'bg-[var(--surface-2)] font-medium text-[var(--text)]'
                : 'text-[var(--text-muted)] hover:bg-[var(--surface-hover)] hover:text-[var(--text)]'
            }`}
          >
            {i.label}
          </Link>
        ))}

      {/* Met welk account je hier bezig bent.
          Dit lijkt een detail en is het niet. Eén persoon kan twee accounts
          hebben — zijn spelersaccount en het account waarmee hij de club
          beheert — en zolang nergens staat welk van de twee actief is, kan
          een scherm heel redelijk niets tonen zonder dat iemand begrijpt
          waarom. Dat is precies wat er gebeurd is bij de uitnodigingen: de
          wachtrij stond vol en het scherm zei nul, omdat er met het verkeerde
          account gekeken werd. */}
      {account && (
        <span className="ml-auto shrink-0 pl-3 text-xs text-[var(--text-faint)]">
          <span className="hidden sm:inline">{t('nav.signedInAs')} </span>
          <span className="text-[var(--text-muted)]">{account}</span>
        </span>
      )}
    </nav>
  )
}
