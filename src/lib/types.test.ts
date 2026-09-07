import { test } from 'node:test'
import assert from 'node:assert/strict'
import { entryPriceCents, type TournamentRow } from './types'

/**
 * Wat een inkoop kost.
 *
 * Deze getallen moeten exact overeenkomen met wat `floor_rebuy` in de databank
 * boekt (migratie 0050). Loopt dat uit elkaar, dan staat er een prijs op de
 * knop die niet in de kassa terechtkomt — en dat merk je pas bij het tellen na
 * afloop, als er niemand meer is om het aan te vragen.
 */

const basis = {
  buyin_cents: 4000,
  fee_cents: 500,
  bounty_cents: 0,
  bounty_mode: 'none',
  addon_cents: null,
  addon_fee_cents: null,
  rebuy_cents: null,
  rebuy_fee_cents: null,
} satisfies Pick<TournamentRow,
  'buyin_cents' | 'fee_cents' | 'bounty_cents' | 'bounty_mode'
  | 'addon_cents' | 'addon_fee_cents' | 'rebuy_cents' | 'rebuy_fee_cents'>

test('rebuy zonder eigen prijs volgt de inleg, rake inbegrepen', () => {
  const p = entryPriceCents(basis, 'rebuy')
  assert.deepEqual(p, { pot: 4000, fee: 500, bounty: 0, total: 4500 })
})

test('re-entry kost hetzelfde als een rebuy', () => {
  assert.deepEqual(entryPriceCents(basis, 'reentry'), entryPriceCents(basis, 'rebuy'))
})

test('een eigen rebuyprijs wint van de inleg', () => {
  const p = entryPriceCents({ ...basis, rebuy_cents: 3000, rebuy_fee_cents: 0 }, 'rebuy')
  assert.deepEqual(p, { pot: 3000, fee: 0, bounty: 0, total: 3000 })
})

test('zonder eigen rebuyrake geldt die van de inleg', () => {
  const p = entryPriceCents({ ...basis, rebuy_cents: 3000 }, 'rebuy')
  assert.equal(p.fee, 500)
  assert.equal(p.total, 3500)
})

test('addon zonder eigen prijs volgt de inleg maar heeft geen rake', () => {
  const p = entryPriceCents(basis, 'addon')
  assert.deepEqual(p, { pot: 4000, fee: 0, bounty: 0, total: 4000 })
})

test('addon met eigen prijs en eigen rake', () => {
  const p = entryPriceCents({ ...basis, addon_cents: 2000, addon_fee_cents: 200 }, 'addon')
  assert.deepEqual(p, { pot: 2000, fee: 200, bounty: 0, total: 2200 })
})

test('bij een bountyavond komt de bounty erbij op een rebuy', () => {
  const p = entryPriceCents(
    { ...basis, bounty_mode: 'fixed', bounty_cents: 1000 }, 'rebuy')
  assert.deepEqual(p, { pot: 4000, fee: 500, bounty: 1000, total: 5500 })
})

test('een addon draagt nooit een bounty, ook niet op een bountyavond', () => {
  const p = entryPriceCents(
    { ...basis, bounty_mode: 'fixed', bounty_cents: 1000 }, 'addon')
  assert.equal(p.bounty, 0)
  assert.equal(p.total, 4000)
})

test('een rebuyprijs van nul is een prijs en geen ontbrekende waarde', () => {
  // Het verschil tussen `?? ` en `||`: een gratis rebuy hoort gratis te
  // blijven en niet terug te vallen op de inleg.
  const p = entryPriceCents({ ...basis, rebuy_cents: 0, rebuy_fee_cents: 0 }, 'rebuy')
  assert.equal(p.total, 0)
})
