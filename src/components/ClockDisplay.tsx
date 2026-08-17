'use client'

import { useEffect, useRef } from 'react'
import { resolveClock, formatDuration, averageStack, breakLabel } from '@/lib/tournament/clock'
import { formatMoney, toClockState } from '@/lib/types'
import { useClockSound } from '@/lib/useClockSound'
import { useServerTime, useTicker } from '@/lib/useServerTime'
import { useTournament } from '@/lib/useTournament'
import { useT } from '@/lib/i18n/context'

/** Hoe lang de aankondiging van een nieuw level blijft staan. */
const ANNOUNCE_MS = 8_000

/**
 * Zaalweergave.
 *
 * Twee dingen sturen elke keuze hier. Ten eerste: dit hangt op een beamer aan
 * de andere kant van een zaal, dus de tijd moet alles domineren en er mag
 * niets staan dat je van dichtbij moet lezen. Ten tweede: het is het enige
 * scherm dat spelers de hele avond zien, dus het draagt de huisstijl van de
 * club — logo, kleur, en accenten die met die kleur meebewegen.
 *
 * Geen bedieningsknoppen. Wat hier staat komt van het floor-scherm; dat
 * scheelt paniek als iemand tegen de laptop stoot.
 */
export function ClockDisplay({ tournamentId }: { tournamentId: string }) {
  const { tournament, club, levels, stats, loading, error, live } = useTournament(tournamentId)
  const { nowMs } = useServerTime()
  const sound = useClockSound()
  const t = useT()
  useTicker(200)

  const resolved = tournament
    ? resolveClock(toClockState(tournament), levels, nowMs())
    : null

  const running = tournament?.clock === 'running'
  const secondsLeft = resolved ? Math.ceil(resolved.remainingMs / 1000) : 0
  const levelIdx = resolved?.levelIdx ?? 0

  const prevLevelRef = useRef<number | null>(null)
  const warnedLevelRef = useRef<number | null>(null)
  const armedLevelRef = useRef<number | null>(null)

  useEffect(() => {
    if (!running || !resolved?.level) return

    if (prevLevelRef.current !== null && prevLevelRef.current !== levelIdx) {
      sound.playLevelUp()
      sound.announce(resolved.level)
    }
    prevLevelRef.current = levelIdx

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

  if (loading) return <Centered>{t('common.loading')}</Centered>
  if (error || !tournament || !resolved) {
    return <Centered tone="error">{error ?? t('clock.unknown')}</Centered>
  }

  const brand = club?.primary_color ?? '#10b981'
  const level = resolved.level
  const isBreak = level?.isBreak ?? false

  const announcing =
    running && !resolved.finished && levelIdx > 0 &&
    resolved.elapsedInLevelMs < ANNOUNCE_MS

  const urgency =
    !running || resolved.finished ? 'idle'
      : secondsLeft <= 10 ? 'critical'
      : secondsLeft <= 60 ? 'soon'
      : 'idle'

  // De clubkleur is de standaard. Alleen wanneer het dringend wordt neemt
  // rood of amber het over, want dán moet de kleur iets betekenen.
  const accent =
    urgency === 'critical' ? '#f87171'
      : urgency === 'soon' ? '#fbbf24'
      : isBreak ? '#38bdf8'
      : brand

  const levelDurationMs = Math.max(1, (level?.durationS ?? 0) * 1000)
  const progress = Math.min(1, resolved.elapsedInLevelMs / levelDurationMs)
  const playLevels = levels.filter((l) => !l.isBreak).length
  const playIdx = levels.slice(0, levelIdx + 1).filter((l) => !l.isBreak).length

  const elapsedTotal = tournament.started_at
    ? Math.max(0, nowMs() - Date.parse(tournament.started_at))
    : 0

  return (
    <main
      data-hall
      className="relative flex min-h-dvh select-none flex-col overflow-hidden bg-[var(--bg)] text-[var(--text)]"
    >
      {/* Zachte gloed in de clubkleur, zodat het scherm niet als een zwart
          gat aan de muur hangt. */}
      <div
        aria-hidden
        className="pointer-events-none absolute inset-0"
        style={{
          background: `radial-gradient(75vw 60vh at 50% 40%, ${accent}26 0%, transparent 72%)`,
          transition: 'background 700ms ease',
        }}
      />
      <Suits />

      {/* Het beeldmerk van de club als watermerk achter de tijd.
          Geen tegel met een eigen achtergrond: dat geeft een harde rechthoek
          tegen het scherm. Dit is het vrijstaande merk, groot, zacht, en aan
          de randen weggevaagd met een masker zodat er nergens een overgang
          te zien is. Het staat achter de cijfers, niet ernaast — zo blijft
          de tijd het grootste ding in de zaal. */}
      {club?.mark_url ? (
        <div
          aria-hidden
          className="pointer-events-none absolute inset-0 flex items-center justify-center"
          style={{
            // Het masker vervaagt het merk naar de randen toe, zodat er geen
            // zichtbare grens is tussen beeld en achtergrond.
            maskImage: 'radial-gradient(closest-side, #000 42%, transparent 88%)',
            WebkitMaskImage: 'radial-gradient(closest-side, #000 42%, transparent 88%)',
          }}
        >
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src={club.mark_url}
            alt=""
            className="h-[84vh] w-auto max-w-[86vw] object-contain"
            style={{
              opacity: isBreak ? 0.14 : 0.1,
              filter: 'saturate(1.1)',
              transition: 'opacity 700ms ease',
            }}
          />
        </div>
      ) : null}

      {/* Voortgang binnen het level over de volle breedte. Van veraf zie je
          zo in één oogopslag of het level bijna om is. */}
      <div className="absolute inset-x-0 top-0 h-[0.9vh] bg-white/[0.06]">
        <div
          className="h-full rounded-r-full transition-[width] duration-500 ease-linear"
          style={{ width: `${progress * 100}%`, background: accent, boxShadow: `0 0 2vh ${accent}` }}
        />
      </div>

      <header className="relative flex items-start justify-between gap-[3vw] px-[3.5vw] pt-[3vh]">
        {/* De clubnaam staat centraal boven de klok, dus hier alleen nog
            waar we in zitten: welk tornooi. */}
        <div className="min-w-0">
          <h1 className="truncate text-[3.2vh] font-semibold tracking-tight">{tournament.name}</h1>
        </div>

        <div className="shrink-0 text-right">
          <p className="text-[1.8vh] font-medium uppercase tracking-[0.28em] text-[var(--text-faint)]">
            {isBreak ? t('clock.break') : running ? t('clock.level') : tournament.clock === 'paused' ? t('clock.paused') : t('clock.notStarted')}
          </p>
          <p className="tnum text-[4.6vh] font-bold leading-none" style={{ color: accent }}>
            {isBreak ? '—' : playIdx}
            {!isBreak && (
              <span className="text-[2.4vh] font-medium text-[var(--text-faint)]">
                {' '}/ {playLevels}
              </span>
            )}
          </p>
        </div>
      </header>

      <section className="relative flex flex-1 flex-col items-center justify-center px-[3vw]">
        {/* De naam van de club, centraal boven de tijd. Als tekst en niet als
            beeld: dan schaalt hij mee met het scherm, blijft hij scherp op
            een beamer, en botst hij niet met het watermerk erachter.
            Valt er geen vrijstaand beeldmerk te tonen, dan is dít wat de
            zaal ziet — vandaar dat het er ook alleen goed uit moet zien. */}
        {club?.name ? (
          <p
            className="mb-[1vh] max-w-[80vw] truncate text-center font-semibold uppercase leading-none"
            style={{
              fontSize: 'min(4.6vh, 5vw)',
              letterSpacing: '0.42em',
              // Eén spatie te veel rechts door de letterafstand; die halen we
              // er weg zodat de naam echt gecentreerd staat.
              textIndent: '0.42em',
              color: accent,
              opacity: 0.92,
              textShadow: `0 0 6vh ${accent}44`,
            }}
          >
            {club.name}
          </p>
        ) : null}

        {isBreak && (
          <p
            className="mb-[1vh] text-[6.5vh] font-bold uppercase tracking-[0.25em]"
            style={{ color: accent }}
          >
            {breakLabel(level?.label, t('clock.break'))}
          </p>
        )}

        <p
          className={`tnum font-bold leading-[0.85] tracking-tight ${
            urgency === 'critical' ? 'animate-pulse' : ''
          }`}
          style={{
            fontSize: 'min(33vh, 30vw)',
            color: urgency === 'idle' && !isBreak ? '#ffffff' : accent,
            textShadow: `0 0 9vh ${accent}55`,
          }}
        >
          {formatDuration(resolved.remainingMs)}
        </p>

        {!isBreak && level && (
          <div className="mt-[2.5vh] flex items-end gap-[3vw]">
            <BlindChip label={t('clock.smallBlind')} value={level.smallBlind} />
            <BlindChip label={t('clock.bigBlind')} value={level.bigBlind} big accent={accent} />
            {level.ante > 0 && <BlindChip label={t('clock.ante')} value={level.ante} />}
          </div>
        )}

        <p className="mt-[2.5vh] text-[2.5vh] text-[var(--text-faint)]">
          {resolved.nextLevel
            ? resolved.nextLevel.isBreak
              ? `${t('clock.next')} — ${breakLabel(resolved.nextLevel.label, t('clock.break'))}`
              : `${t('clock.next')} — ${resolved.nextLevel.smallBlind.toLocaleString('nl-BE')} / ${resolved.nextLevel.bigBlind.toLocaleString('nl-BE')}`
            : t('clock.lastLevel')}
        </p>
      </section>

      {sound.supported && !sound.enabled && (
        <div className="relative flex justify-center pb-[1.5vh]">
          <button
            type="button"
            onClick={() => void sound.enable()}
            className="rounded-full px-[2.5vw] py-[1.2vh] text-[1.8vh] font-semibold shadow-2xl transition hover:brightness-110"
            style={{ background: accent, color: '#07090c' }}
          >
            {t('clock.enableSound')}
          </button>
        </div>
      )}

      <LevelPips levels={levels} current={levelIdx} accent={accent} />

      <footer className="relative grid grid-cols-4 gap-[1.6vw] px-[3.5vw] pb-[3.5vh] pt-[1.8vh]">
        <Stat label={t('clock.playersLeft')} value={String(stats.playersLeft)} sub={`${t('common.of')} ${stats.entriesTotal}`} />
        <Stat
          label={t('clock.avgStack')}
          value={(stats.totalChips > 0
            ? averageStack(stats.totalChips, stats.playersLeft)
            : tournament.starting_stack ?? 0
          ).toLocaleString('nl-BE')}
        />
        <Stat
          label={t('clock.prizePool')}
          value={stats.prizePoolCents > 0
            ? formatMoney(stats.prizePoolCents, club?.currency ?? 'EUR')
            : '—'}
        />
        <Stat label={t('clock.elapsed')} value={elapsedTotal > 0 ? formatDuration(elapsedTotal) : '—'} />
      </footer>

      {announcing && level && (
        <div className="pointer-events-none absolute inset-0 flex flex-col items-center justify-center bg-[color-mix(in_oklab,var(--bg)_88%,transparent)] backdrop-blur-sm">
          <p className="text-[3.2vh] font-medium uppercase tracking-[0.35em] text-[var(--text-muted)]">
            {isBreak ? t('clock.break') : `${t('clock.level')} ${playIdx}`}
          </p>
          <p
            className="tnum mt-[2vh] text-center font-bold leading-none"
            style={{ fontSize: 'min(20vh, 15vw)', color: accent }}
          >
            {isBreak
              ? breakLabel(level.label, t('clock.break'))
              : `${level.smallBlind.toLocaleString('nl-BE')} / ${level.bigBlind.toLocaleString('nl-BE')}`}
          </p>
          {!isBreak && level.ante > 0 && (
            <p className="mt-[2vh] text-[4vh] text-[var(--text-muted)]">
              {t('clock.ante')} {level.ante.toLocaleString('nl-BE')}
            </p>
          )}
        </div>
      )}

      {!live && (
        <p className="absolute bottom-2 right-3 text-[1.5vh] text-[#fbbf24]">
          {t('clock.offline')}
        </p>
      )}
    </main>
  )
}

/** Eén blindwaarde als los blok, zodat SB en BB niet in elkaar overlopen. */
function BlindChip({
  label, value, big, accent,
}: { label: string; value: number; big?: boolean; accent?: string }) {
  return (
    <div className="text-center">
      <p className="text-[1.6vh] font-medium uppercase tracking-[0.22em] text-[var(--text-faint)]">
        {label}
      </p>
      <p
        className="tnum font-bold leading-none"
        style={{
          fontSize: big ? '10vh' : '7.5vh',
          color: big ? (accent ?? '#ffffff') : '#ffffff',
        }}
      >
        {value.toLocaleString('nl-BE')}
      </p>
    </div>
  )
}

/** Streepjes die tonen hoe ver het tornooi in de structuur zit. */
function LevelPips({
  levels, current, accent,
}: { levels: { idx: number; isBreak: boolean }[]; current: number; accent: string }) {
  if (levels.length === 0) return null
  return (
    <div className="relative flex items-end justify-center gap-[0.35vw] px-[3.5vw]">
      {levels.map((l) => {
        const done = l.idx < current
        const now = l.idx === current
        return (
          <span
            key={l.idx}
            className="rounded-full transition-all duration-300"
            style={{
              width: now ? '1.6vw' : '0.7vw',
              height: l.isBreak ? '0.6vh' : now ? '1.4vh' : '0.9vh',
              background: now ? accent : done ? `${accent}66` : '#ffffff1f',
              boxShadow: now ? `0 0 1.4vh ${accent}` : undefined,
            }}
          />
        )
      })}
    </div>
  )
}

function Stat({ label, value, sub }: { label: string; value: string; sub?: string }) {
  return (
    <div className="min-w-0 rounded-[1.4vh] border border-white/[0.07] bg-white/[0.035] px-[1.2vw] py-[1.4vh] text-center backdrop-blur-sm">
      <p className="truncate text-[1.5vh] font-medium uppercase tracking-[0.2em] text-[var(--text-faint)]">
        {label}
      </p>
      <p className="tnum truncate text-[4.2vh] font-bold leading-tight">{value}</p>
      {sub && <p className="tnum text-[1.5vh] text-[var(--text-faint)]">{sub}</p>}
    </div>
  )
}

/** Kaartsymbolen als zacht behangmotief. Nauwelijks zichtbaar, maar het
 *  scherm oogt er minder kaal door. */
function Suits() {
  return (
    <div aria-hidden className="pointer-events-none absolute inset-0 overflow-hidden">
      <span className="absolute -left-[3vw] top-[12vh] text-[38vh] leading-none text-white/[0.022]">♠</span>
      <span className="absolute -right-[2vw] bottom-[6vh] text-[34vh] leading-none text-white/[0.022]">♦</span>
      <span className="absolute right-[16vw] top-[4vh] text-[16vh] leading-none text-white/[0.018]">♥</span>
      <span className="absolute left-[18vw] bottom-[2vh] text-[14vh] leading-none text-white/[0.018]">♣</span>
    </div>
  )
}

function Centered({
  children, tone = 'normal',
}: { children: React.ReactNode; tone?: 'normal' | 'error' }) {
  return (
    <main data-hall className="flex min-h-dvh items-center justify-center bg-[var(--bg)] p-8">
      <p className={`text-2xl ${tone === 'error' ? 'text-[#f87171]' : 'text-[var(--text-muted)]'}`}>
        {children}
      </p>
    </main>
  )
}
