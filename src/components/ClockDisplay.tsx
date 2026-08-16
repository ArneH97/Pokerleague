'use client'

import { useEffect, useRef } from 'react'
import { resolveClock, formatDuration, formatBlinds, averageStack } from '@/lib/tournament/clock'
import { formatMoney, toClockState } from '@/lib/types'
import { useClockSound } from '@/lib/useClockSound'
import { useServerTime, useTicker } from '@/lib/useServerTime'
import { useTournament } from '@/lib/useTournament'

/** Hoe lang de aankondiging van een nieuw level blijft staan. */
const ANNOUNCE_MS = 8_000

/**
 * Zaalweergave. Ontworpen om vanaf de andere kant van een zaal leesbaar te
 * zijn: donkere achtergrond, weinig elementen, en de tijd domineert alles.
 *
 * Deze pagina heeft geen bedieningsknoppen. Wat hier staat wordt bepaald door
 * het floor-scherm; dat scheelt paniek als iemand tegen de laptop stoot.
 */
export function ClockDisplay({ tournamentId }: { tournamentId: string }) {
  const { tournament, club, levels, stats, loading, error, live } = useTournament(tournamentId)
  const { nowMs } = useServerTime()
  const sound = useClockSound()
  useTicker(200)

  const resolved = tournament
    ? resolveClock(toClockState(tournament), levels, nowMs())
    : null

  const running = tournament?.clock === 'running'
  const secondsLeft = resolved ? Math.ceil(resolved.remainingMs / 1000) : 0
  const levelIdx = resolved?.levelIdx ?? 0

  // Randdetectie voor het geluid. Bewust met refs binnen een effect: hier
  // hoort geen state bij, want er is niets te tekenen dat er niet al staat.
  const prevLevelRef = useRef<number | null>(null)
  const warnedLevelRef = useRef<number | null>(null)
  const armedLevelRef = useRef<number | null>(null)

  useEffect(() => {
    if (!running || !resolved?.level) return

    // Levelwissel: pas melden nadat we minstens één keer een vorig level
    // gezien hebben, anders piept het bij elke keer dat het scherm opent.
    if (prevLevelRef.current !== null && prevLevelRef.current !== levelIdx) {
      sound.playLevelUp()
      sound.announce(resolved.level)
    }
    prevLevelRef.current = levelIdx

    // Waarschuwing op één minuut. "Armed" zorgt dat we alleen piepen als we
    // dit level ook boven de minuut hebben gezien — anders piept een scherm
    // dat halverwege wordt geopend meteen.
    if (secondsLeft > 65) armedLevelRef.current = levelIdx

    if (
      secondsLeft <= 60 && secondsLeft > 0 &&
      armedLevelRef.current === levelIdx &&
      warnedLevelRef.current !== levelIdx &&
      !resolved.level.isBreak
    ) {
      warnedLevelRef.current = levelIdx
      sound.playOneMinute()
    }
  }, [running, levelIdx, secondsLeft, resolved?.level, sound])

  if (loading) return <Centered>Laden…</Centered>
  if (error || !tournament || !resolved) {
    return <Centered tone="error">{error ?? 'Onbekend tornooi'}</Centered>
  }

  const isBreak = resolved.level?.isBreak ?? false

  // De aankondiging is puur afgeleid van de klok: zitten we minder dan acht
  // seconden in een level, dan tonen we de nieuwe blinds groot. Geen state,
  // dus twee schermen tonen hem vanzelf tegelijk en een refresh verandert
  // niets.
  const announcing =
    running && !resolved.finished && levelIdx > 0 &&
    resolved.elapsedInLevelMs < ANNOUNCE_MS

  const urgency =
    !running || resolved.finished ? 'idle'
      : secondsLeft <= 10 ? 'critical'
      : secondsLeft <= 60 ? 'soon'
      : 'idle'

  const timeColor =
    urgency === 'critical' ? 'text-red-400'
      : urgency === 'soon' ? 'text-amber-300'
      : isBreak ? 'text-sky-300'
      : 'text-white'

  return (
    <main className="relative min-h-dvh select-none bg-neutral-950 text-white flex flex-col">
      <header className="flex items-baseline justify-between px-[3vw] pt-[2.5vh]">
        <div className="min-w-0">
          <p className="truncate text-[2.2vh] uppercase tracking-[0.25em] text-neutral-500">
            {club?.name ?? ''}
          </p>
          <h1 className="truncate text-[3.4vh] font-semibold">{tournament.name}</h1>
        </div>
        <div className="shrink-0 text-right">
          <p className="text-[2.2vh] uppercase tracking-[0.25em] text-neutral-500">
            {isBreak ? 'Pauze' : `Level ${levelIdx + 1}`}
          </p>
          <p className="text-[3.4vh] font-semibold tabular-nums">
            {tournament.clock === 'paused' && 'Gepauzeerd'}
            {tournament.clock === 'stopped' && 'Nog niet gestart'}
            {running && !resolved.finished && `van ${levels.length}`}
            {running && resolved.finished && 'Structuur voorbij'}
          </p>
        </div>
      </header>

      <section className="flex flex-1 flex-col items-center justify-center gap-[1vh] px-[3vw]">
        {isBreak && (
          <p className="text-[6vh] font-semibold uppercase tracking-[0.2em] text-sky-300">
            {resolved.level?.label ?? 'Pauze'}
          </p>
        )}

        <p
          className={`font-bold tabular-nums leading-none ${timeColor} ${
            urgency === 'critical' ? 'animate-pulse' : ''
          }`}
          style={{ fontSize: 'min(34vh, 30vw)' }}
        >
          {formatDuration(resolved.remainingMs)}
        </p>

        {!isBreak && (
          <p className="text-[9vh] font-semibold leading-none tabular-nums text-neutral-100">
            {formatBlinds(resolved.level)}
          </p>
        )}

        <p className="mt-[1vh] text-[2.8vh] text-neutral-500">
          {resolved.nextLevel
            ? `Hierna — ${formatBlinds(resolved.nextLevel)}`
            : 'Laatste level'}
        </p>
      </section>

      <footer className="grid grid-cols-4 gap-[2vw] px-[3vw] pb-[3vh] text-center">
        <Stat label="Spelers over" value={`${stats.playersLeft} / ${stats.entriesTotal}`} />
        <Stat
          label="Gem. stack"
          value={
            stats.totalChips > 0
              ? averageStack(stats.totalChips, stats.playersLeft).toLocaleString('nl-BE')
              : (tournament.starting_stack ?? 0).toLocaleString('nl-BE')
          }
        />
        <Stat
          label="Prijzenpot"
          value={
            stats.prizePoolCents > 0
              ? formatMoney(stats.prizePoolCents, club?.currency ?? 'EUR')
              : '—'
          }
        />
        <Stat
          label="Inzet"
          value={formatMoney(tournament.buyin_cents + tournament.fee_cents, club?.currency ?? 'EUR')}
        />
      </footer>

      {/* Aankondiging bij een nieuw level. */}
      {announcing && (
        <div className="pointer-events-none absolute inset-0 flex flex-col items-center justify-center bg-neutral-950/92">
          <p className="text-[4vh] uppercase tracking-[0.3em] text-neutral-400">
            {isBreak ? 'Pauze' : `Level ${levelIdx + 1}`}
          </p>
          <p className="mt-[2vh] text-center font-bold leading-none" style={{ fontSize: 'min(18vh, 14vw)' }}>
            {isBreak ? (resolved.level?.label ?? 'Pauze') : formatBlinds(resolved.level)}
          </p>
          {!isBreak && resolved.level && resolved.level.ante > 0 && (
            <p className="mt-[2vh] text-[4vh] text-neutral-400">
              Ante {resolved.level.ante.toLocaleString('nl-BE')}
            </p>
          )}
        </div>
      )}

      {/* Geluid moet één keer met een klik aangezet worden; browsers staan
          audio anders niet toe. Bewust groot en in beeld tot het gebeurd is. */}
      {sound.supported && !sound.enabled && (
        <button
          type="button"
          onClick={() => void sound.enable()}
          className="absolute bottom-[2vh] left-1/2 -translate-x-1/2 rounded-full bg-white px-6 py-3 text-[2vh] font-medium text-neutral-900 shadow-lg hover:bg-neutral-200"
        >
          Geluid aanzetten
        </button>
      )}

      {!live && (
        <p className="absolute bottom-2 right-3 text-[1.6vh] text-amber-500">
          Verbinding kwijt — scherm ververst trager
        </p>
      )}
    </main>
  )
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div className="min-w-0">
      <p className="truncate text-[1.9vh] uppercase tracking-[0.2em] text-neutral-500">{label}</p>
      <p className="truncate text-[4.4vh] font-semibold tabular-nums">{value}</p>
    </div>
  )
}

function Centered({
  children, tone = 'normal',
}: { children: React.ReactNode; tone?: 'normal' | 'error' }) {
  return (
    <main className="flex min-h-dvh items-center justify-center bg-neutral-950 p-8">
      <p className={`text-2xl ${tone === 'error' ? 'text-red-400' : 'text-neutral-400'}`}>
        {children}
      </p>
    </main>
  )
}
