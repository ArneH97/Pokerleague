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
 * De straal is zo gekozen dat een stoelkaartje nooit buiten het vlak valt:
 * 50% − 34% − de halve kaartbreedte blijft positief. Dat is geen schoonheid
 * maar noodzaak — valt er een kaartje buiten, dan schuift de hele pagina
 * zijwaarts op een telefoon.
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

  return (
    <div className="relative w-full flex-1" style={{ minHeight: '17rem' }}>
      {/* De rail: de leren rand waar de spelers hun armen op leggen. Hij maakt
          van een groene vlek een tafel. */}
      <div
        aria-hidden
        className="absolute rounded-[50%]"
        style={{
          inset: '7% 10%',
          background:
            'linear-gradient(165deg, var(--rail-licht) 0%, var(--rail) 48%, #180f0a 100%)',
          boxShadow: '0 18px 40px -18px #000, inset 0 1px 0 rgba(255,225,160,.13)',
        }}
      />
      <div
        aria-hidden
        className="absolute rounded-[50%]"
        style={{
          inset: 'calc(7% + 13px) calc(10% + 13px)',
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
          inset: 'calc(7% + 13px + 13%) calc(10% + 13px + 13%)',
          borderColor: 'rgba(251,191,36,.12)',
        }}
      />

      {seats.map((s, i) => {
        const hoek = ((-90 + i * (360 / n)) * Math.PI) / 180
        const x = 50 + 34 * Math.cos(hoek)
        const y = 50 + 38 * Math.sin(hoek)
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
            style={{ left: `${x}%`, top: `${y}%`, width: '27.5%' }}
            className={[
              'absolute -translate-x-1/2 -translate-y-1/2 rounded-xl px-1 pb-1.5 pt-1 text-center',
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
            <span className="tnum block text-[0.54rem] leading-none text-[var(--text-faint)]">
              {s.seatNo}
            </span>
            <span className="mt-0.5 block truncate text-[0.72rem] font-semibold leading-tight">
              {leeg ? (pickedId !== null ? placeHere : labelFree) : korteNaam(s.name ?? '')}
            </span>
            <span
              className={`tnum block text-[0.66rem] leading-tight ${
                kort ? 'text-[var(--danger)]' : 'text-[var(--text-muted)]'
              }`}
            >
              {s.chipCount !== null ? s.chipCount.toLocaleString('nl-BE') : '—'}
            </span>
            {/* Blinds en niet alleen fiches: dat is het getal waarin een floor
                denkt. 9 bb zegt meer dan 7.500. */}
            {!leeg && s.chipCount !== null && bigBlind > 0 && (
              <span className="tnum block text-[0.56rem] leading-none text-[var(--text-faint)]">
                {Math.round(s.chipCount / bigBlind)} bb
              </span>
            )}
          </button>
        )
      })}
    </div>
  )
}

/** "Chris Verbeeck" wordt "Chris V." — anders past er geen naam op een stoel. */
function korteNaam(naam: string): string {
  const d = naam.trim().split(/\s+/)
  return d.length > 1 ? `${d[0]} ${d[1][0]}.` : naam
}
