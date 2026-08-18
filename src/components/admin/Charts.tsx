import { formatMoney } from '@/lib/types'

/**
 * De grafieken van het platformdashboard.
 *
 * Met de hand getekende SVG, net als bij de spelerspagina en om dezelfde
 * redenen: dit rendert op de server, weegt niets, en volgt de kleuren uit
 * globals.css zonder een thema te moeten dupliceren in JavaScript.
 *
 * Drie regels die hier overal gelden:
 *
 * **Nooit twee assen in één grafiek.** Euro's en deelnames op dezelfde tekening
 * met elk hun eigen schaal is een verband suggereren dat er niet is. Twee
 * grootheden betekent twee grafieken.
 *
 * **Kleur hoort bij wie het is, niet bij hoe groot het is.** De clubs worden
 * getekend in hun eigen huisstijlkleur, en die blijft dezelfde als er een club
 * bijkomt of wegvalt. Een club herkennen aan haar kleur werkt alleen als die
 * kleur niet verspringt.
 *
 * **Kleur alleen volstaat niet.** Elke grafiek met meer dan één reeks heeft een
 * legende, en waar het past staat het getal er gewoon bij. Wie kleuren minder
 * goed onderscheidt — en bij de amberen en gouden tinten hier is dat niet
 * denkbeeldig — leest dan nog altijd wat er staat.
 *
 * Elk vlak heeft een `<title>`: dat is de tooltip van de browser zelf, zonder
 * één regel JavaScript.
 */

// ---------------------------------------------------------------------------
// Gestapelde maandstaven
// ---------------------------------------------------------------------------

export interface StackSeries {
  key: string
  label: string
  color: string
  values: number[]
}

/**
 * Eén staaf per maand, opgedeeld in reeksen die samen een geheel vormen.
 *
 * Alleen gebruiken waar de delen écht optellen tot het totaal — het geld aan
 * de deur is prijzenpot plus clubbijdrage plus bounty's, en de deelnames per
 * club tellen op tot alle deelnames. Twee dingen stapelen die niets met elkaar
 * te maken hebben geeft een staaf waarvan de hoogte niets betekent.
 */
export function StackedMonths({
  labels, series, format, height = 150, emptyLabel, wideLabels = false,
}: {
  labels: string[]
  series: StackSeries[]
  format: (v: number) => string
  height?: number
  emptyLabel: string
  /**
   * Zet dit aan wanneer het getal boven de staaf een bedrag is.
   *
   * Twaalf maanden op een telefoon geeft kolommen van dertig pixels, en
   * "€ 1.100" wordt daarin "€ 1…" — een getal waar niemand iets aan heeft en
   * dat er alleen maar rommelig uitziet. Dan liever niets: het totaal staat in
   * de kop en de legende geeft de som per reeks. Op een breed scherm is er wel
   * plaats en komen ze gewoon terug.
   */
  wideLabels?: boolean
}) {
  const totals = labels.map((_, i) => series.reduce((sum, s) => sum + (s.values[i] ?? 0), 0))
  const max = Math.max(1, ...totals)
  const anything = totals.some((v) => v > 0)

  return (
    <div>
      <div className="flex items-end gap-1 sm:gap-1.5" style={{ height: height + 38 }}>
        {labels.map((label, i) => {
          const total = totals[i]
          return (
            <div key={label + i} className="flex min-w-0 flex-1 flex-col items-center justify-end gap-1">
              {/* `truncate` is hier geen luxe. Zonder die regel maakt "€ 1.100"
                  de kolom breder dan zijn twaalfde van de ruimte, en groeit de
                  hele grafiek — en daarmee het kader eromheen — buiten het
                  scherm van een telefoon. */}
              <span
                className={`tnum w-full truncate text-center text-[0.6rem] leading-none text-[var(--text-muted)] ${
                  wideLabels ? 'hidden sm:block' : ''
                }`}
              >
                {total > 0 ? format(total) : ''}
              </span>

              {/* De staaf zelf. De segmenten staan van onder naar boven in de
                  volgorde van de reeksen, met een haarlijn ertussen zodat twee
                  aangrenzende kleuren niet in elkaar overlopen. */}
              <div
                className="flex w-full flex-col-reverse overflow-hidden rounded-t-[4px]"
                style={{ height: Math.max(2, (total / max) * height) }}
              >
                {total === 0 && <span className="h-full w-full bg-[var(--line)]" />}
                {series.map((s) => {
                  const v = s.values[i] ?? 0
                  if (v <= 0) return null
                  return (
                    <span
                      key={s.key}
                      className="w-full"
                      style={{
                        height: `${(v / total) * 100}%`,
                        background: s.color,
                        boxShadow: 'inset 0 -2px 0 0 var(--surface)',
                      }}
                    >
                      <title>{`${label} · ${s.label}: ${format(v)}`}</title>
                    </span>
                  )
                })}
              </div>

              <span className="w-full truncate text-center text-[0.6rem] uppercase tracking-wide text-[var(--text-faint)]">
                {label}
              </span>
            </div>
          )
        })}
      </div>

      {!anything && (
        <p className="mt-2 text-center text-xs text-[var(--text-faint)]">{emptyLabel}</p>
      )}

      {series.length > 1 && (
        <Legend items={series.map((s) => ({
          label: s.label,
          color: s.color,
          value: format(s.values.reduce((a, b) => a + b, 0)),
        }))} />
      )}
    </div>
  )
}

