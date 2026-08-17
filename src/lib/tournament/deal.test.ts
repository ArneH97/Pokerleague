import { test } from 'node:test'
import assert from 'node:assert/strict'
import {
  computeDeal, chipChopCents, evenSplitCents, icmEquityCents, distributeCents, ICM_MAX_PLAYERS,
  type DealSeat,
} from './deal'

const sum = (xs: number[]) => xs.reduce((a, b) => a + b, 0)
const seats = (...pairs: [string, number][]): DealSeat[] =>
  pairs.map(([name, chips], i) => ({ id: `p${i}`, name, chips }))

// ---------------------------------------------------------------------------
// Afronding
// ---------------------------------------------------------------------------

test('verdeling telt altijd exact op tot het totaal', () => {
  for (const total of [10_000, 33_333, 1, 7, 999_999]) {
    for (const weights of [[1, 1, 1], [7, 3], [5, 5, 5, 5, 5, 5, 5], [1, 0, 0]]) {
      const out = distributeCents(total, weights)
      assert.equal(sum(out), total, `${total} over ${weights.join('/')}`)
      assert.ok(out.every((x) => x >= 0), 'geen negatieve bedragen')
    }
  }
})

test('gelijke gewichten geven een gelijke verdeling, restcenten netjes verdeeld', () => {
  const out = distributeCents(1000, [1, 1, 1])
  assert.equal(sum(out), 1000)
  assert.deepEqual(out.toSorted((a, b) => a - b), [333, 333, 334])
})

test('gewicht nul levert niets op', () => {
  const out = distributeCents(1000, [1, 0])
  assert.equal(out[1], 0)
  assert.equal(out[0], 1000)
})

// ---------------------------------------------------------------------------
// ICM
// ---------------------------------------------------------------------------

test('ICM bij twee gelijke stapels is een gelijke verdeling', () => {
  const ev = icmEquityCents([5000, 5000], [7000, 3000])!
  assert.ok(Math.abs(ev[0] - 5000) < 0.01)
  assert.ok(Math.abs(ev[1] - 5000) < 0.01)
})

test('ICM bij twee spelers volgt de handberekening', () => {
  // 75% kans op plaats 1, 25% op plaats 2.
  // 0.75 * 70 + 0.25 * 30 = 60
  const ev = icmEquityCents([7500, 2500], [7000, 3000])!
  assert.ok(Math.abs(ev[0] - 6000) < 0.01, `verwacht 6000, kreeg ${ev[0]}`)
  assert.ok(Math.abs(ev[1] - 4000) < 0.01, `verwacht 4000, kreeg ${ev[1]}`)
})

test('ICM bij drie spelers volgt de handberekening', () => {
  // Stapels 50/30/20, prijzen 50/30/20.
  // P(A eerste) = 0.5. P(A tweede) = P(B eerst)*A/(A+C) + P(C eerst)*A/(A+B)
  //             = 0.3*(50/70) + 0.2*(50/80) = 0.214285... + 0.125 = 0.339285...
  // P(A derde)  = 1 - 0.5 - 0.339285... = 0.160714...
  // EV(A) = 0.5*50 + 0.339285*30 + 0.160714*20 = 25 + 10.17857 + 3.21428 = 38.39285
  const ev = icmEquityCents([50, 30, 20], [5000, 3000, 2000])!
  assert.ok(Math.abs(ev[0] - 3839.285) < 0.5, `verwacht ~3839, kreeg ${ev[0]}`)
  assert.ok(Math.abs(sum(ev) - 10000) < 0.01, 'som moet de pot zijn')
})

test('ICM geeft de chipleider minder dan zijn chipaandeel', () => {
  // Dit is de kern van ICM: chips zetten niet lineair om in geld.
  const chips = [7000, 2000, 1000]
  const prizes = [5000, 3000, 2000]
  const ev = icmEquityCents(chips, prizes)!
  const pool = sum(prizes)
  const chipShare = (chips[0] / sum(chips)) * pool

  assert.ok(ev[0] < chipShare, `ICM ${ev[0]} zou onder chipaandeel ${chipShare} moeten liggen`)
  assert.ok(ev[2] > (chips[2] / sum(chips)) * pool, 'kleinste stapel krijgt juist meer')
})

test('ICM is monotoon: meer chips is nooit minder geld', () => {
  const ev = icmEquityCents([9000, 5000, 3000, 2000, 1000], [4000, 2500, 1500, 1200, 800])!
  for (let i = 1; i < ev.length; i++) {
    assert.ok(ev[i - 1] >= ev[i], `speler ${i - 1} heeft meer chips maar minder equity`)
  }
})

