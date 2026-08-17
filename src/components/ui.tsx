import Link from 'next/link'

/**
 * Gedeelde bouwstenen.
 *
 * Eén plek waar knoppen, kaarten en velden hun vorm krijgen, zodat schermen
 * er niet elk net iets anders uitzien. Alles gebruikt de CSS-variabelen uit
 * globals.css, dus een clubkleur slaat vanzelf overal door.
 */

// ---------------------------------------------------------------------------
// Knoppen
// ---------------------------------------------------------------------------

type Variant = 'brand' | 'solid' | 'ghost' | 'danger'
type Size = 'sm' | 'md' | 'lg'

const sizes: Record<Size, string> = {
  sm: 'px-3 py-1.5 text-sm gap-1.5',
  md: 'px-4 py-2.5 text-sm gap-2',
  lg: 'px-5 py-3.5 text-base gap-2',
}

const base =
  'inline-flex items-center justify-center rounded-[var(--radius)] font-medium ' +
  'transition-colors duration-150 disabled:cursor-not-allowed disabled:opacity-40 ' +
  'active:translate-y-px select-none'

function variantClass(v: Variant): string {
  switch (v) {
    case 'brand':
      return 'bg-[var(--brand)] text-[var(--on-brand)] hover:brightness-110'
    case 'solid':
      return 'bg-[var(--text)] text-[var(--bg)] hover:bg-white'
    case 'danger':
      return 'border border-[var(--line-strong)] text-[var(--danger)] hover:bg-[var(--surface-hover)]'
    default:
      return 'border border-[var(--line-strong)] text-[var(--text)] hover:bg-[var(--surface-hover)]'
  }
}

export function Button({
  variant = 'ghost', size = 'md', className = '', ...rest
}: React.ButtonHTMLAttributes<HTMLButtonElement> & { variant?: Variant; size?: Size }) {
  return <button className={`${base} ${sizes[size]} ${variantClass(variant)} ${className}`} {...rest} />
}

export function ButtonLink({
  variant = 'ghost', size = 'md', className = '', ...rest
}: React.ComponentProps<typeof Link> & { variant?: Variant; size?: Size }) {
  return <Link className={`${base} ${sizes[size]} ${variantClass(variant)} ${className}`} {...rest} />
}

// ---------------------------------------------------------------------------
// Vlakken
// ---------------------------------------------------------------------------

export function Card({
  className = '', padded = true, ...rest
}: React.HTMLAttributes<HTMLDivElement> & { padded?: boolean }) {
  return (
    <div
      className={`rounded-[var(--radius-lg)] border border-[var(--line)] bg-[var(--surface)] ${
        padded ? 'p-5' : ''
      } ${className}`}
      {...rest}
    />
  )
}

export function Page({ children, width = 'md' }: { children: React.ReactNode; width?: 'md' | 'lg' }) {
  return (
    <main
      className={`mx-auto min-h-dvh w-full ${
        width === 'lg' ? 'max-w-5xl' : 'max-w-3xl'
      } space-y-7 px-5 py-8 sm:px-6`}
    >
      {children}
    </main>
  )
}

export function PageHeader({
  overline, title, subtitle, backHref, backLabel, actions, logoUrl,
}: {
  overline?: string
  title: string
  subtitle?: React.ReactNode
  backHref?: string
  backLabel?: string
  actions?: React.ReactNode
  /** Clublogo, links naast de titel. Hoort bij de kop, niet ergens los. */
  logoUrl?: string | null
}) {
  return (
    <header className="flex flex-wrap items-center justify-between gap-4">
      {logoUrl && (
        <div className="order-first flex size-14 shrink-0 items-center justify-center overflow-hidden rounded-[var(--radius)] border border-[var(--line)] bg-[var(--surface)]">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={logoUrl} alt="" className="size-full object-contain p-1" />
        </div>
      )}
      <div className="min-w-0 flex-1">
        {backHref && (
          <Link
            href={backHref}
            className="mb-1.5 inline-flex items-center gap-1 text-sm text-[var(--text-faint)] transition-colors hover:text-[var(--text-muted)]"
          >
            <span aria-hidden>←</span> {backLabel ?? 'Terug'}
          </Link>
        )}
        {overline && (
          <p className="text-[0.7rem] font-medium uppercase tracking-[0.18em] text-[var(--text-faint)]">
            {overline}
          </p>
        )}
        <h1 className="truncate text-[1.75rem] font-semibold leading-tight tracking-tight">{title}</h1>
        {subtitle && <div className="mt-1 text-sm text-[var(--text-muted)]">{subtitle}</div>}
      </div>
      {actions && <div className="flex shrink-0 flex-wrap items-center gap-2">{actions}</div>}
    </header>
  )
}

