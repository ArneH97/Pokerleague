import { test } from 'node:test'
import assert from 'node:assert/strict'
import {
  type BlindLevel, type ClockState,
  resolveClock, start, pause, resume, stop, nextLevel, prevLevel,
  adjustTime, formatDuration, formatBlinds, averageStack,
} from './clock.ts'

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
  const paused = pause(running(), T0 + 500_000)
  assert.equal(paused.status, 'paused')
  assert.equal(paused.levelElapsedMs, 500_000)

  // Tien minuten later moet er nog steeds evenveel op de klok staan.
  const later = resolveClock(paused, levels, T0 + 1_100_000)
  assert.equal(later.remainingMs, 700_000)
})

test('hervatten pakt de opgebouwde tijd weer op', () => {
  const paused = pause(running(), T0 + 500_000)
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

test('gepauzeerde klok rolt nooit door', () => {
  const paused: ClockState = {
    status: 'paused', levelIdx: 0, levelStartedAt: null, levelElapsedMs: 5_000_000,
  }
  const r = resolveClock(paused, levels, T0 + 10 * 3600_000)
  assert.equal(r.levelIdx, 0)
  assert.equal(r.rolledOver, 0)
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
  const plus = adjustTime(running(), 60_000, T0 + 300_000, iso(T0 + 300_000))
  assert.equal(resolveClock(plus, levels, T0 + 300_000).remainingMs, 960_000)

  const minus = adjustTime(running(), -60_000, T0 + 300_000, iso(T0 + 300_000))
  assert.equal(resolveClock(minus, levels, T0 + 300_000).remainingMs, 840_000)

  // Niet verder terug dan het begin van het level.
  const capped = adjustTime(running(), 999_999_999, T0 + 300_000, iso(T0 + 300_000))
  assert.equal(resolveClock(capped, levels, T0 + 300_000).remainingMs, 1_200_000)
})

test('stoppen bewaart de stand', () => {
  const stopped = stop(running(), T0 + 400_000)
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
