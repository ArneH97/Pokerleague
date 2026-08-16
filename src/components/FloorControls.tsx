'use client'

import { useMemo, useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import {
  resolveClock, formatDuration, formatBlinds,
  start, pause, resume, nextLevel, prevLevel, adjustTime,
  type ClockState,
} from '@/lib/tournament/clock'
import { toClockState } from '@/lib/types'
import { useServerTime, useTicker } from '@/lib/useServerTime'
import { useTournament } from '@/lib/useTournament'

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
}: {
  tournamentId: string
  /** Waar het zaalscherm staat; komt van de clubroute zodat de URL klopt. */
  clockHref: string
}) {
  const supabase = useMemo(() => createClient(), [])
  const { tournament, club, levels, stats, loading, error, live } = useTournament(tournamentId)
  const { nowMs, nowIso } = useServerTime()
  const [busy, setBusy] = useState(false)
  const [actionError, setActionError] = useState<string | null>(null)
  useTicker(250)

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
        ...(next.status === 'running' ? { status: 'running' as const } : {}),
      })
      .eq('id', tournamentId)

    if (err) {
      setActionError(
        err.message.includes('row-level security') || err.code === '42501'
          ? 'Geen rechten om dit tornooi te bedienen.'
          : err.message,
      )
    }
    setBusy(false)
  }

  if (loading) return <Shell><p className="text-neutral-400">Laden…</p></Shell>
  if (error || !tournament) {
    return <Shell><p className="text-red-400">{error ?? 'Onbekend tornooi'}</p></Shell>
  }

  const state = toClockState(tournament)
  const resolved = resolveClock(state, levels, nowMs())
  const running = tournament.clock === 'running'
  const neverStarted = tournament.clock === 'stopped' && !tournament.started_at

  return (
    <Shell>
      <header className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <p className="text-sm uppercase tracking-widest text-neutral-500">
            {club?.name} · Floor
          </p>
          <h1 className="text-2xl font-semibold">{tournament.name}</h1>
        </div>
        <div className="flex items-center gap-3">
          <span
            className={`inline-flex items-center gap-2 rounded-full px-3 py-1 text-xs ${
              live ? 'bg-emerald-950 text-emerald-400' : 'bg-amber-950 text-amber-400'
            }`}
          >
            <span className={`size-2 rounded-full ${live ? 'bg-emerald-400' : 'bg-amber-400'}`} />
            {live ? 'Live' : 'Verbinding kwijt'}
          </span>
          <a
            href={clockHref}
            target="_blank"
            rel="noreferrer"
            className="rounded-lg border border-neutral-700 px-3 py-1.5 text-sm hover:bg-neutral-800"
          >
            Zaalscherm openen ↗
          </a>
        </div>
      </header>

      <section className="rounded-2xl bg-neutral-900 p-6 text-center">
        <p className="text-sm uppercase tracking-widest text-neutral-500">
          {resolved.level?.isBreak
            ? (resolved.level.label ?? 'Pauze')
            : `Level ${resolved.levelIdx + 1} van ${levels.length || '—'}`}
        </p>
        <p className="my-2 text-7xl font-bold tabular-nums leading-none">
          {formatDuration(resolved.remainingMs)}
        </p>
        <p className="text-2xl text-neutral-300">{formatBlinds(resolved.level)}</p>
        <p className="mt-1 text-sm text-neutral-500">
          {resolved.nextLevel ? `Hierna: ${formatBlinds(resolved.nextLevel)}` : 'Laatste level'}
        </p>
        {resolved.rolledOver > 0 && running && (
          <p className="mt-3 text-sm text-amber-400">
            {resolved.rolledOver} level{resolved.rolledOver > 1 ? 's' : ''} automatisch
            doorgerold — de klok liep door zonder dat er geklikt werd.
          </p>
        )}
      </section>

      {levels.length === 0 && (
        <p className="rounded-xl border border-amber-900 bg-amber-950/50 p-4 text-sm text-amber-300">
          Dit tornooi heeft nog geen blindstructuur. Koppel er een aan voor je start,
          anders heeft de klok niets om af te tellen.
        </p>
      )}

      <section className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        {neverStarted ? (
          <Button
            primary
            disabled={busy || levels.length === 0}
            onClick={() => apply(start(nowIso()))}
          >
            Tornooi starten
          </Button>
        ) : running ? (
          <Button primary disabled={busy} onClick={() => apply(pause(state, nowMs()))}>
            Pauzeren
          </Button>
        ) : (
          <Button primary disabled={busy} onClick={() => apply(resume(state, nowIso()))}>
            Hervatten
          </Button>
        )}

        <Button
          disabled={busy || resolved.levelIdx === 0}
          onClick={() => apply(prevLevel(state, levels, nowMs(), nowIso()))}
        >
          ← Vorig level
        </Button>
        <Button
          disabled={busy || resolved.levelIdx >= levels.length - 1}
          onClick={() => apply(nextLevel(state, levels, nowMs(), nowIso()))}
        >
          Volgend level →
        </Button>
        <div className="grid grid-cols-2 gap-3">
          <Button
            disabled={busy}
            onClick={() => apply(adjustTime(state, -60_000, nowMs(), nowIso()))}
          >
            −1 min
          </Button>
          <Button
            disabled={busy}
            onClick={() => apply(adjustTime(state, 60_000, nowMs(), nowIso()))}
          >
            +1 min
          </Button>
        </div>
      </section>

      {actionError && (
        <p className="rounded-xl border border-red-900 bg-red-950/50 p-4 text-sm text-red-300">
          {actionError}
        </p>
      )}

      <section className="grid grid-cols-3 gap-3 text-center">
        <Tile label="Spelers over" value={`${stats.playersLeft} / ${stats.entriesTotal}`} />
        <Tile label="Inkopen" value={String(stats.entriesTotal)} />
        <Tile
          label="Prijzenpot"
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

      {levels.length > 0 && (
        <section>
          <h2 className="mb-2 text-sm uppercase tracking-widest text-neutral-500">Structuur</h2>
          <ol className="divide-y divide-neutral-800 overflow-hidden rounded-xl border border-neutral-800">
            {levels.map((l) => (
              <li
                key={l.idx}
                className={`flex items-center justify-between px-4 py-2 text-sm ${
                  l.idx === resolved.levelIdx ? 'bg-neutral-800' : ''
                } ${l.isBreak ? 'text-sky-300' : ''}`}
              >
                <span className="w-16 text-neutral-500">
                  {l.isBreak ? 'Pauze' : `#${l.idx + 1}`}
                </span>
                <span className="flex-1 tabular-nums">{formatBlinds(l)}</span>
                <span className="tabular-nums text-neutral-500">
                  {Math.round(l.durationS / 60)} min
                </span>
              </li>
            ))}
          </ol>
        </section>
      )}
    </Shell>
  )
}

function Shell({ children }: { children: React.ReactNode }) {
  return (
    <main className="mx-auto flex min-h-dvh max-w-3xl flex-col gap-6 bg-neutral-950 p-6 text-white">
      {children}
    </main>
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
          ? 'bg-emerald-600 hover:bg-emerald-500'
          : 'border border-neutral-700 hover:bg-neutral-800'
      }`}
    >
      {children}
    </button>
  )
}

function Tile({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-xl border border-neutral-800 p-4">
      <p className="text-xs uppercase tracking-widest text-neutral-500">{label}</p>
      <p className="mt-1 text-2xl font-semibold tabular-nums">{value}</p>
    </div>
  )
}