export function SectionTitle({ children, action }: { children: React.ReactNode; action?: React.ReactNode }) {
  return (
    <div className="mb-3 flex items-center justify-between gap-3">
      <h2 className="text-[0.7rem] font-medium uppercase tracking-[0.18em] text-[var(--text-faint)]">
        {children}
      </h2>
      {action}
    </div>
  )
}

// ---------------------------------------------------------------------------
// Formulier
// ---------------------------------------------------------------------------

export const inputClass =
  'w-full rounded-[var(--radius)] border border-[var(--line-strong)] bg-[var(--surface-2)] ' +
  'px-3.5 py-2.5 text-[var(--text)] placeholder:text-[var(--text-faint)] ' +
  'transition-colors hover:border-[var(--line-strong)] focus:border-[var(--brand)] focus:outline-none'

export function Field({
  label, hint, error, children,
}: {
  label: string
  hint?: string
  error?: string
  children: React.ReactNode
}) {
  return (
    <label className="block">
      <span className="mb-1.5 block text-sm font-medium text-[var(--text-muted)]">{label}</span>
      {children}
      {error
        ? <span className="mt-1 block text-xs text-[var(--danger)]">{error}</span>
        : hint && <span className="mt-1 block text-xs text-[var(--text-faint)]">{hint}</span>}
    </label>
  )
}

// ---------------------------------------------------------------------------
// Statussen en meldingen
// ---------------------------------------------------------------------------

export function Badge({
  children, tone = 'neutral',
}: { children: React.ReactNode; tone?: 'neutral' | 'ok' | 'warn' | 'live' }) {
  const tones = {
    neutral: 'bg-[var(--surface-2)] text-[var(--text-muted)] border-[var(--line)]',
    ok: 'bg-[color-mix(in_oklab,var(--ok)_14%,transparent)] text-[var(--ok)] border-[color-mix(in_oklab,var(--ok)_30%,transparent)]',
    warn: 'bg-[color-mix(in_oklab,var(--warn)_14%,transparent)] text-[var(--warn)] border-[color-mix(in_oklab,var(--warn)_30%,transparent)]',
    live: 'bg-[color-mix(in_oklab,var(--ok)_14%,transparent)] text-[var(--ok)] border-[color-mix(in_oklab,var(--ok)_30%,transparent)]',
  }
  return (
    <span className={`inline-flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-xs font-medium ${tones[tone]}`}>
      {tone === 'live' && <span className="size-1.5 animate-pulse rounded-full bg-[var(--ok)]" />}
      {children}
    </span>
  )
}

export function Notice({
  tone = 'info', children,
}: { tone?: 'info' | 'warn' | 'error'; children: React.ReactNode }) {
  const tones = {
    info: 'border-[var(--line)] bg-[var(--surface)] text-[var(--text-muted)]',
    warn: 'border-[color-mix(in_oklab,var(--warn)_35%,transparent)] bg-[color-mix(in_oklab,var(--warn)_10%,transparent)] text-[var(--warn)]',
    error: 'border-[color-mix(in_oklab,var(--danger)_35%,transparent)] bg-[color-mix(in_oklab,var(--danger)_10%,transparent)] text-[var(--danger)]',
  }
  return (
    <div className={`rounded-[var(--radius)] border px-4 py-3 text-sm ${tones[tone]}`}>{children}</div>
  )
}

export function EmptyState({
  title, children, action,
}: { title: string; children?: React.ReactNode; action?: React.ReactNode }) {
  return (
    <Card className="flex flex-col items-center gap-3 py-12 text-center">
      <p className="text-base font-medium">{title}</p>
      {children && <p className="max-w-sm text-sm text-[var(--text-muted)]">{children}</p>}
      {action && <div className="mt-1">{action}</div>}
    </Card>
  )
}

export function Stat({
  label, value, sub,
}: { label: string; value: React.ReactNode; sub?: string }) {
  return (
    <div className="rounded-[var(--radius)] border border-[var(--line)] bg-[var(--surface)] px-4 py-3.5">
      <p className="text-[0.65rem] font-medium uppercase tracking-[0.16em] text-[var(--text-faint)]">
        {label}
      </p>
      <p className="tnum mt-1 text-2xl font-semibold leading-none">{value}</p>
      {sub && <p className="mt-1.5 text-xs text-[var(--text-faint)]">{sub}</p>}
    </div>
  )
}
