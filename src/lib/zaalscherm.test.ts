import { test } from 'node:test'
import assert from 'node:assert/strict'
import { esc, veiligeKleur, zaalHtml, type ZaalBord, type ZaalLevel } from './zaalscherm'

/**
 * De zaalpagina bestaat omdat oude tv's de gewone app niet aankunnen. Die
 * reden verdampt zodra er iemand — ik, over een maand — hier een moderne
 * schrijfwijze inzet omdat het korter leest. Deze test is het slot daarop:
 * hij leest de pagina na op alles wat een browser van 2018 niet kent.
 *
 * De ondergrens is Chromium 69, de motor van een Samsung uit 2020. Dat is
 * strenger dan de 94 van een toestel uit 2023, en met opzet: we weten niet
 * welk bouwjaar er in een clubzaal hangt, en het kost hier niets.
 */

const LEVELS: ZaalLevel[] = [
  { idx: 0, is_break: false, label: null, small_blind: 100, big_blind: 200, ante: 200, duration_s: 1200 },
  { idx: 1, is_break: false, label: null, small_blind: 200, big_blind: 400, ante: 400, duration_s: 1200 },
  { idx: 2, is_break: true, label: 'Pauze', small_blind: 0, big_blind: 0, ante: 0, duration_s: 600 },
  { idx: 3, is_break: false, label: null, small_blind: 300, big_blind: 600, ante: 600, duration_s: 1200 },
]

const BORD: ZaalBord = {
  club_name: 'Cutoff Cardroom',
  primary_color: '#c8a15c',
  tournament_id: '22222222-2222-2222-2222-222222222222',
  name: 'Sunday Opening',
  status: 'running',
  clock: 'running',
  level_idx: 1,
  level_started_at: new Date().toISOString(),
  level_elapsed_ms: 0,
  scheduled_at: new Date().toISOString(),
  starting_stack: 40000,
  late_reg_level: 6,
  entries: 13,
  players_left: 9,
  rebuys: 4,
  addons: 1,
  prize_pool_cents: 51000,
  chips_in_play: 680000,
  currency: 'EUR',
  server_now: new Date().toISOString(),
}

function pagina(over: Partial<ZaalBord> = {}): string {
  return zaalHtml({
    sleutel: 'abcdef2345',
    bord: { ...BORD, ...over },
    levels: LEVELS,
    clubNaam: 'Cutoff Cardroom',
  })
}

/**
 * Wat er niet in mag, en vanaf welke Chromium het pas bestaat.
 *
 * Alleen dingen die stilletjes misgaan. Een eigenschap die een oude browser
 * niet kent laat hij vallen — vervelend maar leesbaar. `@layer` is de enige
 * waarbij hij het hele blok overslaat, en dat is precies wat de app op de tv
 * van Cutoff onleesbaar maakte. De rest staat erbij omdat we het ene geval
 * niet van het andere willen moeten onderscheiden.
 */
