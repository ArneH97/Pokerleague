/**
 * Verdelingen aan de finaletafel: ICM en chipchop.
 *
 * De twee methodes geven bewust verschillende antwoorden, en dat verschil is
 * het punt. Chipchop verdeelt naar rato van de chips; ICM houdt er rekening
 * mee dat chips in een tornooi niet lineair in geld omzetten — de chipleider
 * kan zijn stapel niet volledig verzilveren, want hij kan maar één keer
 * eerste worden. ICM geeft de leider daarom minder dan chipchop.
 *
 * Door beide te tonen ziet de tafel het verschil en kiest ze zelf, in plaats
 * van dat de software een methode oplegt waar iemand zich in benadeeld voelt.
 *
 * Alle bedragen zijn hele centen. Elke verdeling telt exact op tot de
 * resterende pot — geen verdwenen cent, want de kas moet 's avonds kloppen.
 */

/** Boven dit aantal spelers wordt exacte ICM onbetaalbaar (2^n deelverzamelingen). */
export const ICM_MAX_PLAYERS = 16

export interface DealSeat {
  /** Verwijzing naar tournament_players.id */
  id: string
  name: string
  chips: number
}

export interface DealShare {
  id: string
  name: string
  chips: number
  chipShare: number
  icmCents: number | null
  chopCents: number
}

export interface DealResult {
  shares: DealShare[]
  poolCents: number
  /** Wat de eerstvolgende afvaller zou krijgen; ondergrens bij chipchop. */
  floorCents: number
  icmAvailable: boolean
  icmUnavailableReason: string | null
}

const sum = (xs: number[]) => xs.reduce((a, b) => a + b, 0)

/**
 * Verdeelt een pot over gehele centen volgens gegeven verhoudingen, zodat de
 * som exact klopt. Gebruikt de grootste-rest-methode: eerst iedereen naar
 * beneden afgerond, daarna gaan de overgebleven centen naar wie het grootste
 * stuk is kwijtgeraakt. Eerlijker dan alles bij de chipleider gooien.
 */
export function distributeCents(total: number, weights: number[]): number[] {
  const n = weights.length
  if (n === 0) return []
  if (total <= 0) return new Array(n).fill(0)

  const weightSum = sum(weights)
  if (weightSum <= 0) {
    // Geen zinnige verhouding: gelijk verdelen.
    const base = Math.floor(total / n)
    const out = new Array(n).fill(base)
    for (let i = 0; i < total - base * n; i++) out[i] += 1
    return out
  }

  const exact = weights.map((w) => (total * w) / weightSum)
  const out = exact.map((x) => Math.floor(x))
  let left = total - sum(out)

  const order = exact
    .map((x, i) => ({ i, frac: x - Math.floor(x) }))
    .sort((a, b) => b.frac - a.frac)

  for (let k = 0; left > 0; k++, left--) {
    out[order[k % n].i] += 1
  }
  return out
}

/**
 * ICM volgens Malmuth-Harville.
 *
 * Berekent per speler de kans om op elke plaats te eindigen, met als aanname
 * dat de kans om als volgende te winnen evenredig is met je stapel. De
 * verwachte opbrengst is die kansverdeling maal de prijzenstructuur.
 *
 * Uitgevoerd als dynamisch programma over deelverzamelingen: p[S] is de kans
 * dat precies de spelers in S de bovenste |S| plaatsen bezetten. Dat is
 * O(2^n · n) in plaats van de O(n!) van de naïeve recursie.
 *
 * Geeft null terug boven ICM_MAX_PLAYERS spelers.
 */
export function icmEquityCents(chips: number[], prizes: number[]): number[] | null {
  const n = chips.length
  if (n === 0) return []
  if (n > ICM_MAX_PLAYERS) return null

  const total = sum(chips)
  if (total <= 0) return null

  const depth = Math.min(prizes.length, n)
  if (depth === 0) return new Array(n).fill(0)

  const size = 1 << n
  const prob = new Float64Array(size)
  const chipsLeft = new Float64Array(size)
  prob[0] = 1
  chipsLeft[0] = total

  const ev = new Array<number>(n).fill(0)
  const popcount = (x: number) => {
    let c = 0
    while (x) { x &= x - 1; c++ }
    return c
  }

  for (let s = 0; s < size; s++) {
    const p = prob[s]
    if (p === 0) continue

    const placed = popcount(s)
    if (placed >= depth) continue

    const remaining = chipsLeft[s]
    if (remaining <= 0) continue

    for (let i = 0; i < n; i++) {
      const bit = 1 << i
      if (s & bit) continue

      const share = chips[i] / remaining
      if (share === 0) continue

      const step = p * share
      // Speler i wordt nummer (placed + 1).
      ev[i] += step * prizes[placed]

      const next = s | bit
      prob[next] += step
      chipsLeft[next] = remaining - chips[i]
    }
  }

  return ev
}

/**
 * Chipchop met gegarandeerde ondergrens.
 *
 * Iedereen krijgt eerst het bedrag van de laagste nog te verdelen plaats —
 * niemand aan een dealtafel zou akkoord gaan met minder dan wat hij krijgt
 * door gewoon als volgende te sneuvelen. Wat overblijft gaat naar rato van
 * de stapels.
 */
export function chipChopCents(chips: number[], prizes: number[]): number[] {
  const n = chips.length
  if (n === 0) return []

  const payable = prizes.slice(0, Math.min(n, prizes.length))
  const pool = sum(payable)
  if (pool <= 0) return new Array(n).fill(0)

  // Zijn er meer spelers dan betaalde plaatsen, dan valt er niets te
  // garanderen: sommigen zouden zonder deal met lege handen eindigen.
  const floorCents = n <= prizes.length ? payable[payable.length - 1] : 0

  const guaranteed = floorCents * n
  const remainder = pool - guaranteed

  if (remainder <= 0) {
    return distributeCents(pool, chips)
  }

  const extra = distributeCents(remainder, chips)
  return extra.map((x) => x + floorCents)
}

/**
 * Rekent beide methodes door voor de spelers die nog aan tafel zitten.
 *
 * `prizes` zijn de bedragen voor de plaatsen die nog te vergeven zijn, van
 * hoog naar laag — dus bij vier spelers over en een structuur die vijf
 * plaatsen betaalt, geef je de bedragen voor plaats 1 tot en met 4.
 */
export function computeDeal(seats: DealSeat[], prizes: number[]): DealResult {
  const chips = seats.map((s) => Math.max(0, Math.round(s.chips)))
  const totalChips = sum(chips)
  const payable = prizes.slice(0, Math.min(seats.length, prizes.length))
  const poolCents = sum(payable)

  const rawIcm = icmEquityCents(chips, prizes)
  const icm = rawIcm ? distributeCents(poolCents, rawIcm) : null
  const chop = chipChopCents(chips, prizes)

  return {
    poolCents,
    floorCents: seats.length <= prizes.length && payable.length > 0
      ? payable[payable.length - 1]
      : 0,
    icmAvailable: icm !== null,
    icmUnavailableReason:
      icm === null
        ? seats.length > ICM_MAX_PLAYERS
          ? `ICM wordt pas berekend vanaf ${ICM_MAX_PLAYERS} spelers of minder.`
          : 'ICM kan niet berekend worden met deze chipstanden.'
        : null,
    shares: seats.map((s, i) => ({
      id: s.id,
      name: s.name,
      chips: chips[i],
      chipShare: totalChips > 0 ? chips[i] / totalChips : 0,
      icmCents: icm ? icm[i] : null,
      chopCents: chop[i],
    })),
  }
}
