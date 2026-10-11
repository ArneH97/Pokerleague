import assert from 'node:assert/strict'
import { test } from 'node:test'
import { pointsFor, stakeWeight, type PointsRules } from './points'

/**
 * Deze getallen staan ook in buyin_test.sql en inzet_test.sql, waar ze tegen
 * de échte `calc_points` aangehouden worden. Lopen de twee uit elkaar, dan
 * valt hier of daar een test om — en dat is precies waarvoor ze er zijn: een
 * scherm dat een andere formule uitlegt dan de database rekent, is erger dan
 * een scherm zonder uitleg.
 */
const league: PointsRules = {
  method: 'sqrt_ratio',
  multiplier: 10,
  exponent: 0.75,
  buyin_ref: 30,
  buyin_weight: 0.5,
  bonus_entry: 3,
  bonus_per_ko: 0,
  count_best_n: 15,
  min_tournaments: 10,
}

const zonderInzet: PointsRules = { ...league, buyin_ref: null, bonus_entry: 0 }

test('zonder deelnamebonus geeft de wortelformule dezelfde getallen als de database', () => {
  const r = { ...zonderInzet }
  assert.equal(pointsFor(r, 1, 20, 0), 45)
  assert.equal(pointsFor(r, 20, 20, 0), 5)
})

test('de inzet weegt mee met het ijkpunt als nulpunt', () => {
  const r = { ...league, bonus_entry: 0 }
  assert.equal(pointsFor(r, 1, 20, 1500), 32)
  assert.equal(pointsFor(r, 1, 20, 3000), 45)
  assert.equal(pointsFor(r, 1, 20, 5000), 58)
  assert.equal(pointsFor(r, 1, 20, 10000), 82)
})

test('de weging blijft tussen een half en twee', () => {
  assert.equal(stakeWeight(league, 3000), 1)
  assert.equal(stakeWeight(league, 50000), 2)
  assert.equal(stakeWeight(league, 200), 0.5)
})

test('zonder ijkpunt weegt de inzet niet mee', () => {
  assert.equal(stakeWeight(zonderInzet, 5000), null)
  assert.equal(pointsFor(zonderInzet, 1, 20, 5000), pointsFor(zonderInzet, 1, 20, 3000))
})

test('de deelnamebonus komt er bovenop', () => {
  assert.equal(pointsFor(league, 20, 20, 3000), 5 + 3)
})

test('The Hunt: twintig pot plus twintig bounty telt als veertig euro', () => {
  // Dertien spelers, winnaar. Hetzelfde getal als in inzet_test.sql.
  assert.equal(pointsFor(league, 1, 13, 4000), 45)
  // En met alleen de pot zou het 32 geweest zijn — de fout uit migratie 0065.
  assert.equal(pointsFor(league, 1, 13, 2000), 32)
})

test('een onmogelijke exponent wordt naar iets speelbaars getrokken', () => {
  const steil = { ...league, exponent: 9 }
  const maximaal = { ...league, exponent: 1.5 }
  assert.equal(pointsFor(steil, 2, 20, 3000), pointsFor(maximaal, 2, 20, 3000))
})

test('andere formules krijgen geen verzonnen voorbeeld', () => {
  assert.equal(pointsFor({ ...league, method: 'fixed_table' }, 1, 20, 3000), null)
  assert.equal(pointsFor({ ...league, method: 'linear' }, 1, 20, 3000), null)
})
