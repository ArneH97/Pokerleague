import { test } from 'node:test'
import assert from 'node:assert/strict'
import { translator, type Locale } from './dictionaries'

// De bug in het klein: identiteit. Een effect met `t` of `sound` in zijn
// afhankelijkheden draait opnieuw zodra dat ding een nieuw exemplaar is, en
// de zaalklok hertekent elke seconde.
test('translator geeft per taal telkens hetzelfde exemplaar terug', () => {
  for (const l of ['nl', 'fr', 'en'] as Locale[]) {
    assert.equal(translator(l), translator(l), `${l} gaf een nieuwe functie terug`)
  }
  assert.notEqual(translator('nl'), translator('fr'), 'talen mogen niet samenvallen')
})

test('en hij vertaalt nog altijd', () => {
  assert.equal(typeof translator('nl')('common.signIn'), 'string')
  assert.notEqual(translator('nl')('common.signIn'), translator('en')('common.signIn'))
})
