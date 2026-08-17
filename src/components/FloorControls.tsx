'use client'

import { useMemo, useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import {
  resolveClock, formatDuration, formatBlinds, breakLabel,
  start, pause, resume, nextLevel, prevLevel, adjustTime,
  type ClockState,
} from '@/lib/tournament/clock'
import { toClockState } from '@/lib/types'
import { useServerTime, useTicker } from '@/lib/useServerTime'
import { useTournament } from '@/lib/useTournament'
import { useT } from '@/lib/i18n/context'

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
  const t = useT()
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
          ? t('floor.noRights')
          : err.message,
      )
    }
    setBusy(false)
  }

  if (loading) return <Shell><p className="text-[var(--text-muted)]">{t('common.loading')}</p></Shell>
  if (error || !tournament) {
    return <Shell><p className="text-[var(--danger)]">{error ?? t('clock.unknown')}</p></Shell>
  }

  const state = toClockState(tournament)
  const resolved = resolveClock(state, levels, nowMs())
  const running = tournament.clock === 'running'
  const neverStarted = tournament.clock === 'stopped' && !tournament.started_at

  return (
    <Shell>
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
            : `${t('clock.level')} ${resolved.levelIdx + 1} ${t('common.of')} ${levels.length || '—'}`}
        </p>
        <p className="my-2 text-7xl font-bold tabular-nums leading-none">
          {formatDuration(resolved.remainingMs)}
        </p>
        <p className="text-2xl text-[var(--text-muted)]">{formatBlinds(resolved.level)}</p>
        <p className="mt-1 text-sm text-[var(--text-faint)]">
          {resolved.nextLevel ? `${t('clock.next')}: ${formatBlinds(resolved.nextLevel)}` : t('clock.lastLevel')}
        </p>
        {resolved.rolledOver > 0 && running && (
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
          <Button primary disabled={busy} onClick={() => apply(pause(state, nowMs()))}>
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
            onClick={() => apply(adjustTime(state, -60_000, nowMs(), nowIso()))}
          >
            {t('floor.minusMinute')}
          </Button>
          <Button
            disabled={busy}
            onClick={() => apply(adjustTime(state, 60_000, nowMs(), nowIso()))}
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
                  {l.isBreak ? t('clock.break') : `#${l.idx + 1}`}
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

function Shell({ children }: { children: React.ReactNode }) {
  return (
    <main className="mx-auto flex min-h-dvh max-w-3xl flex-col gap-6 bg-[var(--bg)] p-6 text-white">
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
