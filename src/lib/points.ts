/**
 * De puntenformule, alleen om te tónen.
 *
 * De echte punten komen altijd uit `calc_points` in de database en worden
 * vastgelegd bij het afsluiten van een avond. Wat hier staat is een kopie om
 * een voorbeeld mee te kunnen uitrekenen — "wie eerste wordt van twintig
 * krijgt 48 punten" — en om de weging van de inzet te kunnen laten zien naast
 * een resultaat.
 *
 * Een kopie van een formule drijft weg van het origineel. Daarom twee dingen:
 * de getallen in `points.test.ts` zijn exact dezelfde die `buyin_test.sql` en
 * `inzet_test.sql` aan de databasekant vastleggen, en de grenzen hieronder
 * staan ook in `club_public_season_rules`, zodat het scherm nooit iets
 * uitlegt wat de database anders doet.
 *
 * Niets hiervan mag ooit ergens bewaard worden.
 */

export interface PointsRules {
  method: string
  multiplier: number
  exponent: number
  /** Het ijkpunt in euro, of null als de inzet niet meeweegt. */
  buyin_ref: number | null
  buyin_weight: number
  bonus_entry: number
  bonus_per_ko: number
  count_best_n: number | null
  min_tournaments: number
}

/** Tussen twee grenzen houden, zoals `least`/`greatest` in calc_points. */
const klem = (v: number, laag: number, hoog: number) => Math.min(hoog, Math.max(laag, v))

/**
 * Hoe zwaar een avond weegt door wat er op het spel stond.
 *
 * 1 betekent: even zwaar als het ijkpunt. Geeft null terug als de club de
 * inzet niet laat meewegen — dan hoort er ook niets over te staan.
 */
export function stakeWeight(rules: PointsRules, stakeCents: number): number | null {
  const ref = rules.buyin_ref ?? 0
  if (ref <= 0 || stakeCents <= 0) return null
  const gewicht = klem(rules.buyin_weight, 0, 1.5)
  return klem(Math.pow(stakeCents / 100 / ref, gewicht), 0.5, 2)
}

/**
 * Wat een plaats oplevert. Null voor de formules waar dit geen zinnig
 * voorbeeld van kan maken — dan toont het scherm er gewoon geen.
 */
export function pointsFor(
  rules: PointsRules,
  place: number,
  entries: number,
  stakeCents: number,
  knockouts = 0,
): number | null {
  if (rules.method !== 'sqrt_ratio') return null
  if (place < 1 || entries < 1) return 0

  const exp = klem(rules.exponent, 0.5, 1.5)
  let pts = (rules.multiplier * Math.sqrt(entries)) / Math.pow(place, exp)

  const weging = stakeWeight(rules, stakeCents)
  if (weging !== null) pts *= weging

  pts += knockouts * rules.bonus_per_ko + rules.bonus_entry
  return Math.round(Math.max(pts, 0))
}
