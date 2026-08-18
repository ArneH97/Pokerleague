import type { T } from '@/lib/i18n/dictionaries'
import { formatMoney } from '@/lib/types'

/**
 * De twee grafieken die een pokerspeler echt bekijkt.
 *
 * **De cumulatieve lijn.** Elke speler die zijn resultaten bijhoudt, tekent
 * deze: netto over de tijd. Niet per sessie — dat is ruis, want één avond zegt
 * niets — maar opgeteld. Daarin zie je in één oogopslag of je erop of eronder
 * staat, en waar het kantelde.
 *
 * **Waar je eindigt.** Vijf balkjes: de eindplaats omgerekend naar het bovenste
 * vijfde, het tweede vijfde, enzovoort. Absolute plaatsen kan je niet
 * vergelijken — vierde van tien is beter dan vierde van vijf niet — dus staat
 * hier het aandeel van het veld.
 *
 * **Niet tekenen wat er niet is.** Met één sessie was dit een leeg kader met
 * een stipje in het midden en een balkje ernaast: het zag eruit als een scherm
 * dat kapot is, en het was het eerste wat een nieuwe speler te zien kreeg. Een
 * lijn heeft twee punten nodig en een verdeling heeft er een handvol nodig
 * voor ze iets betekent. Tot dan staat er één kaart die zegt vanaf wanneer je
 * hier iets ziet — dat is eerlijker en het geeft je een reden om terug te
 * komen.
 *
 * Met de hand getekende SVG en geen grafiekbibliotheek. Het is hier één lijn
 * en vijf balken, en zo'n bibliotheek weegt meer dan deze hele pagina — op een
 * telefoon in de zaal is dat het verschil tussen wel en niet laden. Bovendien
 * rendert dit op de server: geen flikkering, geen skelet, meteen goed.
 */

export interface ChartRow {
  played_on: string
  place: number
  entries: number
  prize_cents: number
  spent_cents: number
}

const MIN_LINE = 2
const MIN_BARS = 4

