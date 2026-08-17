/**
 * Een staafgrafiek zonder bibliotheek.
 *
 * Bewust met de hand: een grafiekbibliotheek weegt honderden kilobytes, moet
 * in de browser draaien en zou het enige stuk van dit project zijn dat niet
 * op de server gerenderd wordt. Twaalf staafjes met een schaal erin is
 * rekenwerk van drie regels.
 *
 * Geen assen en geen raster. Boven elke staaf staat het getal zelf; dat leest
 * sneller dan een waarde aflezen tegen een lijn, en op een clubdashboard gaat
 * het om "hoeveel was het in maart" en niet om een precieze curve.
 */
export function BarChart({
  data, format, accent = 'var(--brand)', height = 120,
}: {
  data: { label: string; value: number }[]
  /** Hoe de waarde boven de staaf getoond wordt. */
  format?: (v: number) => string
  accent?: string
  height?: number
}) {
  const max = Math.max(1, ...data.map((d) => d.value))
  const show = format ?? ((v: number) => String(v))

  return (
    <div className="flex items-end gap-1.5 sm:gap-2" style={{ height: height + 34 }}>
      {data.map((d, i) => {
        const h = Math.round((d.value / max) * height)
        return (
          <div key={i} className="flex min-w-0 flex-1 flex-col items-center justify-end gap-1">
            <span className="tnum text-[0.65rem] text-[var(--text-muted)]">
              {d.value > 0 ? show(d.value) : ''}
            </span>
            <div
              className="w-full rounded-t-[3px] transition-[height]"
              style={{
                // Een lege maand krijgt een streepje in plaats van niets:
                // anders lijkt hij te ontbreken in plaats van leeg te zijn.
                height: Math.max(h, d.value > 0 ? 3 : 2),
                background: d.value > 0 ? accent : 'var(--line)',
                opacity: d.value > 0 ? 1 : 1,
              }}
            />
            <span className="w-full truncate text-center text-[0.6rem] uppercase tracking-wide text-[var(--text-faint)]">
              {d.label}
            </span>
          </div>
        )
      })}
    </div>
  )
}
