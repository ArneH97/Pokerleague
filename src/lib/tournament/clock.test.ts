import { test } from 'node:test'
import assert from 'node:assert/strict'
import {
  type BlindLevel, type ClockState,
  resolveClock, start, pause, resume, stop, nextLevel, prevLevel,
  adjustTime, formatDuration, formatBlinds, averageStack, breakLabel,
} from './clock'

const T0 = Date.parse('2026-09-06T20:00:00.000Z')
const iso = (ms: number) => new Date(ms).toISOString()

const levels: BlindLevel[] = [
  { idx: 0, isBreak: false, label: null, smallBlind: 25,  bigBlind: 50,  ante: 0,  durationS: 1200 },
  { idx: 1, isBreak: false, label: null, smallBlind: 50,  bigBlind: 100, ante: 0,  durationS: 1200 },
  { idx: 2, isBreak: true,  label: 'Pauze', smallBlind: 0, bigBlind: 0,  ante: 0,  durationS: 600  },
  { idx: 3, isBreak: false, label: null, smallBlind: 100, bigBlind: 200, ante: 25, durationS: 1200 },
]

const running = (levelIdx = 0, startedMs = T0, elapsed = 0): ClockState => ({
  status: 'running', levelIdx, levelStartedAt: iso(startedMs), levelElapsedMs: elapsed,
})

test('gestopte klok telt niet af', () => {
  const s: ClockState = { status: 'stopped', levelIdx: 0, levelStartedAt: null, levelElapsedMs: 0 }
  const a = resolveClock(s, levels, T0)
  const b = resolveClock(s, levels, T0 + 60_000)
  assert.equal(a.remainingMs, b.remainingMs)
  assert.equal(a.remainingMs, 1_200_000)
})

test('lopende klok telt af tegen servertijd', () => {
  const r = resolveClock(running(), levels, T0 + 300_000)
  assert.equal(r.remainingMs, 900_000)
  assert.equal(r.levelIdx, 0)
  assert.equal(r.rolledOver, 0)
})

test('pauzeren bevriest de resterende tijd', () => {
  const paused = pause(running(), levels, T0 + 500_000)
  assert.equal(paused.status, 'paused')
  assert.equal(paused.levelElapsedMs, 500_000)

  // Tien minuten later moet er nog steeds evenveel op de klok staan.
  const later = resolveClock(paused, levels, T0 + 1_100_000)
  assert.equal(later.remainingMs, 700_000)
})

test('hervatten pakt de opgebouwde tijd weer op', () => {
  const paused = pause(running(), levels, T0 + 500_000)
  const resumed = resume(paused, iso(T0 + 900_000))
  const r = resolveClock(resumed, levels, T0 + 1_000_000)
  // 500s opgebouwd + 100s sinds hervatten = 600s verstreken van 1200s.
  assert.equal(r.remainingMs, 600_000)
})

test('klok rolt door verlopen levels als niemand doorklikt', () => {
  // Ruim 45 minuten later: level 0 (20m) en level 1 (20m) zijn voorbij,
  // we zitten 5 minuten in de pauze van 10 minuten.
  const r = resolveClock(running(), levels, T0 + 45 * 60_000)
  assert.equal(r.levelIdx, 2)
  assert.equal(r.level?.isBreak, true)
  assert.equal(r.remainingMs, 5 * 60_000)
  assert.equal(r.rolledOver, 2)
})

test('klok blijft staan op het einde van de structuur', () => {
  const r = resolveClock(running(), levels, T0 + 10 * 3600_000)
  assert.equal(r.finished, true)
  assert.equal(r.remainingMs, 0)
  assert.equal(r.levelIdx, 3)
})

test('gepauzeerde klok schuift niet op van het wachten', () => {
  // Dit is waar het om gaat bij een pauze: hoe lang de zaal ook stilligt, er
  // gaat geen level voorbij. De opgebouwde tijd staat stil, dus de stand ook.
  const paused: ClockState = {
    status: 'paused', levelIdx: 0, levelStartedAt: null, levelElapsedMs: 300_000,
  }
  const kort = resolveClock(paused, levels, T0)
  const uren = resolveClock(paused, levels, T0 + 10 * 3600_000)
  assert.equal(uren.levelIdx, kort.levelIdx)
  assert.equal(uren.remainingMs, kort.remainingMs)
  assert.equal(uren.rolledOver, 0)
})