test('ICM telt op tot de volledige pot, ook bij scheve stapels', () => {
  const prizes = [4000, 2500, 1500, 1200, 800]
  for (const chips of [
    [1, 1, 1, 1, 1],
    [100000, 1, 1, 1, 1],
    [30000, 25000, 20000, 15000, 10000],
  ]) {
    const ev = icmEquityCents(chips, prizes)!
    assert.ok(Math.abs(sum(ev) - sum(prizes)) < 0.01, `som klopt niet voor ${chips.join('/')}`)
  }
})

test('ICM met minder prijzen dan spelers verdeelt alleen de prijzen', () => {
  const ev = icmEquityCents([40, 30, 20, 10], [7000, 3000])!
  assert.ok(Math.abs(sum(ev) - 10000) < 0.01)
})

test('ICM weigert boven het maximum aantal spelers', () => {
  const many = new Array(ICM_MAX_PLAYERS + 1).fill(1000)
  assert.equal(icmEquityCents(many, [1000]), null)
})

test('ICM blijft snel bij een volle finaletafel', () => {
  const chips = [30000, 25000, 20000, 18000, 15000, 12000, 9000, 6000, 3000]
  const prizes = [30000, 20000, 14000, 10000, 8000, 6000, 5000, 4000, 3000]
  const started = process.hrtime.bigint()
  const ev = icmEquityCents(chips, prizes)!
  const ms = Number(process.hrtime.bigint() - started) / 1e6
  assert.ok(Math.abs(sum(ev) - sum(prizes)) < 0.01)
  assert.ok(ms < 500, `duurde ${ms.toFixed(0)} ms, dat is te traag voor aan tafel`)
})

// ---------------------------------------------------------------------------
// Chipchop
// ---------------------------------------------------------------------------

test('chipchop garandeert iedereen minstens de laagste nog te winnen prijs', () => {
  const prizes = [5000, 3000, 2000]
  const out = chipChopCents([9000, 500, 500], prizes)
  assert.equal(sum(out), sum(prizes))
  assert.ok(out.every((x) => x >= 2000), `iedereen minstens 2000: ${out.join('/')}`)
})

test('chipchop geeft de chipleider meer dan ICM', () => {
  // Het klassieke verschil tussen de twee methodes.
  const chips = [7000, 2000, 1000]
  const prizes = [5000, 3000, 2000]
  const chop = chipChopCents(chips, prizes)
  const icm = icmEquityCents(chips, prizes)!
  assert.ok(chop[0] > icm[0], `chop ${chop[0]} zou boven ICM ${icm[0]} moeten liggen`)
})

test('chipchop bij gelijke stapels is een gelijke verdeling', () => {
  const out = chipChopCents([1000, 1000], [7000, 3000])
  assert.deepEqual(out, [5000, 5000])
})

test('chipchop met meer spelers dan prijzen verdeelt puur naar chips', () => {
  const out = chipChopCents([60, 30, 10], [8000, 2000])
  assert.equal(sum(out), 10000)
  assert.ok(out[0] > out[1] && out[1] > out[2])
})

// ---------------------------------------------------------------------------
// Samengesteld
// ---------------------------------------------------------------------------

test('computeDeal levert beide methodes met exact kloppende sommen', () => {
  const result = computeDeal(
    seats(['Jan', 42000], ['Sofie', 31000], ['Tom', 18000], ['Els', 9000]),
    [40000, 25000, 15000, 12000],
  )

  assert.equal(result.poolCents, 92000)
  assert.equal(result.floorCents, 12000)
  assert.ok(result.icmAvailable)
  assert.equal(sum(result.shares.map((s) => s.icmCents!)), 92000)
  assert.equal(sum(result.shares.map((s) => s.chopCents)), 92000)
  assert.ok(result.shares.every((s) => s.chopCents >= 12000), 'ondergrens gerespecteerd')
})

test('computeDeal met één speler over geeft hem alles', () => {
  const result = computeDeal(seats(['Jan', 100000]), [40000, 25000])
  assert.equal(result.poolCents, 40000)
  assert.equal(result.shares[0].icmCents, 40000)
  assert.equal(result.shares[0].chopCents, 40000)
})