// ---------------------------------------------------------------------------
// Eén lijn over de tijd
// ---------------------------------------------------------------------------

/**
 * Een oplopende lijn met een vlak eronder. Eén reeks, dus geen legende: de
 * titel van het kader zegt al wat er staat.
 *
 * De schaal begint altijd op nul. Een grafiek die op het laagste punt begint
 * maakt van een verschil van drie procent een klim van veertig graden, en dat
 * is precies het soort cijfer waar je jezelf mee voor de gek houdt.
 */
export function AreaLine({
  labels, values, color = 'var(--brand)', format, height = 140, caption,
}: {
  labels: string[]
  values: number[]
  color?: string
  format: (v: number) => string
  height?: number
  caption?: string
}) {
  const W = 320
  const H = 100
  const PAD = 6
  const max = Math.max(1, ...values)
  const n = values.length

  const x = (i: number) => (n <= 1 ? W / 2 : (i / (n - 1)) * W)
  const y = (v: number) => PAD + (H - 2 * PAD) * (1 - v / max)

  const line = values.map((v, i) => `${i === 0 ? 'M' : 'L'}${x(i).toFixed(1)},${y(v).toFixed(1)}`).join(' ')
  const area = `${line} L${W},${H} L0,${H} Z`
  const last = values[n - 1] ?? 0

  return (
    <div>
      <div className="relative" style={{ height }}>
        <svg
          viewBox={`0 0 ${W} ${H}`}
          preserveAspectRatio="none"
          className="h-full w-full"
          role="img"
          aria-label={caption ?? ''}
        >
          <defs>
            <linearGradient id="pl-adm-fill" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor={color} stopOpacity="0.28" />
              <stop offset="100%" stopColor={color} stopOpacity="0" />
            </linearGradient>
          </defs>

          {/* Een haarlijn op de helft van de schaal. Geen streepjeslijn: die
              ruist meer dan ze helpt op een grafiek van deze grootte. */}
          <line
            x1="0" y1={y(max / 2)} x2={W} y2={y(max / 2)}
            stroke="var(--line)" strokeWidth="1" vectorEffect="non-scaling-stroke"
          />

          <path d={area} fill="url(#pl-adm-fill)" />
          <path
            d={line} fill="none" stroke={color} strokeWidth="2"
            strokeLinejoin="round" strokeLinecap="round" vectorEffect="non-scaling-stroke"
          />
          <circle cx={x(n - 1)} cy={y(last)} r="7" fill={color} opacity="0.2" />
          <circle cx={x(n - 1)} cy={y(last)} r="3.5" fill={color} stroke="var(--bg)" strokeWidth="1.5" />
        </svg>
      </div>

      {/* Alleen de eerste en de laatste maand. Er stond hier eerst ook de
          eindwaarde tussenin, en die las als een meting halverwege het jaar —
          precies het soort getal dat je onthoudt en dat nergens op slaat. Het
          totaal hoort in de kop van het kader. */}
      <div className="mt-1 flex items-baseline justify-between text-[0.65rem] text-[var(--text-faint)]">
        <span>{labels[0]}</span>
        <span className="sr-only">{format(last)}</span>
        <span>{labels[labels.length - 1]}</span>
      </div>
    </div>
  )
}

// ---------------------------------------------------------------------------
// Verdeling over de clubs
// ---------------------------------------------------------------------------

/**
 * Eén liggende balk per club. Geen taartdiagram: met twee of drie clubs die
 * dicht bij elkaar liggen is een taart onleesbaar, en met tien is het een
 * kleurenwaaier. Balken van gelijke lengte-as vergelijken doe je met je oog in
 * één beweging.
 */