test('gepauzeerde klok met te veel geboekte tijd toont waar hij werkelijk staat', () => {
  // Zo'n stand kan niet echt bestaan: 45 minuten geboekt op een level van 20.
  // Ze komt uit een oude opgeslagen stand of uit een structuur die achteraf
  // korter is gemaakt. Vroeger sprong het scherm dan op 00:00 en kwam het er
  // niet meer vanaf, want een gepauzeerde klok rolde niet door.
  const scheef: ClockState = {
    status: 'paused', levelIdx: 0, levelStartedAt: null, levelElapsedMs: 45 * 60_000,
  }
  const r = resolveClock(scheef, levels, T0)
  assert.equal(r.levelIdx, 2, 'level 0 en 1 zijn op; we zitten in de pauze')
  assert.equal(r.remainingMs, 5 * 60_000, 'en niet op 00:00')

  // En pauzeren op zo'n stand mag hem niet alsnog op 00:00 vastzetten.
  const opnieuw = pause({ ...scheef, status: 'running', levelStartedAt: iso(T0) }, levels, T0)
  assert.equal(opnieuw.levelIdx, 2)
  assert.equal(resolveClock(opnieuw, levels, T0).remainingMs, 5 * 60_000)
})

test('pauzeren zonder geladen structuur gooit de tijd niet weg', () => {
  // Een hik in het netwerk mag geen tijd kosten. Zonder levels valt er niets
  // uit te rekenen, dus blijft de stand zoals hij was.
  const s = running(1, T0, 400_000)
  const na = pause(s, [], T0 + 100_000)
  assert.equal(na.status, 'paused')
  assert.equal(na.levelIdx, 1, 'het level blijft staan')
  assert.equal(na.levelElapsedMs, 500_000, '400s geboekt + 100s gelopen')
})

test('een minuut eraf duwt netjes over de levelgrens', () => {
  // Nog 30 seconden te gaan, en de floor haalt er een minuut af. Dan hoort de
  // klok in het volgende level te staan met 30 seconden verstreken — niet op
  // 00:00 te blijven hangen.
  const s = running(0, T0, 0)
  const na = adjustTime(s, levels, -60_000, T0 + 1_170_000, iso(T0 + 1_170_000))
  assert.equal(na.levelIdx, 1)
  assert.equal(na.levelElapsedMs, 30_000)
  assert.equal(resolveClock(na, levels, T0 + 1_170_000).remainingMs, 1_170_000)
})

test('volgend en vorig level zetten de teller op nul', () => {
  const next = nextLevel(running(), levels, T0 + 100_000, iso(T0 + 100_000))
  assert.equal(next.levelIdx, 1)
  assert.equal(next.levelElapsedMs, 0)
  assert.equal(resolveClock(next, levels, T0 + 100_000).remainingMs, 1_200_000)

  const back = prevLevel(next, levels, T0 + 100_000, iso(T0 + 100_000))
  assert.equal(back.levelIdx, 0)
})

test('vorig level gaat niet onder nul, volgend niet voorbij het laatste', () => {
  const first: ClockState = { status: 'paused', levelIdx: 0, levelStartedAt: null, levelElapsedMs: 0 }
  assert.equal(prevLevel(first, levels, T0, iso(T0)).levelIdx, 0)

  const last: ClockState = { status: 'paused', levelIdx: 3, levelStartedAt: null, levelElapsedMs: 0 }
  assert.equal(nextLevel(last, levels, T0, iso(T0)).levelIdx, 3)
})

test('doorrollen respecteert het level waar de floor naartoe sprong', () => {
  // Sprong naar level 3, daarna 5 minuten gelopen.
  const jumped = nextLevel(nextLevel(nextLevel(running(), levels, T0, iso(T0)), levels, T0, iso(T0)), levels, T0, iso(T0))
  const r = resolveClock(jumped, levels, T0 + 300_000)
  assert.equal(r.levelIdx, 3)
  assert.equal(r.remainingMs, 900_000)
})

