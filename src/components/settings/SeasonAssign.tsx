import { inputClass } from '@/components/ui'
import type { T } from '@/lib/i18n/dictionaries'
import { formatMoney } from '@/lib/types'

/** Eén avond in het toewijsscherm. Komt uit season_tournaments(). */
export interface AssignRow {
  id: string
  name: string
  scheduled_at: string
  status: string
  season_id: string | null
  season_name: string | null
  results: number
  players: number
  buyin_cents: number
  fee_cents: number
}

/**
 * Welke avond bij welk seizoen hoort.
 *
 * Het seizoen van een tornooi stond al in het bewerkscherm, maar daarvoor
 * moet je elk tornooi apart openen. Wie een league middenin de kalender
 * begint — en dat is de normale gang van zaken, want een league begin je
 * omdat je al een tijdje speelt — wil de lijst zien en toewijzen.
 *
 * Per rij gaan er twee velden mee: wat er nu staat en wat het was. Alleen wat
 * verschilt gaat naar de database. Dat is geen zuinigheid: elke wijziging
 * rekent de punten van die avond opnieuw door, en dat hoort niet te gebeuren
 * voor veertig avonden waar niemand iets aan veranderd heeft.
 *
 * Op een telefoon staat de keuzelijst onder de naam en niet ernaast. Een
 * naam, een datum, een bedrag en een keuzelijst op één regel van 390 pixels
 * levert vier afgeknotte dingen op in plaats van één leesbare rij.
 */
export function SeasonAssign({
  tournaments, seasons, locale, timezone, currency, t,
}: {
  tournaments: AssignRow[]
  seasons: { id: string; name: string }[]
  locale: string
  timezone: string
  currency: string
  t: T
}) {
  if (tournaments.length === 0) {
    return <p className="text-sm text-[var(--text-muted)]">{t('settings.assignEmpty')}</p>
  }

  const datum = new Intl.DateTimeFormat(`${locale}-BE`, {
    day: '2-digit', month: '2-digit', year: 'numeric', timeZone: timezone,
  })

  return (
    <div className="divide-y divide-[var(--line)]">
      {tournaments.map((x) => (
        <div
          key={x.id}
          className="flex flex-col gap-2 py-3 first:pt-0 sm:flex-row sm:items-center sm:justify-between sm:gap-4"
        >
          <div className="min-w-0">
            <p className="truncate text-sm font-medium">{x.name}</p>
            <p className="tnum mt-0.5 text-xs text-[var(--text-faint)]">
              {datum.format(new Date(x.scheduled_at))}
              {' · '}
              {t(`status.${x.status}` as Parameters<T>[0])}
              {' · '}
              {formatMoney(x.buyin_cents + x.fee_cents, currency)}
              {x.players > 0 && (
                <> · {t('settings.assignEntries').replace('{n}', String(x.players))}</>
              )}
            </p>
          </div>
          <input type="hidden" name={`was_for_${x.id}`} value={x.season_id ?? ''} />
          <select
            name={`season_for_${x.id}`}
            defaultValue={x.season_id ?? ''}
            className={`${inputClass} sm:w-56`}
          >
            <option value="">{t('settings.assignNone')}</option>
            {seasons.map((s) => (
              <option key={s.id} value={s.id}>{s.name}</option>
            ))}
          </select>
        </div>
      ))}
    </div>
  )
}