export function ClubBars({
  rows, format, emptyLabel,
}: {
  rows: { label: string; value: number; color: string; sub?: string }[]
  format: (v: number) => string
  emptyLabel: string
}) {
  const max = Math.max(1, ...rows.map((r) => r.value))
  if (rows.length === 0) {
    return <p className="text-sm text-[var(--text-faint)]">{emptyLabel}</p>
  }

  return (
    <ul className="space-y-2.5">
      {rows.map((r) => (
        <li key={r.label}>
          <div className="flex items-baseline justify-between gap-3 text-sm">
            <span className="flex min-w-0 items-center gap-2">
              <span
                aria-hidden
                className="size-2.5 shrink-0 rounded-full"
                style={{ background: r.color }}
              />
              <span className="truncate">{r.label}</span>
            </span>
            <span className="tnum shrink-0 text-[var(--text-muted)]">
              {format(r.value)}
              {r.sub && <span className="ml-2 text-[var(--text-faint)]">{r.sub}</span>}
            </span>
          </div>
          <div className="mt-1.5 h-2 w-full overflow-hidden rounded-full bg-[var(--surface-2)]">
            <div
              className="h-full rounded-full"
              style={{ width: `${Math.max(r.value > 0 ? 2 : 0, (r.value / max) * 100)}%`, background: r.color }}
            />
          </div>
        </li>
      ))}
    </ul>
  )
}

// ---------------------------------------------------------------------------
// Legende
// ---------------------------------------------------------------------------

export function Legend({
  items,
}: { items: { label: string; color: string; value?: string }[] }) {
  return (
    <ul className="mt-3 flex flex-wrap gap-x-4 gap-y-1.5 border-t border-[var(--line)] pt-3">
      {items.map((it) => (
        <li key={it.label} className="flex items-center gap-2 text-xs">
          <span aria-hidden className="size-2.5 rounded-[3px]" style={{ background: it.color }} />
          <span className="text-[var(--text-muted)]">{it.label}</span>
          {it.value && <span className="tnum text-[var(--text-faint)]">{it.value}</span>}
        </li>
      ))}
    </ul>
  )
}

// ---------------------------------------------------------------------------
// Kaders en cijfers
// ---------------------------------------------------------------------------

export function Panel({
  title, right, children, className = '',
}: {
  title: string
  right?: React.ReactNode
  children: React.ReactNode
  className?: string
}) {
  // `min-w-0` hieronder is geen detail: een kader is bijna altijd een cel van
  // een grid, en zo'n cel groeit met haar inhoud mee tenzij je dat verbiedt.
  // Eén brede tabel of één lang getal duwde zo de hele pagina breder dan een
  // telefoonscherm, met een kop die half buiten beeld viel.
  return (
    <section
      className={`min-w-0 rounded-[var(--radius-lg)] border border-[var(--line)] bg-[var(--surface)] p-4 sm:p-5 ${className}`}
    >
      <div className="mb-3 flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
        <h2 className="text-[0.7rem] font-medium uppercase tracking-[0.18em] text-[var(--text-faint)]">
          {title}
        </h2>
        {right}
      </div>
      {children}
    </section>
  )
}

/**
 * Eén cijfer, groot.
 *
 * De belangrijkste "grafiek" op dit scherm. Voor een getal dat op zichzelf
 * staat — het aantal clubs, de maandelijkse omzet — is een staaf van één balk
 * geen grafiek maar een omweg.
 */
export function Tile({
  label, value, sub, tone = 'plain',
}: {
  label: string
  value: React.ReactNode
  sub?: React.ReactNode
  tone?: 'plain' | 'brand' | 'accent' | 'ok'
}) {
  const color =
    tone === 'brand' ? 'text-[var(--brand)]'
      : tone === 'accent' ? 'text-[var(--accent)]'
        : tone === 'ok' ? 'text-[var(--ok)]'
          : ''

  return (
    <div className="rounded-[var(--radius)] border border-[var(--line)] bg-[var(--surface)] px-4 py-3.5">
      <p className="text-[0.6rem] font-medium uppercase tracking-[0.16em] text-[var(--text-faint)]">
        {label}
      </p>
      <p className={`tnum mt-1.5 text-2xl font-semibold leading-none sm:text-[1.7rem] ${color}`}>
        {value}
      </p>
      {sub && <p className="mt-1.5 text-xs leading-snug text-[var(--text-faint)]">{sub}</p>}
    </div>
  )
}

/** Euro's, zonder centen als het ronde bedragen zijn. */
export function money(cents: number | string): string {
  return formatMoney(Number(cents))
}

/** Duizendtallen met een punt, zoals overal in het product. */
export function num(v: number | string): string {
  return new Intl.NumberFormat('nl-BE').format(Number(v))
}
