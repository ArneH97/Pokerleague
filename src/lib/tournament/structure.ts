/**
 * Hulpstukken voor de blindstructuur-editor.
 *
 * Bewust géén 'use client' bovenaan. Deze functies worden zowel op de server
 * (bij het opbouwen van de beginwaarden) als in de browser gebruikt. Staan ze
 * in een clientmodule, dan krijgt de server enkel een verwijzing terug in
 * plaats van de functie zelf, en dan valt de pagina om.
 */

export interface EditorLevel {
  key: string
  isBreak: boolean
  label: string
  smallBlind: number
  bigBlind: number
  ante: number
  minutes: number
}

let counter = 0

export function makeLevel(p: Partial<EditorLevel> = {}): EditorLevel {
  return {
    // Een expliciete key meegeven wanneer de rij van de server komt: anders
    // tellen server en browser los van elkaar en klopt de hydratie niet.
    key: `l${counter++}`,
    isBreak: false,
    label: '',
    smallBlind: 25,
    bigBlind: 50,
    ante: 0,
    minutes: 20,
    ...p,
  }
}

/** Volgende blindniveau: ongeveer anderhalf keer, afgerond op iets leesbaars. */
export function nextBlinds(bb: number): { sb: number; bb: number } {
  const target = bb * 1.5
  const step = target < 200 ? 25 : target < 1000 ? 50 : target < 5000 ? 500 : 1000
  const rounded = Math.max(bb + step, Math.round(target / step) * step)
  return { sb: Math.round(rounded / 2), bb: rounded }
}

/** Genereert een volledige ladder voor een gewenste speelduur in uren. */
export function generateLadder(hours: number, minutesPerLevel = 20): EditorLevel[] {
  const wanted = Math.max(4, Math.round((hours * 60) / minutesPerLevel))
  const out: EditorLevel[] = []
  let sb = 25
  let bb = 50

  for (let i = 0; i < wanted; i++) {
    out.push(makeLevel({
      smallBlind: sb,
      bigBlind: bb,
      ante: i >= 5 ? bb : 0,
      minutes: minutesPerLevel,
    }))
    if ((i + 1) % 4 === 0 && i + 1 < wanted) {
      out.push(makeLevel({ isBreak: true, label: 'Pauze', minutes: 10 }))
    }
    const n = nextBlinds(bb)
    sb = n.sb
    bb = n.bb
  }
  return out
}
