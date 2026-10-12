'use client'

/**
 * Eén pokertafel, van boven gezien.
 *
 * **Waarom een tafel en geen lijst.** De floor staat in de zaal en kijkt naar
 * mensen, niet naar regels tekst. Vraagt iemand waar hij moet zitten, dan
 * wijst hij met zijn telefoon naar de tafel en zegt "daar". Een lijst van
 * negen regels dwingt hem om stoel 7 te zoeken tussen stoel 6 en 8; een
 * tafel laat hem kijken waar de lege plek zit, net zoals in de zaal.
 *
 * **Het aantal stoelen komt van buiten.** 6-max, 8-max, 9-max: de stoelen
 * verdelen zich vanzelf over de ovaal. Er staat nergens een aanname dat het
 * er negen zijn.
 *
 * **Twee tikken, nooit slepen.** Slepen op een telefoon in een volle zaal is
 * een gok. Tik een speler, tik een stoel. Dat werkt met één hand en met een
 * scherm dat je half ziet.
 *
 * **De maten volgen het aantal stoelen, en dat moest wel.** Met zes stoelen
 * is er ruimte zat; met negen staan de kaartjes bovenaan en onderaan bijna
 * naast elkaar, en dan schoven ze over elkaar heen — precies op de plek waar
 * de floor moet lezen wie er kort staat.
 *
 * De rekensom staat hieronder bij `breedte`: twee buren bovenaan liggen
 * `straal × sin(360/n)` uit elkaar, en breder dan dat mag een kaartje niet
 * zijn. Bij weinig stoelen is de krappe maat de verticale en niet de
 * horizontale, en dan is er geen beperking die telt.
 *
 * De straal is daarnaast zo gekozen dat een kaartje nooit buiten het vlak
 * valt: 50% − 38% − de halve kaartbreedte blijft positief. Dat is geen
 * schoonheid maar noodzaak — valt er een kaartje buiten, dan schuift de hele
 * pagina zijwaarts op een telefoon.
 */

export interface TableSeat {
  seatNo: number
  tournamentPlayerId: string | null
  name: string | null
  chipCount: number | null
}

