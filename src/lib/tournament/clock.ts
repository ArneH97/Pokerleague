/**
 * Tornooiklok.
 *
 * De database bewaart géén aftellende teller. Ze bewaart wanneer het huidige
 * level begon te lopen en hoeveel tijd er al opgebouwd was. De resterende tijd
 * is altijd een berekening tegen servertijd.
 *
 * Waarom: een teller die je elke seconde wegschrijft overleeft geen refresh,
 * geen tweede scherm en geen laptop die in slaap valt. Deze aanpak wel — je
 * kan de zaalweergave dichtklappen, heropenen, en hij staat gelijk.
 *
 * Alle functies hier zijn puur: geen Date.now() binnenin, de tijd komt altijd
 * als argument binnen. Dat maakt ze testbaar en voorkomt dat een verkeerd
 * ingestelde laptopklok de blinds beïnvloedt.
 */

export type ClockStatus = 'stopped' | 'running' | 'paused'

export interface BlindLevel {
  idx: number
  isBreak: boolean
  label: string | null
  smallBlind: number
  bigBlind: number
  ante: number
  durationS: number
}

export interface ClockState {
  status: ClockStatus
  levelIdx: number
  /** ISO-tijdstip waarop het huidige level begon te lopen; null als niet lopend. */
  levelStartedAt: string | null
  /** Reeds opgebouwde tijd binnen het huidige level, in ms. */
  levelElapsedMs: number
}

export interface ResolvedClock {
  status: ClockStatus
  /** Het level waar we werkelijk in zitten, na doorrollen van verlopen levels. */
  levelIdx: number
  level: BlindLevel | null
  nextLevel: BlindLevel | null
  remainingMs: number
  elapsedInLevelMs: number
  /** True als de klok voorbij het laatste level is gelopen. */
  finished: boolean
  /** Aantal levels dat is doorgerold sinds de laatst weggeschreven stand. */
  rolledOver: number
}

const clamp = (n: number, min: number) => (n < min ? min : n)

export function levelDurationMs(level: BlindLevel): number {
  return Math.max(0, level.durationS) * 1000
}

/**
 * Ruwe verstreken tijd binnen het opgeslagen level, zonder doorrollen.
 *
 * Altijd afgerond op hele milliseconden. Dat is geen cosmetiek: de kolom
 * level_elapsed_ms is een bigint, en de tijdcorrectie tegen de server levert
 * halve milliseconden op omdat we de rondreistijd door twee delen. Een
 * gebroken getal wordt door Postgres geweigerd, en dan doet de pauzeknop het
 * niet meer.
 */
export function rawElapsedMs(state: ClockState, nowMs: number): number {
  if (state.status !== 'running' || !state.levelStartedAt) {
    return Math.round(clamp(state.levelElapsedMs, 0))
  }
  const startedMs = Date.parse(state.levelStartedAt)
  if (Number.isNaN(startedMs)) return Math.round(clamp(state.levelElapsedMs, 0))
  return Math.round(clamp(state.levelElapsedMs + (nowMs - startedMs), 0))
}

/**
 * Zet de opgeslagen stand om naar wat er nú op het scherm hoort.
 *
 * Rolt automatisch door verlopen levels heen. Dat is het geval dat je op een
 * tornooiavond echt tegenkomt: de floor vergeet door te klikken, of het scherm
 * stond een kwartier uit. De klok loopt gewoon door in plaats van te bevriezen
 * op 00:00.
 */
