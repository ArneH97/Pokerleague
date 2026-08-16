'use client'

import { resolveClock, formatDuration, formatBlinds, averageStack } from '@/lib/tournament/clock'
import { formatMoney, toClockState } from '@/lib/types'
import { useServerTime, useTicker } from '@/lib/useServerTime'
import { useTournament } from '@/lib/useTournament'

/**
 * Zaalweergave. Ontworpen om vanaf de andere kant van een zaal leesbaar te
 * zijn: donkere achtergrond, weinig elementen, en de tijd domineert alles.
 *
 * Deze pagina heeft geen knoppen. Wat hier staat wordt bepaald door het
 * floor-scherm; dat scheelt paniek als iemand tegen de laptop stoot.
 */
export function ClockDisplay({ tournamentId }: { tournamentId: string }) {
  const { tournament, club, levels, stats, loading, error, live } = useTournament(tournamentId)
  const { nowMs } = useServerTime()
  useTicker(200)

  if (loading) {
    return <Centered>Laden…</Centered>
  }
  if (error || !tournament) {
    return <Centered tone="error">{error ?? 'Onbekend tornooi'}</Centered>
  }

  const resolved = resolveClock(toClockState(tournament), levels, nowMs())
  const isBreak = resolved.level?.isBreak ?? false
  const secondsLeft = Math.ceil(resolved.remainingMs / 1000)
  const running = tournament.clock === 'running'

  // Laatste minuut oplichten, laatste tien seconden nadrukkelijk. Dealers
  // kijken hier op om te weten wanneer ze de blinds moeten verhogen.
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
    <main className="min-h-dvh bg-neutral-950 text-white flex flex-col select-none">
      <header className="flex items-baseline justify-between px-[3vw] pt-[2.5vh]">
        <div className="min-w-0">
          <p className="text-[2.2vh] uppercase tracking-[0.25em] text-neutral-500 truncate">
            {club?.name ?? ''}
          </p>
          <h1 className="text-[3.4vh] font-semibold truncate">{tournament.name}</h1>
        </div>
        <div className="text-right shrink-0">
          <p className="text-[2.2vh] uppercase tracking-[0.25em] text-neutral-500">
            {isBreak ? 'Pauze' : `Level ${resolved.levelIdx + 1}`}
          </p>
          <p className="text-[3.4vh] font-semibold tabular-nums">
            {tournament.clock === 'paused' && 'Gepauzeerd'}
            {tournament.clock === 'stopped' && 'Nog niet gestart'}
            {running && !resolved.finished && `van ${levels.length}`}
            {running && resolved.finished && 'Structuur voorbij'}
          </p>
        </div>
      </header>

      <section className="flex-1 flex flex-col items-center justify-center gap-[1vh] px-[3vw]">
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
          <p className="text-[9vh] font-semibold tabular-nums leading-none text-neutral-100">
            {formatBlinds(resolved.level)}
          </p>
        )}

        <p className="text-[2.8vh] text-neutral-500 mt-[1vh]">
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
      <p className="text-[1.9vh] uppercase tracking-[0.2em] text-neutral-500 truncate">{label}</p>
      <p className="text-[4.4vh] font-semibold tabular-nums truncate">{value}</p>
    </div>
  )
}

function Centered({
  children, tone = 'normal',
}: { children: React.ReactNode; tone?: 'normal' | 'error' }) {
  return (
    <main className="min-h-dvh bg-neutral-950 flex items-center justify-center p-8">
      <p className={`text-2xl ${tone === 'error' ? 'text-red-400' : 'text-neutral-400'}`}>
        {children}
      </p>
    </main>
  )
}
