'use client'

import Link from 'next/link'
import { useEffect, useMemo, useRef, useState } from 'react'
import { FloorPlayers } from '@/components/FloorPlayers'
import { createClient } from '@/lib/supabase/client'
import {
  resolveClock, levelsForClock, formatDuration, formatBlinds, breakLabel,
  start, pause, resume, nextLevel, prevLevel, adjustTime, normalise,
  type ClockState,
} from '@/lib/tournament/clock'
import { expectedChipsInPlay, toClockState } from '@/lib/types'
import { useServerTime, useTicker } from '@/lib/useServerTime'
import { useTournament } from '@/lib/useTournament'
import { useT } from '@/lib/i18n/context'
import { dbMessage } from '@/lib/dbMessage'

/**
 * Bedieningsscherm voor de floor.
 *
 * Ontwerpregel: elke knop doet één ding en het effect is meteen zichtbaar op
 * de zaalweergave. Geen bevestigingsdialogen — op een tornooiavond is een
 * extra klik erger dan een vergissing die je met één klik terugdraait.
 */
export function FloorControls({
  tournamentId,
  clockHref,
  backHref,
}: {
  tournamentId: string
  /** Waar het zaalscherm staat; komt van de clubroute zodat de URL klopt. */
  clockHref: string
  /** Terug naar het clubdashboard. Zonder dit zit de floor vast op dit scherm. */
  backHref: string
}) {
  const supabase = useMemo(() => createClient(), [])
  const { tournament, club, levels: planned, stats, loading, error, live } = useTournament(tournamentId)
  const { nowMs, nowIso } = useServerTime()
  const [busy, setBusy] = useState(false)
  const [actionError, setActionError] = useState<string | null>(null)
  const t = useT()
  const rolledRef = useRef<number | null>(null)
  useTicker(250)

  // Zit de klok aan het laatste level van de structuur, dan komen er levels
  // bij in hetzelfde ritme. Zonder dat loopt een tornooi dat uitloopt vast op
  // 00:00 met stilstaande blinds — en dan raakt het nooit meer uitgespeeld.
  const levels = tournament
    ? levelsForClock(planned, toClockState(tournament), nowMs())
    : planned

  async function apply(next: ClockState) {
    setBusy(true)
    setActionError(null)
    const { error: err } = await supabase
      .from('tournaments')
      .update({
        clock: next.status,
        level_idx: Math.round(next.levelIdx),
        level_started_at: next.levelStartedAt,
        // level_elapsed_ms is een bigint; hier nog eens afronden zodat er
        // nooit een gebroken getal naar de database kan.
        level_elapsed_ms: Math.round(next.levelElapsedMs),
        ...(next.status === 'running'
          ? {
              status: 'running' as const,
              // Het startmoment van de avond, één keer gezet bij de eerste
              // keer starten. Hierop draait de teller "gespeeld" op het
              // zaalscherm; die stond leeg omdat dit nergens werd
              // weggeschreven. Pauzeren en hervatten raken het niet — dan
              // zou de avond telkens opnieuw beginnen.
              ...(tournament?.started_at ? {} : { started_at: nowIso() }),
            }
          : {}),
      })
      .eq('id', tournamentId)

    if (err) {
      setActionError(dbMessage(err, t))
    }
    setBusy(false)
  }

  // Rolde de klok door een levelgrens zonder dat er geklikt werd, dan loopt
  // de opgeslagen stand achter op wat de zaal ziet. Eén keer wegschrijven en
  // ze lopen weer gelijk. Zonder dit blijft de database op het oude level
  // staan tot de floor iets aanraakt — en dat merk je pas bij het pauzeren,
  // of wanneer iemand het scherm heropent.
  //
  // Dit geldt ook voor een gepauzeerde klok. Die rolt niet door van het
  // wachten — de opgebouwde tijd staat stil — maar staat er méér tijd geboekt
  // dan het level lang duurt, dan klopt de opgeslagen stand niet en hoort ze
  // rechtgezet te worden. Het startmoment blijft dan leeg; anders zou de klok
  // van het bijwerken alleen al gaan lopen.
  useEffect(() => {
    if (!tournament || levels.length === 0) return
    if (tournament.clock === 'stopped') return

    const running = tournament.clock === 'running'
    const state = toClockState(tournament)
    const here = resolveClock(state, levels, nowMs())
    if (here.rolledOver === 0 || here.finished) return
    if (rolledRef.current === here.levelIdx) return

    rolledRef.current = here.levelIdx
    const fixed = normalise(state, levels, nowMs())
    void supabase
      .from('tournaments')
      .update({
        level_idx: Math.round(fixed.levelIdx),
        level_started_at: running ? nowIso() : null,
        level_elapsed_ms: Math.round(fixed.levelElapsedMs),
      })
      .eq('id', tournamentId)
  }, [tournament, levels, nowMs, nowIso, supabase, tournamentId])

  // De terugweg staat ook op het laad- en foutscherm. Juist dáár heb je hem
  // nodig: een floor die op een leeg scherm belandt heeft anders alleen nog
  // de terugknop van de browser, en die is op een tablet ver weg.
  const back = <BackLink href={backHref} label={t('floor.back')} />

  if (loading) return <Shell back={back}><p className="text-[var(--text-muted)]">{t('common.loading')}</p></Shell>
  if (error || !tournament) {
    return <Shell back={back}><p className="text-[var(--danger)]">{error ?? t('clock.unknown')}</p></Shell>
  }

  const state = toClockState(tournament)
  const resolved = resolveClock(state, levels, nowMs())
  const running = tournament.clock === 'running'
  const neverStarted = tournament.clock === 'stopped' && !tournament.started_at

  // Levels tellen zonder de pauzes mee te rekenen, net als op het zaalscherm.
  // Anders staat hier "level 6 van 20" terwijl de zaal "5 / 17" leest, en dan
  // gaat de floor door de telefoon een ander nummer zeggen dan de spelers voor
  // zich zien. Een pauze is geen level: die heeft een naam, geen nummer.
  const playLevels = levels.filter((l) => !l.isBreak).length
  const playIdx = levels.slice(0, resolved.levelIdx + 1).filter((l) => !l.isBreak).length

  // Hetzelfde nummer voor de structuurlijst onderaan, zodat "#5" daar naar
  // hetzelfde level wijst als de kop hierboven.
  const playNo = new Map<number, number>()
  let n = 0
  for (const l of levels) {
    if (l.isBreak) continue
    n += 1
    playNo.set(l.idx, n)
  }

  // Zolang er nog ingekocht kan worden verandert de pot. Het prijzengeld
  // vastleggen heeft pas zin daarna; het paneel waarschuwt daarvoor.
  const entriesClosed =
    tournament.late_reg_level !== null && playIdx > tournament.late_reg_level

  // Het ijkpunt waartegen de floor zijn telling aan de finaletafel afzet.
  const expectedChips = expectedChipsInPlay(tournament, stats)

  return (
    <Shell back={back}>
      <header className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <p className="text-sm uppercase tracking-widest text-[var(--text-faint)]">
            {club?.name} · {t('floor.title')}
          </p>
          <h1 className="text-2xl font-semibold">{tournament.name}</h1>
        </div>
        <div className="flex items-center gap-3">
          <span
            className={`inline-flex items-center gap-2 rounded-full px-3 py-1 text-xs ${
              live ? 'bg-[color-mix(in_oklab,var(--ok)_14%,transparent)] text-[var(--ok)]' : 'bg-[color-mix(in_oklab,var(--warn)_14%,transparent)] text-[var(--warn)]'
            }`}
          >
            <span className={`size-2 rounded-full ${live ? 'bg-[var(--ok)]' : 'bg-[var(--warn)]'}`} />
            {live ? t('floor.live') : t('floor.offline')}
          </span>
          <a
            href={clockHref}
            target="_blank"
            rel="noreferrer"
            className="rounded-lg border border-[var(--line-strong)] px-3 py-1.5 text-sm hover:bg-[var(--surface-hover)]"
          >
            {t('floor.openHallScreen')} ↗
          </a>
        </div>
      </header>

      <section className="rounded-2xl bg-[var(--surface)] p-6 text-center">
        <p className="text-sm uppercase tracking-widest text-[var(--text-faint)]">
          {resolved.level?.isBreak
            ? breakLabel(resolved.level.label, t('clock.break'))
            : `${t('clock.level')} ${playIdx} ${t('common.of')} ${playLevels || '—'}`}
        </p>
        <p className="my-2 text-7xl font-bold tabular-nums leading-none">
          {formatDuration(resolved.remainingMs)}
        </p>
        <p className="text-2xl text-[var(--text-muted)]">{formatBlinds(resolved.level)}</p>
        <p className="mt-1 text-sm text-[var(--text-faint)]">
          {resolved.nextLevel ? `${t('clock.next')}: ${formatBlinds(resolved.nextLevel)}` : t('clock.lastLevel')}
        </p>
        {/* Eén gemiste levelgrens is geen incident: de klok hoort door te
            lopen en het effect wordt hierboven meteen weggeschreven. Pas
            vanaf twee levels is er echt iets aan de hand — dan stond het
            scherm een tijd uit. */}
        {resolved.rolledOver > 1 && running && (
          <p className="mt-3 text-sm text-[var(--warn)]">
            {resolved.rolledOver} {t('floor.rolledOver')}
          </p>
        )}
      </section>

      {levels.length === 0 && (
        <p className="rounded-xl border border-[color-mix(in_oklab,var(--warn)_35%,transparent)] bg-[color-mix(in_oklab,var(--warn)_10%,transparent)] p-4 text-sm text-[var(--warn)]">
          {t('floor.noStructure')}
        </p>
      )}

      <section className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        {neverStarted ? (
          <Button
            primary
            disabled={busy || levels.length === 0}
            onClick={() => apply(start(nowIso()))}
          >
            {t('floor.start')}
          </Button>
        ) : running ? (
          <Button primary disabled={busy} onClick={() => apply(pause(state, levels, nowMs()))}>
            {t('floor.pause')}
          </Button>
        ) : (
          <Button primary disabled={busy} onClick={() => apply(resume(state, nowIso()))}>
            {t('floor.resume')}
          </Button>
        )}

        <Button
          disabled={busy || resolved.levelIdx === 0}
          onClick={() => apply(prevLevel(state, levels, nowMs(), nowIso()))}
        >
          ← {t('floor.prevLevel')}
        </Button>
        <Button
          disabled={busy || resolved.levelIdx >= levels.length - 1}
          onClick={() => apply(nextLevel(state, levels, nowMs(), nowIso()))}
        >
          {t('floor.nextLevel')} →
        </Button>
        <div className="grid grid-cols-2 gap-3">
          <Button
            disabled={busy}
            onClick={() => apply(adjustTime(state, levels, -60_000, nowMs(), nowIso()))}
          >
            {t('floor.minusMinute')}
          </Button>
          <Button
            disabled={busy}
            onClick={() => apply(adjustTime(state, levels, 60_000, nowMs(), nowIso()))}
          >
            {t('floor.plusMinute')}
          </Button>
        </div>
      </section>

      {actionError && (
        <p className="rounded-xl border border-[color-mix(in_oklab,var(--danger)_35%,transparent)] bg-[color-mix(in_oklab,var(--danger)_10%,transparent)] p-4 text-sm text-[var(--danger)]">
          {actionError}
        </p>
      )}

      <section className="grid grid-cols-3 gap-3 text-center">
        <Tile label={t('clock.playersLeft')} value={`${stats.playersLeft} / ${stats.entriesTotal}`} />
        <Tile label={t('floor.entries')} value={String(stats.entriesTotal)} />
        <Tile
          label={t('clock.prizePool')}
          value={
            stats.prizePoolCents > 0
              ? new Intl.NumberFormat('nl-BE', {
                  style: 'currency', currency: club?.currency ?? 'EUR',
                  maximumFractionDigits: 0,
                }).format(stats.prizePoolCents / 100)
              : '—'
          }
        />
      </section>

      {/* Het spelersbeheer staat onder de klok en niet op een aparte pagina:
          aan de deur en aan tafel gebeurt alles door elkaar, en wisselen van
          scherm midden in een level is precies wanneer je iets vergeet. */}
      <FloorPlayers
        tournamentId={tournamentId}
        clubId={tournament.club_id}
        bountyMode={tournament.bounty_mode}
        maxReentries={tournament.max_reentries}
        finished={tournament.status === 'finished' || tournament.status === 'cancelled'}
        money={{
          buyinCents: tournament.buyin_cents,
          addonCents: tournament.addon_cents,
          currency: club?.currency ?? 'EUR',
        }}
        potCents={stats.prizePoolCents}
        entriesClosed={entriesClosed}
        expectedChips={expectedChips}
        clubLocale={club?.locale ?? 'nl'}
      />

      {levels.length > 0 && (
        <section>
          <h2 className="mb-2 text-sm uppercase tracking-widest text-[var(--text-faint)]">{t('floor.structure')}</h2>
          <ol className="divide-y divide-[var(--line)] overflow-hidden rounded-xl border border-[var(--line)]">
            {levels.map((l) => (
              <li
                key={l.idx}
                className={`flex items-center justify-between px-4 py-2 text-sm ${
                  l.idx === resolved.levelIdx ? 'bg-[var(--surface-2)]' : ''
                } ${l.isBreak ? 'text-[#7dd3fc]' : ''}`}
              >
                <span className="w-16 text-[var(--text-faint)]">
                  {l.isBreak ? t('clock.break') : `#${playNo.get(l.idx) ?? l.idx + 1}`}
                </span>
                <span className="flex-1 tabular-nums">{formatBlinds(l)}</span>
                <span className="tabular-nums text-[var(--text-faint)]">
                  {Math.round(l.durationS / 60)} {t('floor.min')}
                </span>
              </li>
            ))}
          </ol>
        </section>
      )}
    </Shell>
  )
}

