'use client'

import { useCallback, useEffect, useMemo, useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import {
  resolveClock, levelsForClock, formatDuration, averageStack, breakLabel,
  type BlindLevel,
} from '@/lib/tournament/clock'
import { formatMoney } from '@/lib/types'
import { useServerTime, useTicker } from '@/lib/useServerTime'
import { useT } from '@/lib/i18n/context'
import type { PublicClock, PublicLevel, PublicSeat } from '@/lib/publicClub'

/**
 * De avond op je eigen telefoon.
 *
 * Dit is niet de zaalklok in het klein. Op de beamer domineert de tijd omdat
 * je hem van tien meter moet lezen; hier zit je ernaar te kijken van dertig
 * centimeter en wil je iets anders weten — hoeveel man er nog zit, wat er in
 * de pot ligt, en of jouw naam nog in de lijst staat. De tijd staat er dus
 * groot bij, maar de deelnemerslijst is waar de pagina om draait.
 *
 * De klok telt lokaal af met dezelfde functies als de beamer, dus hij loopt
 * vloeiend zonder dat er per seconde iets over het netwerk gaat. Elke acht
 * seconden wordt de stand opnieuw opgehaald: dat is snel genoeg voor een
 * afvaller en zuinig genoeg voor vijftig telefoons op zaalwifi.
 */
export function LiveBoard({
  tournamentId, initialClock, initialLevels, initialSeats, prizes,
}: {
  tournamentId: string
  initialClock: PublicClock
  initialLevels: PublicLevel[]
  initialSeats: PublicSeat[]
  prizes: number[]
}) {
  const supabase = useMemo(() => createClient(), [])
  const t = useT()
  const { nowMs } = useServerTime()
  useTicker(500)

  const [clock, setClock] = useState(initialClock)
  const [seats, setSeats] = useState(initialSeats)
  const [rawLevels, setRawLevels] = useState(initialLevels)

  const refresh = useCallback(async () => {
    const [c, s, l] = await Promise.all([
      supabase.rpc('club_public_clock', { p_tournament_id: tournamentId }),
      supabase.rpc('club_public_seats', { p_tournament_id: tournamentId }),
      supabase.rpc('club_public_levels', { p_tournament_id: tournamentId }),
    ])
    const row = ((c.data ?? []) as unknown as PublicClock[])[0]
    if (row) setClock(row)
    if (s.data) setSeats(s.data as unknown as PublicSeat[])
    if (l.data) setRawLevels(l.data as unknown as PublicLevel[])
  }, [supabase, tournamentId])

  useEffect(() => {
    const id = setInterval(() => void refresh(), 8_000)
    // Terug uit de achtergrond? Meteen bijwerken in plaats van tot acht
    // seconden naar een oude stand kijken.
    const onVisible = () => { if (!document.hidden) void refresh() }
    document.addEventListener('visibilitychange', onVisible)
    return () => {
      clearInterval(id)
      document.removeEventListener('visibilitychange', onVisible)
    }
  }, [refresh])

  const levels: BlindLevel[] = rawLevels.map((l) => ({
    idx: l.idx,
    isBreak: l.is_break,
    label: l.label,
    smallBlind: l.small_blind,
    bigBlind: l.big_blind,
    ante: l.ante,
    durationS: l.duration_s,
  }))

  const state = {
    status: clock.clock,
    levelIdx: clock.level_idx,
    levelStartedAt: clock.level_started_at,
    levelElapsedMs: Number(clock.level_elapsed_ms ?? 0),
  }

  const all = levelsForClock(levels, state, nowMs())
  const resolved = resolveClock(state, all, nowMs())
  const level = resolved.level
  const isBreak = level?.isBreak ?? false
  const running = clock.clock === 'running'
  const done = clock.status === 'finished' || clock.status === 'cancelled'

  const playLevels = all.filter((l) => !l.isBreak).length
  const playIdx = all.slice(0, resolved.levelIdx + 1).filter((l) => !l.isBreak).length

  const inPlay = (clock.entries + clock.rebuys) * clock.starting_stack
    + clock.addons * (clock.addon_stack ?? clock.starting_stack)
  const avg = averageStack(inPlay, clock.players_left)
  const bb = level && !level.isBreak ? level.bigBlind : (resolved.nextLevel?.bigBlind ?? 0)

  const still = seats.filter((s) => s.status === 'active' || s.status === 'registered')
  const out = seats.filter((s) => s.status !== 'active' && s.status !== 'registered')

  return (
    <div className="space-y-4">
      {/* ------------------------------------------------------------ klok */}
      <section className="rounded-2xl border border-[var(--line)] bg-[var(--surface)] p-5 text-center">
        <p className="text-xs uppercase tracking-[0.2em] text-[var(--text-faint)]">
          {done
            ? t('status.finished')
            : isBreak
              ? breakLabel(level?.label, t('clock.break'))
              : `${t('clock.level')} ${playIdx} ${t('common.of')} ${playLevels}`}
        </p>

        <p className="tnum my-1 text-6xl font-bold leading-none">
          {done ? '—' : formatDuration(resolved.remainingMs)}
        </p>

        {!done && (
          <>
            <p className="text-2xl font-semibold">
              {isBreak
                ? breakLabel(level?.label, t('clock.break'))
                : `${(level?.smallBlind ?? 0).toLocaleString('nl-BE')} / ${(level?.bigBlind ?? 0).toLocaleString('nl-BE')}`}
              {!isBreak && (level?.ante ?? 0) > 0 && (
                <span className="text-base font-normal text-[var(--text-muted)]">
                  {' '}(ante {(level?.ante ?? 0).toLocaleString('nl-BE')})
                </span>
              )}
            </p>
            <p className="mt-1 text-sm text-[var(--text-faint)]">
              {resolved.nextLevel
                ? resolved.nextLevel.isBreak
                  ? `${t('clock.next')} — ${breakLabel(resolved.nextLevel.label, t('clock.break'))}`
                  : `${t('clock.next')} — ${resolved.nextLevel.smallBlind.toLocaleString('nl-BE')} / ${resolved.nextLevel.bigBlind.toLocaleString('nl-BE')}`
                : t('clock.lastLevel')}
            </p>
          </>
        )}

        {!running && !done && (
          <p className="mt-3 inline-block rounded-full border border-[#fbbf2455] bg-[#fbbf2414] px-3 py-1 text-xs font-semibold uppercase tracking-[0.16em] text-[#fbbf24]">
            {clock.clock === 'paused' ? t('clock.pausedBanner') : t('clock.notStarted')}
          </p>
        )}
      </section>

      {/* ---------------------------------------------------------- cijfers */}
      <section className="grid grid-cols-2 gap-3">
        <Tile
          label={t('clock.playersLeft')}
          value={`${clock.players_left}`}
          sub={`${t('common.of')} ${clock.entries}`}
        />
        <Tile
          label={t('clock.prizePool')}
          value={formatMoney(clock.prize_pool_cents, clock.currency)}
        />
        <Tile
          label={t('clock.avgStack')}
          value={avg.toLocaleString('nl-BE')}
          sub={bb > 0 ? `${Math.round(avg / bb)} bb` : undefined}
        />
        <Tile label={t('pub.rebuys')} value={`${clock.rebuys}`} />
      </section>

      {/* --------------------------------------------------- prijzenladder */}
      {prizes.length > 0 && (
        <section className="rounded-2xl border border-[var(--line)] bg-[var(--surface)] p-4">
          <h2 className="text-xs uppercase tracking-[0.2em] text-[var(--text-faint)]">
            {t('payout.title')}
          </h2>
          <ul className="mt-2 divide-y divide-[var(--line)]">
            {prizes.map((cents, i) => (
              <li key={i} className="flex items-baseline justify-between py-1.5">
                <span className="text-sm text-[var(--text-muted)]">{i + 1}</span>
                <span className="tnum font-semibold">{formatMoney(cents, clock.currency)}</span>
              </li>
            ))}
          </ul>
        </section>
      )}

      {/* -------------------------------------------------------- de tafel */}
      <section className="rounded-2xl border border-[var(--line)] bg-[var(--surface)] p-4">
        <h2 className="text-xs uppercase tracking-[0.2em] text-[var(--text-faint)]">
          {t('pub.stillIn')} · {still.length}
        </h2>
        {still.length === 0 ? (
          <p className="mt-2 text-sm text-[var(--text-muted)]">{t('pub.nobodyLeft')}</p>
        ) : (
          <ul className="mt-2 divide-y divide-[var(--line)]">
            {still.map((s, i) => (
              <li key={i} className="flex items-baseline justify-between gap-3 py-2">
                <span className="min-w-0 truncate">{s.player_name}</span>
                {(s.chip_count ?? 0) > 0 && (
                  <span className="tnum shrink-0 text-sm text-[var(--text-faint)]">
                    {(s.chip_count ?? 0).toLocaleString('nl-BE')}
                  </span>
                )}
              </li>
            ))}
          </ul>
        )}

        {out.length > 0 && (
          <>
            <h2 className="mt-5 text-xs uppercase tracking-[0.2em] text-[var(--text-faint)]">
              {t('pub.out')}
            </h2>
            <ul className="mt-2 divide-y divide-[var(--line)]">
              {out.map((s, i) => (
                <li key={i} className="flex items-baseline justify-between gap-3 py-2 text-[var(--text-muted)]">
                  <span className="min-w-0 truncate">{s.player_name}</span>
                  {s.finish_position !== null && (
                    <span className="tnum shrink-0 text-sm">{s.finish_position}e</span>
                  )}
                </li>
              ))}
            </ul>
          </>
        )}
      </section>
    </div>
  )
}

function Tile({ label, value, sub }: { label: string; value: string; sub?: string }) {
  return (
    <div className="rounded-2xl border border-[var(--line)] bg-[var(--surface)] p-4">
      <p className="text-[0.65rem] uppercase tracking-[0.18em] text-[var(--text-faint)]">{label}</p>
      <p className="tnum mt-1 text-2xl font-semibold leading-tight">{value}</p>
      {sub && <p className="text-xs text-[var(--text-faint)]">{sub}</p>}
    </div>
  )
}
