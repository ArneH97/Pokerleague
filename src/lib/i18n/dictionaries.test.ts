import { test } from 'node:test'
import assert from 'node:assert/strict'
import { dictionaries, LOCALES, translator } from './dictionaries'
import { dbMessage } from '../dbMessage'

/**
 * Bewaakt dat het product in drie talen blijft bestaan.
 *
 * TypeScript dekt de helft: `fr` en `en` zijn `Record<Key, string>`, dus een
 * ontbrekende sleutel compileert niet. Wat het níét ziet is een sleutel die je
 * erbij zet door de Nederlandse regel te kopiëren en te vergeten vertalen —
 * dan staat er Nederlands in een Frans scherm en klaagt niemand behalve de
 * Waalse floor die het moet lezen.
 *
 * Vandaar deze test. Ze faalt bij elke nieuwe regel die in twee talen
 * hetzelfde is, tenzij die er hieronder als uitzondering bij staat.
 */

/**
 * Wat in drie talen hetzelfde hoort te zijn.
 *
 * Pokerjargon vertaalt niet: aan een Waalse tafel zegt men "small blind", niet
 * "petite blinde". En "+1 min" is in geen enkele taal iets anders.
 */
const ZELFDE = new Set([
  'clock.smallBlind',
  'clock.bigBlind',
  'floor.minusMinute',
  'floor.plusMinute',
  'struct.addLevel',
  'deal.even',
  'points.bonusKo',
  'site.pick.metaTitle',
])

test('elke taal kent elke sleutel', () => {
  const nl = Object.keys(dictionaries.nl).sort()
  for (const locale of LOCALES) {
    assert.deepEqual(Object.keys(dictionaries[locale]).sort(), nl,
      `${locale} heeft niet dezelfde sleutels als het Nederlands`)
  }
})

test('geen enkele zin blijft onvertaald staan', () => {
  const blijft: string[] = []
  for (const locale of ['fr', 'en'] as const) {
    for (const [key, value] of Object.entries(dictionaries.nl)) {
      if (ZELFDE.has(key)) continue
      // Losse woorden mogen toevallig samenvallen ("Club", "Bounty", "OK");
      // een zin van twee woorden of meer niet.
      if (value.trim().split(/\s+/).length < 2) continue
      if (dictionaries[locale][key as keyof typeof dictionaries.nl].trim() === value.trim()) {
        blijft.push(`${locale}: ${key}`)
      }
    }
  }
  assert.deepEqual(blijft, [], `onvertaald gebleven:\n  ${blijft.join('\n  ')}`)
})

test('geen lege vertalingen', () => {
  for (const locale of LOCALES) {
    for (const [key, value] of Object.entries(dictionaries[locale])) {
      assert.ok(value.trim().length > 0, `${locale}.${key} is leeg`)
    }
  }
})

/**
 * De database praat Nederlands. Dat mag, zolang het scherm het omzet naar de
 * taal van wie kijkt — anders staat er midden in een Frans scherm ineens
 * "Geen rechten om spelers toe te voegen".
 */
test('meldingen uit de database komen vertaald op het scherm', () => {
  const fr = translator('fr')

  assert.equal(dbMessage({ message: 'Geen rechten om spelers toe te voegen' }, fr),
    dictionaries.fr['db.noRights'])
  assert.equal(dbMessage({ message: 'new row violates row-level security policy' }, fr),
    dictionaries.fr['db.noRights'])
  assert.equal(dbMessage({ message: 'iets anders', code: '42501' }, fr),
    dictionaries.fr['db.noRights'])
  assert.equal(dbMessage({ message: 'Dit tornooi is al afgelopen' }, fr),
    dictionaries.fr['db.tournamentOver'])
  assert.equal(dbMessage({ message: 'Speler is 16 jaar; minimumleeftijd is 18.' }, fr),
    dictionaries.fr['db.tooYoung'])
  assert.equal(dbMessage({ message: 'Je kan alleen je eigen chipaantal aanpassen' }, fr),
    dictionaries.fr['db.ownChipsOnly'])

  // Wat we niet kennen blijft staan: een onvertaalde melding is vervelend,
  // een verdwenen melding is erger.
  assert.equal(dbMessage({ message: 'connection reset by peer' }, fr), 'connection reset by peer')
  assert.equal(dbMessage({ message: '' }, fr), dictionaries.fr['common.error'])
  assert.equal(dbMessage(null, fr), dictionaries.fr['common.error'])
})
