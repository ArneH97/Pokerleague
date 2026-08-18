import type { T } from '@/lib/i18n/dictionaries'
import { formatMoney } from '@/lib/types'

/**
 * De twee grafieken die een pokerspeler echt bekijkt.
 *
 * **De cumulatieve lijn.** Elke speler die zijn resultaten bijhoudt, tekent
 * deze: netto over de tijd. Niet per sessie — dat is ruis, want één avond zegt
 * niets — maar opgeteld. Daarin zie je in één oogopslag of je erop of eronder
 * staat, en waar het kantelde. Dit is het getal waar een profielpagina om
 * draait; al de rest is context.
 *
 * **Waar je eindigt.** Vijf balkjes: de eindplaats omgerekend naar het bovenste
 * vijfde, het tweede vijfde, enzovoort. Absolute plaatsen kan je niet
 * vergelijken — vierde van tien is beter dan vierde van vijf niet — dus staat
 * hier het aandeel van het veld. Wie vaak in het eerste vijfde eindigt speelt
 * goed, ongeacht de veldgrootte.
 *
 * Met de hand getekende SVG en geen grafiekbibliotheek. Twee redenen: het is
 * hier maar één lijn en vijf balken, en zo'n bibliotheek weegt meer dan deze
 * hele pagina — op een telefoon in de zaal is dat het verschil tussen wel en
 * niet laden. Bovendien rendert dit op de server: geen flikkering, geen
 * skelet, meteen goed.
 */

export interface ChartRow {
  played_on: string
  place: number
  entries: number
  prize_cents: number
  spent_cents: number
}

export function PlayerCharts({
  rows, currency = 'EUR', t, locale,
}: { rows: ChartRow[]; currency?: string; t: T; locale: string }) {
  // Oudste eerst: een lijn die achteruit loopt leest niemand.
  const chrono = [...rows].sort(
    (a, b) => new Date(a.played_on).getTime() - new Date(b.played_on).getTime(),
  )
  if (chrono.length === 0) return null

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

  // Vaste tekenruimte; de SVG schaalt zelf mee met de breedte van zijn kader.
  const W = 320
  const H = 110
  const x = (i: number) =>
    points.length === 1 ? W / 2 : (i / (points.length - 1)) * W
  const y = (v: number) => H - ((v - lo) / span) * H

  const line = points.map((p, i) => `${i === 0 ? 'M' : 'L'}${x(i).toFixed(1)},${y(p.net).toFixed(1)}`).join(' ')
  const area = `${line} L${x(points.length - 1).toFixed(1)},${y(lo)} L${x(0).toFixed(1)},${y(lo)} Z`
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

  return (
    <div className="grid gap-3 sm:grid-cols-[1.6fr_1fr]">
      {/* ------------------------------------------------------- netto ---- */}
      <section className="rounded-[var(--radius)] border border-[var(--line)] bg-[var(--surface)] p-4 sm:p-5">
        <div className="flex flex-wrap items-baseline justify-between gap-x-3">
          <h3 className="text-xs uppercase tracking-[0.22em] text-[var(--text-faint)]">
            {t('chart.netTitle')}
          </h3>
          <p
            className={`tnum text-xl font-semibold ${
              last > 0 ? 'text-[var(--ok)]' : last < 0 ? 'text-[var(--danger)]' : ''
            }`}
          >
            {last > 0 ? '+' : ''}{formatMoney(last, currency)}
          </p>
        </div>

        <svg
          viewBox={`0 0 ${W} ${H}`}
          preserveAspectRatio="none"
          className="mt-3 h-28 w-full sm:h-32"
          role="img"
          aria-label={t('chart.netTitle')}
        >
          <defs>
            <linearGradient id="pl-net" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="var(--brand)" stopOpacity="0.22" />
              <stop offset="100%" stopColor="var(--brand)" stopOpacity="0" />
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

          <path d={area} fill="url(#pl-net)" />
          <path
            d={line}
            fill="none"
            stroke="var(--brand)"
            strokeWidth="2"
            strokeLinejoin="round"
            strokeLinecap="round"
            vectorEffect="non-scaling-stroke"
          />
          <circle cx={x(points.length - 1)} cy={y(last)} r="3.5" fill="var(--brand)" />
        </svg>

        <div className="mt-1 flex justify-between text-[0.65rem] text-[var(--text-faint)]">
          <span>{fmt.format(points[0].at)}</span>
          <span>{fmt.format(points[points.length - 1].at)}</span>
        </div>
      </section>

      {/* -------------------------------------------------- eindplaatsen ---- */}
      <section className="rounded-[var(--radius)] border border-[var(--line)] bg-[var(--surface)] p-4 sm:p-5">
        <h3 className="text-xs uppercase tracking-[0.22em] text-[var(--text-faint)]">
          {t('chart.finishTitle')}
        </h3>
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
                className="w-full rounded-t"
                style={{
                  height: `${Math.max(n > 0 ? 8 : 2, (n / most) * 100)}%`,
                  background: i === 0 ? 'var(--brand)' : 'var(--line-strong)',
                }}
              />
              <span className="text-center text-[0.6rem] text-[var(--text-faint)]">
                {labels[i]}
              </span>
            </li>
          ))}
        </ul>
      </section>
    </div>
  )
}