function Shell({ children, back }: { children: React.ReactNode; back?: React.ReactNode }) {
  return (
    <main className="mx-auto flex min-h-dvh max-w-3xl flex-col gap-6 bg-[var(--bg)] p-6 text-white">
      {back}
      {children}
    </main>
  )
}

/** Terug naar het clubdashboard. Bewust bovenaan links: daar zoekt iedereen. */
function BackLink({ href, label }: { href: string; label: string }) {
  return (
    <Link
      href={href}
      className="-mb-2 inline-flex w-fit items-center gap-1.5 rounded-lg px-2 py-1.5 text-sm text-[var(--text-faint)] transition-colors hover:bg-[var(--surface-hover)] hover:text-[var(--text)]"
    >
      <span aria-hidden>←</span> {label}
    </Link>
  )
}

function Button({
  children, onClick, disabled, primary,
}: {
  children: React.ReactNode
  onClick?: () => void
  disabled?: boolean
  primary?: boolean
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      className={`rounded-xl px-4 py-4 text-base font-medium transition disabled:cursor-not-allowed disabled:opacity-40 ${
        primary
          ? 'bg-[var(--brand)] text-[var(--on-brand)] hover:brightness-110'
          : 'border border-[var(--line-strong)] hover:bg-[var(--surface-hover)]'
      }`}
    >
      {children}
    </button>
  )
}

function Tile({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-xl border border-[var(--line)] p-4">
      <p className="text-xs uppercase tracking-widest text-[var(--text-faint)]">{label}</p>
      <p className="mt-1 text-2xl font-semibold tabular-nums">{value}</p>
    </div>
  )
}