export function PokerTable({
  seats, pickedId, bigBlind, leaderId, disabled, onSeat, labelFree, placeHere,
}: {
  seats: TableSeat[]
  /** De speler die de floor in de hand heeft; zijn stoel licht op. */
  pickedId: string | null
  /** Om stapels in blinds te tonen. 0 betekent: laat het weg. */
  bigBlind: number
  /** Wie de grootste stapel heeft van het hele veld. */
  leaderId: string | null
  disabled?: boolean
  onSeat: (seatNo: number, tournamentPlayerId: string | null) => void
  labelFree: string
  placeHere: string
}) {
  const n = Math.max(seats.length, 1)

  /**
   * De verhouding van het tafelvlak: breedte gedeeld door hoogte.
   *
   * Een pokertafel is langwerpig. Stond dit vlak vierkant, dan werd de
   * stoelenring een cirkel en zag het eruit als een rond cafétafeltje — en
   * dan klopt ook het beeld niet meer dat de floor in de zaal voor zich ziet.
   *
   * Hoe meer stoelen, hoe minder plat: tien kaartjes op een heel platte ovaal
   * duwen elkaar van de tafel. Zes mag dus langer dan tien.
   */
  const verhouding = n <= 6 ? 1.8 : n <= 8 ? 1.65 : 1.5

  const stoelen = ringPunten(n, verhouding)

  /**
   * Hoe breed een stoelkaartje mag zijn.
   *
   * Niet gegokt maar gemeten: van alle buren die ongeveer even hoog zitten,
   * telt de kleinste horizontale afstand. Breder dan dat en ze schuiven over
   * elkaar — en dat gebeurde ook, bij negen stoelen, precies waar de floor
   * moet lezen wie er kort staat.
   */
  const breedte = Math.min(27, Math.max(15, kleinsteGat(stoelen) * 0.95))

  // Vanaf negen stoelen wordt het krap: dan gaat het stoelnummer van een
  // eigen regel naar vóór de naam, en wordt het kaartje een regel lager.
  const krap = n >= 9

  return (
    <div
      className="relative mx-auto w-full flex-1"
      // Een bovengrens op de breedte, anders wordt de tafel op een laptop een
      // zwembad van twaalfhonderd pixels. Gecentreerd, want dan staat ze op
      // een breed scherm nog steeds middenin de strook.
      style={{
        aspectRatio: String(verhouding),
        minHeight: '12.5rem',
        maxWidth: '34rem',
        // Zodat de letters op de stoelen met de tafel mee kunnen krimpen:
        // `cqw` hieronder is één procent van déze breedte.
        containerType: 'inline-size',
      }}
    >
      {/* De rail: de leren rand waar de spelers hun armen op leggen. Hij maakt
          van een groene vlek een tafel. */}
      <div
        aria-hidden
        className="absolute rounded-[50%]"
        style={{
          inset: '4% 6%',
          background:
            'linear-gradient(165deg, var(--rail-licht) 0%, var(--rail) 48%, #180f0a 100%)',
          boxShadow: '0 18px 40px -18px #000, inset 0 1px 0 rgba(255,225,160,.13)',
        }}
      />
      <div
        aria-hidden
        className="absolute rounded-[50%]"
        style={{
          inset: 'calc(4% + 13px) calc(6% + 13px)',
          background:
            'radial-gradient(ellipse at 50% 30%, var(--felt-licht) 0%, var(--felt) 55%, var(--felt-donker) 100%)',
          boxShadow: 'inset 0 2px 10px rgba(0,0,0,.55), inset 0 0 0 1px rgba(251,191,36,.13)',
        }}
      />
      {/* De bettinglijn, zoals op elk echt tafelblad. */}
      <div
        aria-hidden
        className="absolute rounded-[50%] border"
        style={{
          inset: 'calc(4% + 13px + 14%) calc(6% + 13px + 14%)',
          borderColor: 'rgba(251,191,36,.12)',
        }}
      />

      {seats.map((s, i) => {
        const { x, y } = stoelen[i]
        const leeg = s.tournamentPlayerId === null
        const opgepakt = pickedId !== null && s.tournamentPlayerId === pickedId
        const doel = leeg && pickedId !== null
        const kort = s.chipCount !== null && bigBlind > 0 && s.chipCount < 15 * bigBlind
        const leider = s.tournamentPlayerId !== null && s.tournamentPlayerId === leaderId

        return (
          <button
            key={s.seatNo}
            type="button"
            disabled={disabled}
            onClick={() => onSeat(s.seatNo, s.tournamentPlayerId)}
            style={{ left: `${x}%`, top: `${y}%`, width: `${breedte}%` }}
            className={[
              'absolute -translate-x-1/2 -translate-y-1/2 rounded-xl px-1 text-center',
              krap ? 'pb-1 pt-1' : 'pb-1.5 pt-1',
              'transition active:scale-95 disabled:opacity-40',
              opgepakt
                ? 'border border-[var(--brand)] bg-[color-mix(in_oklab,var(--brand)_18%,transparent)]'
                : leeg
                  ? 'border border-dashed border-[var(--line-strong)] bg-[color-mix(in_oklab,var(--surface)_45%,transparent)]'
                  : 'border bg-[var(--surface-2)] shadow-[0_5px_14px_-8px_#000]',
              !opgepakt && !leeg && leider ? 'border-[var(--gold)]' : '',
              !opgepakt && !leeg && !leider && kort ? 'border-[color-mix(in_oklab,var(--danger)_45%,var(--line))]' : '',
              !opgepakt && !leeg && !leider && !kort ? 'border-[var(--line)]' : '',
              doel ? 'animate-pulse border-[var(--brand)]' : '',
            ].join(' ')}
          >
            {/* Het stoelnummer op een eigen regel zolang daar plaats voor
                is. Vanaf negen stoelen is elke millimeter hoogte er een, en
                dan schuift het nummer vóór de naam. */}
            {!krap && (
              <span
                className="tnum block leading-none text-[var(--text-faint)]"
                style={{ fontSize: 'clamp(0.44rem, 1.9cqw, 0.56rem)' }}
              >
                {s.seatNo}
              </span>
            )}
            <span
              className="mt-0.5 block truncate font-semibold leading-tight"
              style={{ fontSize: 'clamp(0.58rem, 3cqw, 0.74rem)' }}
            >
              {krap && (
                <span className="tnum font-normal text-[var(--text-faint)]">{s.seatNo} </span>
              )}
              {leeg ? (pickedId !== null ? placeHere : labelFree) : korteNaam(s.name ?? '')}
            </span>
            {/* Fiches en blinds op één regel. Het aantal blinds is het getal
                waarin een floor denkt — 9 bb zegt meer dan 7.500 — maar het
                mag geen regel extra kosten: met negen stoelen is elke
                millimeter hoogte het verschil tussen kaartjes die elkaar
                raken en kaartjes die dat niet doen. */}
            <span
              className={`tnum block truncate leading-tight ${
                kort ? 'text-[var(--danger)]' : 'text-[var(--text-muted)]'
              }`}
              style={{ fontSize: 'clamp(0.52rem, 2.5cqw, 0.66rem)' }}
            >
              {s.chipCount !== null ? s.chipCount.toLocaleString('nl-BE') : '—'}
              {!leeg && s.chipCount !== null && bigBlind > 0 && (
                <span className={kort ? '' : 'text-[var(--text-faint)]'}>
                  {' · '}{Math.round(s.chipCount / bigBlind)}bb
                </span>
              )}
            </span>
          </button>
        )
      })}
    </div>
  )
}