const VERBODEN: [RegExp, string][] = [
  [/@layer\b/, 'cascade layers (Chromium 99)'],
  [/color-mix\s*\(/, 'color-mix() (111)'],
  [/\boklch\s*\(/, 'oklch() (111)'],
  [/\boklab\s*\(/, 'oklab() (111)'],
  [/@property\b/, '@property (85)'],
  [/@container\b/, 'container queries (105)'],
  [/\d(?:cqw|cqh|cqi|cqb)\b/, 'container query units (105)'],
  [/\d(?:dvh|svh|lvh|dvw|svw|lvw)\b/, 'dynamic viewport units (108)'],
  [/:has\s*\(/, ':has() (105)'],
  [/:where\s*\(/, ':where() (88)'],
  [/\bis\s*\([^)]*\)\s*\{/, ':is() (88)'],
  [/\baspect-ratio\s*:/, 'aspect-ratio (88)'],
  [/\bgap\s*:/, 'gap in flexbox (84)'],
  [/\binset\s*:/, 'inset-shorthand (87)'],
  [/\bbackdrop-filter\s*:/, 'backdrop-filter (76)'],
  // JavaScript dat te nieuw is voor een motor uit 2018.
  [/=>/, 'pijlfuncties'],
  [/`/, 'template literals'],
  [/\?\./, 'optional chaining (80)'],
  [/\?\?/, 'nullish coalescing (80)'],
  [/\bconst\s+[A-Za-z_$]/, 'const'],
  [/\blet\s+[A-Za-z_$]/, 'let'],
  [/\bclass\s+[A-Za-z_$]/, 'class'],
  [/\basync\s+function\b/, 'async'],
  [/\bawait\s+/, 'await'],
  [/\.\.\./, 'spread'],
  [/\bfetch\s*\(/, 'fetch (42, maar XMLHttpRequest is zekerder)'],
]

/**
 * Commentaar telt niet mee.
 *
 * De uitleg in de pagina nóemt de dingen die er niet in mogen — dat is juist
 * waarom ze er staat. Een browser leest commentaar niet, dus kijken we naar
 * wat er werkelijk uitgevoerd wordt. Zowel de CSS als het JavaScript in deze
 * pagina schrijven hun uitleg tussen schuine strepen en sterretjes, dus één
 * patroon volstaat.
 */
function zonderUitleg(html: string): string {
  return html.replace(/\/\*[\s\S]*?\*\//g, ' ')
}

test('de zaalpagina gebruikt niets wat een oude tv niet kent', () => {
  const html = zonderUitleg(pagina())
  const gevonden: string[] = []
  for (const [patroon, naam] of VERBODEN) {
    if (patroon.test(html)) gevonden.push(naam)
  }
  assert.deepEqual(gevonden, [],
    `de zaalpagina bevat dingen die een oude tv niet kent:\n  ${gevonden.join('\n  ')}`)
})

test('de pagina staat er meteen, zonder op de server te wachten', () => {
  const html = pagina()
  // Eerste verf: de cijfers zitten al in de pagina en niet alleen in een
  // tweede verzoek. Een tv die een seconde "laden…" toont, oogt stuk.
  assert.match(html, /Cutoff Cardroom/)
  assert.match(html, /Sunday Opening/)
  assert.match(html, /"level_idx":1/)
  assert.match(html, /"big_blind":400/)
})

test('een tornooinaam met vreemde tekens breekt de pagina niet', () => {
  const html = pagina({ name: '</script><img src=x onerror=alert(1)>' })
  // In de JSON mag geen afsluitende scripttag belanden, anders eindigt het
  // blok daar en staat de rest als tekst op het scherm.
  assert.ok(!html.includes('</script><img'), 'de JSON brak het scriptblok open')
  assert.match(html, /\\u003c\/script/)
})

test('de titel van de pagina is ontsmet', () => {
  const html = zaalHtml({
    sleutel: 'x', bord: null, levels: [], clubNaam: '<b>Club</b>',
  })
  assert.ok(!html.includes('<title><b>'), 'de clubnaam ging ongefilterd de titel in')
  assert.match(html, /&lt;b&gt;Club/)
})

test('esc vangt de vier tekens die ertoe doen', () => {
  assert.equal(esc('a & b'), 'a &amp; b')
  assert.equal(esc('<i>'), '&lt;i&gt;')
  assert.equal(esc('"x"'), '&quot;x&quot;')
})

test('alleen een echte hexkleur komt in de stylesheet', () => {
  assert.equal(veiligeKleur('#c8a15c', '#000'), '#c8a15c')
  assert.equal(veiligeKleur('#FFF', '#000'), '#FFF')
  assert.equal(veiligeKleur(' #c8a15c ', '#000'), '#c8a15c')
  // Dit is waar het om gaat: een kleur komt uit de databank en belandt
  // rechtstreeks in een <style>. Alles wat geen hex is, gaat eruit.
  assert.equal(veiligeKleur('red; } body { display:none', '#000'), '#000')
  assert.equal(veiligeKleur('url(javascript:alert(1))', '#000'), '#000')
  assert.equal(veiligeKleur(null, '#000'), '#000')
  assert.equal(veiligeKleur('', '#000'), '#000')
})

test('zonder tornooi komt er een pagina en geen fout', () => {
  const html = zaalHtml({ sleutel: 'x', bord: null, levels: [], clubNaam: 'Cutoff' })
  assert.match(html, /Geen tornooi bezig/)
  assert.match(html, /"bord":null/)
})
