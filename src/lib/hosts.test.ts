import { test } from 'node:test'
import assert from 'node:assert/strict'
import { isPassthroughPath, isPlatformHost, normalizeHost, platformSubdomainSlug } from './hosts'

// De testen draaien zonder .env, dus dit is het domein waar de code op
// terugvalt. Expliciet meegeven zodat de test niet stilletjes iets anders
// meet als die standaard ooit verandert.
process.env.NEXT_PUBLIC_LEAGUE_DOMAIN = 'pokerleague.be'

test('poort en www horen niet bij de naam', () => {
  assert.equal(normalizeHost('App.Cutoff.be:3000'), 'app.cutoff.be')
  assert.equal(normalizeHost('www.pokerleague.be'), 'pokerleague.be')
  assert.equal(normalizeHost(null), '')
})

test('het platform is geen club', () => {
  assert.equal(platformSubdomainSlug('pokerleague.be'), null)
  assert.equal(platformSubdomainSlug('localhost'), null)
  assert.equal(platformSubdomainSlug('pokerleague-abc123.vercel.app'), null)
  assert.ok(isPlatformHost('pokerleague.be'))
})

test('een subdomein van het platform is meteen een club', () => {
  // Dit is het pad waar geen mens iets voor hoeft te doen: één jokerteken in
  // DNS en elke nieuwe club is bereikbaar.
  assert.equal(platformSubdomainSlug('cutoff.pokerleague.be'), 'cutoff')
  assert.equal(platformSubdomainSlug('poker-aalst.pokerleague.be'), 'poker-aalst')
  // En lokaal, zodat je de twee kanten naast elkaar kan openen.
  assert.equal(platformSubdomainSlug('cutoff.localhost'), 'cutoff')
})

test('gereserveerde namen worden nooit een club', () => {
  // Anders wordt een status- of mailadres ooit stilletjes doorgeschreven naar
  // een clubomgeving die niet bestaat.
  for (const naam of ['www', 'api', 'mail', 'admin', 'status']) {
    assert.equal(platformSubdomainSlug(`${naam}.pokerleague.be`), null, naam)
  }
})

test('alleen één laag diep, en alleen geldige tekens', () => {
  assert.equal(platformSubdomainSlug('a.b.pokerleague.be'), null)
  assert.equal(platformSubdomainSlug('-cutoff.pokerleague.be'), null)
  assert.equal(platformSubdomainSlug('cut off.pokerleague.be'), null)
})

test('een eigen clubdomein blijft een opzoeking waard', () => {
  // app.cutoff.be zegt niets over welke club het is; dat staat in de
  // database. Hier hoort dus null uit te komen zodat de opzoeking volgt.
  assert.equal(platformSubdomainSlug('app.cutoff.be'), null)
})

test('paden die nooit doorgeschreven worden', () => {
  assert.ok(isPassthroughPath('/c/cutoff/floor/1'))
  assert.ok(isPassthroughPath('/api/time'))
  assert.ok(isPassthroughPath('/auth/signout'))
  assert.ok(!isPassthroughPath('/klok/1'))
  assert.ok(!isPassthroughPath('/'))
})

test('het platformdomein hangt niet af van een omgevingsvariabele', () => {
  // Staat de variabele verkeerd of helemaal niet, dan blijft
  // cutoff.pokerleague.be gewoon werken. Anders ontdek je die fout pas
  // wanneer een club belt dat zijn adres het niet doet.
  const bewaard = process.env.NEXT_PUBLIC_LEAGUE_DOMAIN
  try {
    delete process.env.NEXT_PUBLIC_LEAGUE_DOMAIN
    assert.equal(platformSubdomainSlug('cutoff.pokerleague.be'), 'cutoff')
    assert.ok(isPlatformHost('pokerleague.be'))

    process.env.NEXT_PUBLIC_LEAGUE_DOMAIN = 'pokerleague-sable.vercel.app'
    assert.equal(platformSubdomainSlug('cutoff.pokerleague.be'), 'cutoff')
  } finally {
    if (bewaard === undefined) delete process.env.NEXT_PUBLIC_LEAGUE_DOMAIN
    else process.env.NEXT_PUBLIC_LEAGUE_DOMAIN = bewaard
  }
})