/**
 * Waar de stoelen liggen: gelijk verdeeld over de ránd, niet over de hoek.
 *
 * Dit is het verschil tussen een tafel en een taartdiagram. Verdeel je de
 * stoelen over gelijke hoeken, dan kruipen ze op een langwerpige tafel
 * samen bij de twee korte uiteinden en blijven de lange zijden half leeg —
 * precies omgekeerd aan hoe mensen aan een pokertafel zitten, en met negen
 * stoelen schoven de kaartjes daardoor over elkaar.
 *
 * Gelijke afstand over de omtrek lost dat op: de meeste spelers komen langs
 * de twee lange zijden te zitten en één of twee aan elk uiteinde. Dat is ook
 * wat je in de zaal ziet.
 *
 * De omtrek van een ellips heeft geen eenvoudige formule, dus we lopen hem na
 * in kleine stapjes en tellen de lengte op. Zevenhonderd stapjes is ruim
 * genoeg voor een tafel van een paar honderd pixels, en het rekent in een
 * oogwenk.
 *
 * Alles rekent in procenten van de bréédte, ook de hoogte; anders tel je
 * appels bij peren op zodra het vlak niet vierkant is. Op het eind gaat de
 * hoogte door de verhouding terug naar procenten van het vlak zelf.
 */
function ringPunten(n: number, verhouding: number): { x: number; y: number }[] {
  const a = 38
  const b = 37 / verhouding

  const stappen = 700
  const lengtes: number[] = [0]
  const punten: { x: number; y: number }[] = []
  let vx = 0
  let vy = -b
  for (let i = 0; i <= stappen; i += 1) {
    const h = -Math.PI / 2 + (2 * Math.PI * i) / stappen
    const x = a * Math.cos(h)
    const y = b * Math.sin(h)
    if (i > 0) lengtes.push(lengtes[i - 1] + Math.hypot(x - vx, y - vy))
    punten.push({ x, y })
    vx = x
    vy = y
  }

  const omtrek = lengtes[lengtes.length - 1]
  const uit: { x: number; y: number }[] = []
  let j = 0
  for (let k = 0; k < n; k += 1) {
    const doel = (omtrek * k) / n
    while (j < lengtes.length - 1 && lengtes[j] < doel) j += 1
    uit.push({ x: 50 + punten[j].x, y: 50 + punten[j].y * verhouding })
  }
  return uit
}

/**
 * De kleinste horizontale afstand tussen twee stoelen die ongeveer even hoog
 * liggen, in procent van de breedte.
 *
 * Alleen buren die elkaar verticaal kunnen raken tellen mee: twee stoelen
 * recht boven elkaar aan het uiteinde van de tafel mogen gerust dezelfde
 * x-waarde hebben. De grens van tien procent is ruwweg de hoogte van een
 * kaartje; daarboven zitten ze zo ver uit elkaar dat de breedte niet meer
 * uitmaakt.
 */
function kleinsteGat(punten: { x: number; y: number }[]): number {
  let kleinste = 100
  for (let i = 0; i < punten.length; i += 1) {
    for (let j = i + 1; j < punten.length; j += 1) {
      if (Math.abs(punten[i].y - punten[j].y) > 16) continue
      kleinste = Math.min(kleinste, Math.abs(punten[i].x - punten[j].x))
    }
  }
  return kleinste === 100 ? 27 : kleinste
}

/** "Chris Verbeeck" wordt "Chris V." — anders past er geen naam op een stoel. */
function korteNaam(naam: string): string {
  const d = naam.trim().split(/\s+/)
  return d.length > 1 ? `${d[0]} ${d[1][0]}.` : naam
}