export function resolveClock(
  state: ClockState,
  levels: BlindLevel[],
  nowMs: number,
): ResolvedClock {
  const sorted = [...levels].sort((a, b) => a.idx - b.idx)

  if (sorted.length === 0) {
    return {
      status: state.status, levelIdx: state.levelIdx, level: null, nextLevel: null,
      remainingMs: 0, elapsedInLevelMs: 0, finished: true, rolledOver: 0,
    }
  }

  let idx = Math.min(Math.max(state.levelIdx, 0), sorted.length - 1)
  let elapsed = rawElapsedMs(state, nowMs)
  let rolled = 0

  if (state.status === 'running') {
    while (idx < sorted.length && elapsed >= levelDurationMs(sorted[idx])) {
      const spent = levelDurationMs(sorted[idx])
      // Een level van 0 seconden zou hier oneindig lussen.
      if (spent === 0) { idx += 1; rolled += 1; break }
      elapsed -= spent
      idx += 1
      rolled += 1
    }
  }

  if (idx >= sorted.length) {
    const last = sorted[sorted.length - 1]
    return {
      status: state.status, levelIdx: sorted.length - 1, level: last, nextLevel: null,
      remainingMs: 0, elapsedInLevelMs: levelDurationMs(last),
      finished: true, rolledOver: rolled,
    }
  }

  const level = sorted[idx]
  const duration = levelDurationMs(level)
  const capped = Math.min(elapsed, duration)

  return {
    status: state.status,
    levelIdx: level.idx,
    level,
    nextLevel: idx + 1 < sorted.length ? sorted[idx + 1] : null,
    remainingMs: clamp(duration - capped, 0),
    elapsedInLevelMs: capped,
    finished: false,
    rolledOver: rolled,
  }
}

// ---------------------------------------------------------------------------
// Overgangen. Elke functie geeft de nieuwe stand terug zoals die in de
// database moet komen — nooit een mutatie van het argument.
// ---------------------------------------------------------------------------

export function start(nowIso: string): ClockState {
  return { status: 'running', levelIdx: 0, levelStartedAt: nowIso, levelElapsedMs: 0 }
}

/**
 * De opgeslagen stand gelijkzetten met wat er op het scherm staat.
 *
 * Dit is de reparatie van een bug die je alleen merkt als je pauzeert. De
 * klok telt door zonder dat er iets weggeschreven wordt, dus na een level dat
 * afliep zonder klik staat er in de database nog altijd het oude level met
 * een verstreken tijd die veel groter is dan dat level lang duurt. Zolang de
 * klok loopt is dat onzichtbaar: resolveClock rolt er netjes doorheen.
 *
 * Pauzeren bevroor die ruwe tijd echter zoals ze was. Een gepauzeerde klok
 * rolt niet door — met opzet, want anders zou een pauze van een uur je drie
 * levels verder zetten — dus je zag ineens 00:00 op het oude level staan. En
 * bij hervatten kwam al die opgespaarde tijd alsnog vrij: een niveau erbij en
 * de melding "level automatisch doorgerold".
 *
 * Vandaar dat pauzeren, stoppen en het bijstellen van de tijd nu eerst
 * gelijkzetten: het level waar de klok wérkelijk in zit, met de verstreken
 * tijd afgetopt op de duur van dat level. Wat je ziet is dan ook wat er
 * bewaard wordt.
 */
export function normalise(state: ClockState, levels: BlindLevel[], nowMs: number): ClockState {
  const resolved = resolveClock(state, levels, nowMs)
  return {
    ...state,
    levelIdx: resolved.levelIdx,
    levelElapsedMs: Math.round(clamp(resolved.elapsedInLevelMs, 0)),
  }
}

export function pause(state: ClockState, levels: BlindLevel[], nowMs: number): ClockState {
  if (state.status !== 'running') return state
  const here = normalise(state, levels, nowMs)
  return {
    ...here,
    status: 'paused',
    levelStartedAt: null,
  }
}

export function resume(state: ClockState, nowIso: string): ClockState {
  if (state.status === 'running') return state
  return { ...state, status: 'running', levelStartedAt: nowIso }
}

export function stop(state: ClockState, levels: BlindLevel[], nowMs: number): ClockState {
  const here = normalise(state, levels, nowMs)
  return {
    status: 'stopped',
    levelIdx: here.levelIdx,
    levelStartedAt: null,
    levelElapsedMs: here.levelElapsedMs,
  }
}