test('tijd bijtellen en aftrekken', () => {
  const plus = adjustTime(running(), levels, 60_000, T0 + 300_000, iso(T0 + 300_000))
  assert.equal(resolveClock(plus, levels, T0 + 300_000).remainingMs, 960_000)

  const minus = adjustTime(running(), levels, -60_000, T0 + 300_000, iso(T0 + 300_000))
  assert.equal(resolveClock(minus, levels, T0 + 300_000).remainingMs, 840_000)

  // Niet verder terug dan het begin van het level.
  const capped = adjustTime(running(), levels, 999_999_999, T0 + 300_000, iso(T0 + 300_000))
  assert.equal(resolveClock(capped, levels, T0 + 300_000).remainingMs, 1_200_000)
})

test('stoppen bewaart de stand', () => {
  const stopped = stop(running(), levels, T0 + 400_000)
  assert.equal(stopped.status, 'stopped')
  assert.equal(stopped.levelElapsedMs, 400_000)
})

test('start begint bovenaan', () => {
  const s = start(iso(T0))
  assert.equal(s.levelIdx, 0)
  assert.equal(s.status, 'running')
  assert.equal(resolveClock(s, levels, T0).remainingMs, 1_200_000)
})

test('lege structuur laat niets ontploffen', () => {
  const r = resolveClock(running(), [], T0 + 100_000)
  assert.equal(r.finished, true)
  assert.equal(r.level, null)
})

test('level van nul seconden veroorzaakt geen oneindige lus', () => {
  const zero: BlindLevel[] = [
    { idx: 0, isBreak: false, label: null, smallBlind: 1, bigBlind: 2, ante: 0, durationS: 0 },
    { idx: 1, isBreak: false, label: null, smallBlind: 2, bigBlind: 4, ante: 0, durationS: 600 },
  ]
  const r = resolveClock(running(), zero, T0 + 1000)
  assert.equal(r.levelIdx, 1)
})

test('ongeldig starttijdstip valt terug op de opgebouwde tijd', () => {
  const broken: ClockState = {
    status: 'running', levelIdx: 0, levelStartedAt: 'geen datum', levelElapsedMs: 120_000,
  }
  assert.equal(resolveClock(broken, levels, T0).remainingMs, 1_080_000)
})

test('elke overgang levert hele milliseconden op, ook bij een gebroken kloktijd', () => {
  // Regressie: de tijdcorrectie tegen de server deelt de rondreistijd door
  // twee en produceerde daardoor halve milliseconden. level_elapsed_ms is een
  // bigint, dus Postgres weigerde de update en de pauzeknop deed niets.
  const fractional = T0 + 134_240.5
  const iso2 = new Date(fractional).toISOString()

  const cases: Record<string, ClockState> = {
    pause: pause(running(), levels, fractional),
    stop: stop(running(), levels, fractional),
    resume: resume(pause(running(), levels, fractional), iso2),
    plusMinuut: adjustTime(running(), levels, 60_000, fractional, iso2),
    minMinuut: adjustTime(running(), levels, -60_000, fractional, iso2),
    halveDelta: adjustTime(running(), levels, 1234.5, fractional, iso2),
    volgend: nextLevel(running(), levels, fractional, iso2),
    vorig: prevLevel(running(1), levels, fractional, iso2),
    start: start(iso2),
  }

  for (const [naam, s] of Object.entries(cases)) {
    assert.ok(
      Number.isInteger(s.levelElapsedMs),
      `${naam} gaf ${s.levelElapsedMs}, dat is geen geheel getal`,
    )
    assert.ok(Number.isInteger(s.levelIdx), `${naam} gaf een gebroken levelIdx`)
    assert.ok(s.levelElapsedMs >= 0, `${naam} gaf een negatieve tijd`)
  }
})

test('gebroken kloktijd verandert niets aan de resterende tijd', () => {
  const a = resolveClock(running(), levels, T0 + 300_000)
  const b = resolveClock(running(), levels, T0 + 300_000.5)
  assert.equal(Math.round(a.remainingMs / 1000), Math.round(b.remainingMs / 1000))
})