test('computeDeal met een lege stapel laat die speler niet met de pot lopen', () => {
  const result = computeDeal(seats(['Jan', 50000], ['Leeg', 0]), [7000, 3000])
  assert.equal(sum(result.shares.map((s) => s.chopCents)), 10000)
  // Zonder chips nog altijd de gegarandeerde ondergrens.
  assert.equal(result.shares[1].chopCents, 3000)
  assert.ok(result.shares[0].icmCents! > result.shares[1].icmCents!)
})

test('computeDeal boven het ICM-maximum toont alleen chipchop', () => {
  const many = Array.from({ length: ICM_MAX_PLAYERS + 1 },
    (_, i) => ['Speler ' + i, 1000] as [string, number])
  const result = computeDeal(seats(...many), [5000, 3000, 2000])
  assert.equal(result.icmAvailable, false)
  assert.ok(result.icmUnavailableReason)
  assert.equal(sum(result.shares.map((s) => s.chopCents)), 10000)
})

test('even split verdeelt de pot gelijk, in hele euro’s', () => {
  // 10.000 cent over drie spelers gaat niet gelijk op. Omdat er in stappen
  // van een euro verdeeld wordt krijgt één speler er één euro meer, en de
  // som blijft exact kloppen. Op de cent verdelen zou € 33,33 opleveren, en
  // dat is precies wat we niet willen aan de kassa.
  const even = evenSplitCents(3, [5000, 3000, 2000])
  assert.equal(even.reduce((a, b) => a + b, 0), 10000)
  assert.ok(Math.max(...even) - Math.min(...even) <= 100)
  assert.ok(even.every((x) => x % 100 === 0), 'even split hoort rond te zijn')

  // Meer spelers dan betaalde plaatsen: alleen wat er te verdelen valt.
  const four = evenSplitCents(4, [5000, 3000])
  assert.equal(four.reduce((a, b) => a + b, 0), 8000)
  assert.equal(four.length, 4)

  assert.deepEqual(evenSplitCents(0, [1000]), [])
})

test('computeDeal geeft de drie methodes naast elkaar', () => {
  const seats = [
    { id: 'a', name: 'A', chips: 60000 },
    { id: 'b', name: 'B', chips: 25000 },
    { id: 'c', name: 'C', chips: 15000 },
  ]
  const r = computeDeal(seats, [5000, 3000, 2000])

  for (const key of ['icmCents', 'chopCents', 'evenCents'] as const) {
    const total = r.shares.reduce((n, s) => n + (s[key] ?? 0), 0)
    assert.equal(total, r.poolCents, `${key} telt niet op tot de pot`)
  }

  // De chipleader vaart het best bij chipchop, het slechtst bij even split.
  const a = r.shares[0]
  assert.ok(a.chopCents > a.evenCents, 'chipchop hoort de grote stapel te bevoordelen')
  assert.ok((a.icmCents ?? 0) < a.chopCents, 'ICM hoort onder chipchop te liggen')
  assert.ok((a.icmCents ?? 0) > a.evenCents, 'ICM hoort boven de gelijke verdeling te liggen')
})

test('elke verdeling komt uit op hele euro’s', () => {
  // Een pot die niet netjes deelbaar is: 3 spelers, 10.000 cent. Zonder
  // afronding zou dat 3333,33 per persoon worden — precies het soort bedrag
  // waar je aan de kassa niet mee thuiskomt.
  const seats = [
    { id: 'a', name: 'A', chips: 61234 },
    { id: 'b', name: 'B', chips: 24567 },
    { id: 'c', name: 'C', chips: 14199 },
  ]
  const prizes = [5000, 3000, 2000]
  const r = computeDeal(seats, prizes)

  for (const s of r.shares) {
    assert.equal((s.icmCents ?? 0) % 100, 0, `ICM van ${s.name} heeft centen`)
    assert.equal(s.chopCents % 100, 0, `chipchop van ${s.name} heeft centen`)
    assert.equal(s.evenCents % 100, 0, `even split van ${s.name} heeft centen`)
  }

  // En de som blijft exact de pot, ondanks het afronden.
  for (const key of ['icmCents', 'chopCents', 'evenCents'] as const) {
    const total = r.shares.reduce((n, s) => n + (s[key] ?? 0), 0)
    assert.equal(total, r.poolCents, `${key} telt niet meer op tot de pot`)
  }
})

test('een pot met centen erin verliest die centen niet', () => {
  // Buy-in van € 2,50: dan is de pot zelf geen rond bedrag. Het restje moet
  // ergens heen, en dat is de grootste winnaar — nooit verdwijnen.
  const out = distributeCents(1250, [3, 1], 100)
  assert.equal(out.reduce((a, b) => a + b, 0), 1250)
})