export function PlayerCharts({
  rows, currency = 'EUR', t, locale,
}: { rows: ChartRow[]; currency?: string; t: T; locale: string }) {
  // Oudste eerst: een lijn die achteruit loopt leest niemand.
  const chrono = [...rows].sort(
    (a, b) => new Date(a.played_on).getTime() - new Date(b.played_on).getTime(),
  )
  if (chrono.length === 0) return null

  if (chrono.length < MIN_LINE) {
    return (
      <Panel title={t('chart.netTitle')}>
        <p className="text-sm leading-relaxed text-[var(--text-muted)]">{t('chart.soon')}</p>
      </Panel>
    )
  }

  // Optellen zonder een variabele buiten de expressie bij te werken: de
  // lintregel tegen herschrijven na de render is hier streng, en terecht — een
  // teller die tussen twee renders blijft hangen geeft een grafiek die
  // verdubbelt zonder dat je begrijpt waarom.
  const points = chrono.reduce<{ at: Date; net: number }[]>((acc, r) => {
    const prev = acc.length > 0 ? acc[acc.length - 1].net : 0
    acc.push({
      at: new Date(r.played_on),
      net: prev + Number(r.prize_cents) - Number(r.spent_cents),
    })
    return acc
  }, [])

  const nets = points.map((p) => p.net)
  const hi = Math.max(0, ...nets)
  const lo = Math.min(0, ...nets)
  const span = hi - lo || 1
  const last = nets[nets.length - 1]
  const up = last >= 0

  // Vaste tekenruimte; de SVG schaalt zelf mee met de breedte van zijn kader.
  // Een kleine marge boven en onder, anders raakt de lijn de rand en lijkt ze
  // afgesneden.
  const W = 320
  const H = 110
  const PAD = 8
  const x = (i: number) => (i / (points.length - 1)) * W
  const y = (v: number) => PAD + (H - 2 * PAD) * (1 - (v - lo) / span)

  const line = points
    .map((p, i) => `${i === 0 ? 'M' : 'L'}${x(i).toFixed(1)},${y(p.net).toFixed(1)}`)
    .join(' ')
  const area = `${line} L${W},${H} L0,${H} Z`
  const zero = y(0)

  // ------------------------------------------------------- eindplaatsen ---
  const buckets = [0, 0, 0, 0, 0]
  for (const r of chrono) {
    if (!r.entries || r.entries < 1) continue
    // (plaats − 1) / veld → 0 is winnaar, bijna 1 is laatste.
    const share = (r.place - 1) / r.entries
    buckets[Math.min(4, Math.floor(share * 5))] += 1
  }
  const most = Math.max(...buckets, 1)
  const labels = [t('chart.top20'), '2', '3', '4', t('chart.bottom20')]

  const fmt = new Intl.DateTimeFormat(`${locale}-BE`, {
    month: 'short', year: '2-digit', timeZone: 'Europe/Brussels',
  })

  const enough = chrono.length >= MIN_BARS
  const stroke = up ? 'var(--ok)' : 'var(--danger)'

  return (
    <div className={`grid gap-3 ${enough ? 'sm:grid-cols-[1.55fr_1fr]' : ''}`}>
      {/* ------------------------------------------------------- netto ---- */}
      <Panel
        title={t('chart.netTitle')}
        right={
          <span
            className={`tnum text-lg font-semibold ${
              last > 0 ? 'text-[var(--ok)]' : last < 0 ? 'text-[var(--danger)]' : ''
            }`}
          >
            {last > 0 ? '+' : ''}{formatMoney(last, currency)}
          </span>
        }
      >
        <svg
          viewBox={`0 0 ${W} ${H}`}
          preserveAspectRatio="none"
          className="mt-3 h-28 w-full sm:h-32"
          role="img"
          aria-label={t('chart.netTitle')}
        >
          <defs>
            <linearGradient id="pl-net-fill" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor={stroke} stopOpacity="0.30" />
              <stop offset="100%" stopColor={stroke} stopOpacity="0" />
            </linearGradient>
            {/* De lijn zelf verloopt van blauw naar de winst- of verlieskleur:
                links waar je begon is neutraal, rechts staat waar je nu bent. */}
            <linearGradient id="pl-net-line" x1="0" y1="0" x2="1" y2="0">
              <stop offset="0%" stopColor="var(--accent)" />
              <stop offset="100%" stopColor={stroke} />
            </linearGradient>
          </defs>

          {/* De nullijn. Zonder die lijn weet je niet of je boven of onder staat. */}
          {lo < 0 && hi > 0 && (
            <line
              x1="0" y1={zero} x2={W} y2={zero}
              stroke="var(--line-strong)" strokeWidth="1" strokeDasharray="3 3"
              vectorEffect="non-scaling-stroke"
            />
          )}

          <path d={area} fill="url(#pl-net-fill)" />
          <path
            d={line}
            fill="none"
            stroke="url(#pl-net-line)"
            strokeWidth="2.5"
            strokeLinejoin="round"
            strokeLinecap="round"
            vectorEffect="non-scaling-stroke"
          />
          {/* Twee cirkels op het laatste punt: een zachte halo en de stip zelf.
              Dat leest als "hier sta je nu" in plaats van als het einde van
              een streep. */}
          <circle cx={x(points.length - 1)} cy={y(last)} r="7" fill={stroke} opacity="0.22" />
          <circle
            cx={x(points.length - 1)} cy={y(last)} r="3.5"
            fill={stroke} stroke="var(--bg)" strokeWidth="1.5"
          />
        </svg>

        <div className="mt-1 flex justify-between text-[0.65rem] text-[var(--text-faint)]">
          <span>{fmt.format(points[0].at)}</span>
          <span>{fmt.format(points[points.length - 1].at)}</span>
        </div>
      </Panel>

      {/* -------------------------------------------------- eindplaatsen ----
          Pas vanaf een handvol avonden. Met twee sessies is een verdeling over
          vijf vakjes geen verdeling maar twee losse balkjes. */}
      {enough && (
        <Panel title={t('chart.finishTitle')}>
          <p className="mt-1 text-[0.7rem] leading-relaxed text-[var(--text-faint)]">
            {t('chart.finishHint')}
          </p>

          <ul className="mt-3 flex h-24 items-end gap-1.5 sm:h-28">
            {buckets.map((n, i) => (
              <li key={i} className="flex h-full flex-1 flex-col justify-end gap-1">
                <span className="tnum text-center text-[0.65rem] text-[var(--text-faint)]">
                  {n || ''}
                </span>
                <span
                  className="w-full rounded-t-md"
                  style={{
                    height: `${Math.max(n > 0 ? 8 : 2, (n / most) * 100)}%`,
                    background:
                      n === 0
                        ? 'var(--line)'
                        : i === 0
                          ? 'linear-gradient(to top, color-mix(in oklab, var(--gold) 55%, transparent), var(--gold))'
                          : `color-mix(in oklab, var(--accent) ${70 - i * 12}%, transparent)`,
                  }}
                />
                <span className="text-center text-[0.6rem] text-[var(--text-faint)]">
                  {labels[i]}
                </span>
              </li>
            ))}
          </ul>
        </Panel>
      )}
    </div>
  )
}

function Panel({
  title, right, children,
}: { title: string; right?: React.ReactNode; children: React.ReactNode }) {
  return (
    <section className="rounded-[var(--radius)] border border-[var(--line)] bg-[var(--surface)] p-4 sm:p-5">
      <div className="flex flex-wrap items-baseline justify-between gap-x-3">
        <h3 className="text-xs uppercase tracking-[0.22em] text-[var(--text-faint)]">{title}</h3>
        {right}
      </div>
      {children}
    </section>
  )
}