/**
 * Handmatig naar een ander level. De floor gebruikt dit om te corrigeren,
 * dus de teller begint altijd opnieuw op nul voor dat level.
 */
export function gotoLevel(state: ClockState, levelIdx: number, nowIso: string): ClockState {
  return {
    status: state.status,
    levelIdx: Math.max(0, levelIdx),
    levelStartedAt: state.status === 'running' ? nowIso : null,
    levelElapsedMs: 0,
  }
}

export function nextLevel(state: ClockState, levels: BlindLevel[], nowMs: number, nowIso: string): ClockState {
  const resolved = resolveClock(state, levels, nowMs)
  const max = levels.length > 0 ? levels.length - 1 : 0
  return gotoLevel(state, Math.min(resolved.levelIdx + 1, max), nowIso)
}

export function prevLevel(state: ClockState, levels: BlindLevel[], nowMs: number, nowIso: string): ClockState {
  const resolved = resolveClock(state, levels, nowMs)
  return gotoLevel(state, Math.max(resolved.levelIdx - 1, 0), nowIso)
}

/**
 * Tijd bijtellen of aftrekken binnen het huidige level. Positief = meer tijd
 * op de klok. Kan niet voorbij het begin van het level.
 */
export function adjustTime(
  state: ClockState, levels: BlindLevel[], deltaMs: number, nowMs: number, nowIso: string,
): ClockState {
  // Eerst gelijkzetten, anders trek je een minuut af van een tijd die al
  // voorbij het einde van het level ligt en gebeurt er zichtbaar niets.
  const here = normalise(state, levels, nowMs)
  return {
    ...here,
    levelStartedAt: state.status === 'running' ? nowIso : null,
    levelElapsedMs: Math.round(clamp(here.levelElapsedMs - deltaMs, 0)),
  }
}

// ---------------------------------------------------------------------------
// Weergave
// ---------------------------------------------------------------------------

export function formatDuration(ms: number): string {
  const total = Math.max(0, Math.round(ms / 1000))
  const h = Math.floor(total / 3600)
  const m = Math.floor((total % 3600) / 60)
  const s = total % 60
  const mm = String(m).padStart(2, '0')
  const ss = String(s).padStart(2, '0')
  return h > 0 ? `${h}:${mm}:${ss}` : `${mm}:${ss}`
}

/**
 * Standaardwoorden voor een pauze, in de talen die we ondersteunen.
 *
 * Een label als "Pauze" wordt opgeslagen in de taal waarin de structuur is
 * gemaakt, en blijft daarna Nederlands staan op een Engelse klok. Herkennen
 * we het als een gewoon pauzewoord, dan tonen we in plaats daarvan de
 * vertaling. Alleen een écht eigen label — "Rookpauze", "Souper" — blijft
 * staan zoals de club het typte.
 */
const DEFAULT_BREAK_WORDS = new Set(['pauze', 'pause', 'break'])

export function isDefaultBreakLabel(label: string | null | undefined): boolean {
  const v = (label ?? '').trim().toLowerCase()
  return v === '' || DEFAULT_BREAK_WORDS.has(v)
}

/** Het label voor een pauze, met de vertaling als het geen eigen tekst is. */
export function breakLabel(label: string | null | undefined, fallback: string): string {
  return isDefaultBreakLabel(label) ? fallback : (label as string).trim()
}

export function formatBlinds(level: BlindLevel | null): string {
  if (!level) return '—'
  if (level.isBreak) return level.label ?? 'Pauze'
  const base = `${level.smallBlind.toLocaleString('nl-BE')} / ${level.bigBlind.toLocaleString('nl-BE')}`
  return level.ante > 0 ? `${base} (ante ${level.ante.toLocaleString('nl-BE')})` : base
}

/** Gemiddelde stack, de vraag die de floor het vaakst krijgt. */
export function averageStack(totalChips: number, playersLeft: number): number {
  if (playersLeft <= 0) return 0
  return Math.round(totalChips / playersLeft)
}