test('pauzelabel volgt de taal van de club, eigen tekst blijft staan', () => {
  // Een structuur gemaakt in het Nederlands mag geen "Pauze" tonen op een
  // Engelse klok. Standaardwoorden herkennen we en vervangen we.
  assert.equal(breakLabel('Pauze', 'Break'), 'Break')
  assert.equal(breakLabel('pause', 'Break'), 'Break')
  assert.equal(breakLabel('BREAK', 'Pause'), 'Pause')
  assert.equal(breakLabel('', 'Break'), 'Break')
  assert.equal(breakLabel(null, 'Break'), 'Break')
  assert.equal(breakLabel('   ', 'Break'), 'Break')

  // Een echt eigen label blijft ongemoeid, in welke taal dan ook.
  assert.equal(breakLabel('Rookpauze', 'Break'), 'Rookpauze')
  assert.equal(breakLabel('  Souper  ', 'Break'), 'Souper')
})

test('weergave', () => {
  assert.equal(formatDuration(0), '00:00')
  assert.equal(formatDuration(59_400), '00:59')
  assert.equal(formatDuration(1_200_000), '20:00')
  assert.equal(formatDuration(3_723_000), '1:02:03')
  assert.equal(formatDuration(-5000), '00:00')

  assert.equal(formatBlinds(levels[0]), '25 / 50')
  assert.equal(formatBlinds(levels[3]), '100 / 200 (ante 25)')
  assert.equal(formatBlinds(levels[2]), 'Pauze')
  assert.equal(formatBlinds(null), '—')

  assert.equal(averageStack(210_000, 21), 10_000)
  assert.equal(averageStack(100, 0), 0)
})

test('pauzeren op een verlopen level springt niet alsnog bij het hervatten', () => {
  // De bug: de klok liep door zonder dat er geklikt werd, dus in de database
  // stond nog level 0 met een verstreken tijd van ver voorbij die twintig
  // minuten. Pauzeren bevroor die ruwe tijd, het scherm toonde 00:00 op het
  // oude level, en bij hervatten kwam alles alsnog vrij: een level erbij en
  // de melding "automatisch doorgerold".
  const laat = T0 + 25 * 60_000       // vijf minuten voorbij het einde van level 0
  const paused = pause(running(), levels, laat)

  // Pauzeren zet de stand gelijk met wat er op het scherm hoort te staan.
  assert.equal(paused.levelIdx, 1, 'pauzeren hoort mee te schuiven naar het juiste level')
  assert.equal(resolveClock(paused, levels, laat).remainingMs, 15 * 60_000)
  assert.equal(resolveClock(paused, levels, laat).rolledOver, 0)

  // En een uur later staat er nog precies hetzelfde.
  const later = resolveClock(paused, levels, laat + 3600_000)
  assert.equal(later.levelIdx, 1)
  assert.equal(later.remainingMs, 15 * 60_000)

  // Hervatten verandert niets aan het level en rolt niets door.
  const resumed = resume(paused, iso(laat + 3600_000))
  const na = resolveClock(resumed, levels, laat + 3600_000)
  assert.equal(na.levelIdx, 1, 'hervatten hoort op hetzelfde level te blijven')
  assert.equal(na.rolledOver, 0, 'hervatten mag geen doorrolmelding geven')
  assert.equal(na.remainingMs, 15 * 60_000)
})

test('pauzeren bovenop een levelgrens blijft staan waar het scherm stond', () => {
  // Precies op 00:00 van level 0 pauzeren: het scherm toont dan level 1 met
  // volle tijd, en dat hoort ook bewaard te worden.
  const grens = T0 + 20 * 60_000
  const paused = pause(running(), levels, grens)
  assert.equal(paused.levelIdx, 1)
  assert.equal(paused.levelElapsedMs, 0)
})

test('tijd bijstellen werkt ook als de klok al doorgerold is', () => {
  // Een minuut bijtellen op een klok die al voorbij het level staat hoorde
  // zichtbaar niets te doen, want de tijd werd van een enorm getal afgetrokken.
  const laat = T0 + 25 * 60_000
  const plus = adjustTime(running(), levels, 60_000, laat, iso(laat))
  assert.equal(plus.levelIdx, 1)
  assert.equal(resolveClock(plus, levels, laat).remainingMs, 16 * 60_000)
})

test('stoppen zet de stand ook gelijk', () => {
  const laat = T0 + 25 * 60_000
  const stopped = stop(running(), levels, laat)
  assert.equal(stopped.levelIdx, 1)
  assert.equal(stopped.levelElapsedMs, 5 * 60_000)
})
