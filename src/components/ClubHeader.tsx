import Link from 'next/link'

/**
 * Kop van de clubomgeving.
 *
 * Heeft de club een logo, dan krijgt dat het midden en groot, en verdwijnt de
 * clubnaam als losse tekst — een logo zoals dat van Cutoff bevat de naam en
 * de baseline al, dus die er nog eens naast zetten is dubbelop. Zonder logo
 * valt alles terug op een gewone tekstkop, zodat een club zonder beeldmerk er
 * niet kaal uitziet.
 */
export function ClubHeader({
  name, city, subtitle, logoUrl, actions, homeHref,
}: {
  name: string
  city?: string | null
  subtitle?: string
  logoUrl?: string | null
  actions?: React.ReactNode
  /** Maakt het logo klikbaar terug naar het clubdashboard. */
  homeHref?: string
}) {
  const mark = logoUrl ? (
    // eslint-disable-next-line @next/next/no-img-element
    <img
      src={logoUrl}
      alt={name}
      className="h-28 w-auto max-w-[16rem] object-contain sm:h-36"
    />
  ) : null

  return (
    <header className="flex flex-col items-center gap-5 pb-2 pt-2 text-center">
      {mark ? (
        <>
          {homeHref ? <Link href={homeHref}>{mark}</Link> : mark}
          {/* Voor schermlezers en zoekmachines blijft de naam bestaan. */}
          <h1 className="sr-only">{name}</h1>
          {(city || subtitle) && (
            <p className="text-xs font-medium uppercase tracking-[0.22em] text-[var(--text-faint)]">
              {[city, subtitle].filter(Boolean).join(' · ')}
            </p>
          )}
        </>
      ) : (
        <div>
          {city && (
            <p className="text-[0.7rem] font-medium uppercase tracking-[0.18em] text-[var(--text-faint)]">
              {city}
            </p>
          )}
          <h1 className="text-3xl font-semibold tracking-tight">{name}</h1>
          {subtitle && <p className="mt-1 text-sm text-[var(--text-muted)]">{subtitle}</p>}
        </div>
      )}

      {actions && <div className="flex flex-wrap items-center justify-center gap-2">{actions}</div>}
    </header>
  )
}
