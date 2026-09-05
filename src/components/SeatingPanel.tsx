'use client'

import { useCallback, useEffect, useMemo, useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { useT } from '@/lib/i18n/context'
import { dbMessage } from '@/lib/dbMessage'

/**
 * De tafelindeling aan de floor.
 *
 * Drie dingen, in deze volgorde van belang:
 *
 * 1. **Zien wie waar zit.** Een raster per tafel, stoel voor stoel. Dat is wat
 *    je nodig hebt als iemand vraagt waar hij moet gaan zitten, en het is het
 *    enige wat ook klopt als de zaal iets anders doet dan het scherm denkt.
 * 2. **Een voorstel, dat je bevestigt.** De databank rekent uit wie er zou
 *    moeten verhuizen; hier staat het als lijstje met een knop eronder. Tot je
 *    erop drukt beweegt er niemand.
 * 3. **Alles overschrijven.** Tik een speler aan, tik een stoel aan, en hij
 *    zit daar. Is die stoel bezet, dan wisselen de twee. Er is geen stand
 *    waarin het scherm zegt "dat mag niet omdat het voorstel iets anders zei":
 *    het voorstel is een rekenhulp, de floor beslist.
 *
 * Twee tikken in plaats van slepen, met opzet. Slepen op een telefoon in een
 * volle zaal is een gok; twee keer tikken werkt met één hand en met een
 * scherm dat je half ziet.
 */

interface PlanRow {
  table_no: number
  seats: number
  is_open: boolean
  seat_no: number
  tournament_player_id: string | null
  display_name: string | null
  chip_count: number | null
}

interface Move {
  tournament_player_id: string
  name: string
  from_table: number | null
  from_seat: number | null
  to_table: number
  to_seat: number
}

interface Proposal {
  kind: 'none' | 'balance' | 'break'
  break_table?: number
  moves: Move[]
}

interface Tafel {
  no: number
  seats: number
  isOpen: boolean
  stoelen: PlanRow[]
}

export function SeatingPanel({
  tournamentId, seatsPerTable, finished,
}: {
  tournamentId: string
  seatsPerTable: number
  finished: boolean
}) {
  const supabase = useMemo(() => createClient(), [])
  const t = useT()

  const [plan, setPlan] = useState<PlanRow[]>([])
  const [voorstel, setVoorstel] = useState<Proposal | null>(null)
  const [zonderStoel, setZonderStoel] = useState<{ id: string; name: string }[]>([])
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [open, setOpen] = useState(false)
  /** Wie er opgepakt is en op de volgende stoel gaat die je aantikt. */
  const [opgepakt, setOpgepakt] = useState<{ id: string; name: string } | null>(null)

  const load = useCallback(async () => {
    const [planRes, voorRes, zonderRes] = await Promise.all([
      supabase.rpc('seating_plan', { p_tournament_id: tournamentId }),
      supabase.rpc('seating_proposal', { p_tournament_id: tournamentId }),
      supabase
        .from('tournament_players')
        .select('id,players(display_name)')
        .eq('tournament_id', tournamentId)
        .is('table_no', null)
        .in('status', ['active', 'registered'])
        .overrideTypes<{ id: string; players: { display_name: string } | null }[]>(),
    ])
    setPlan((planRes.data ?? []) as unknown as PlanRow[])
    setVoorstel((voorRes.data ?? null) as unknown as Proposal | null)
    setZonderStoel(
      (zonderRes.data ?? []).map((r) => ({ id: r.id, name: r.players?.display_name ?? '—' })),
    )
  }, [supabase, tournamentId])

  useEffect(() => {
    if (!open) return
    // eslint-disable-next-line react-hooks/set-state-in-effect
    void load()
    const id = setInterval(() => void load(), 15_000)
    return () => clearInterval(id)
  }, [open, load])

  async function run(fn: () => PromiseLike<{ error: { message: string } | null }>) {
    setBusy(true)
    setError(null)
    const { error: err } = await fn()
    if (err) setError(dbMessage(err, t))
    await load()
    setBusy(false)
  }

  const tafels: Tafel[] = []
  for (const r of plan) {
    let tafel = tafels.find((x) => x.no === r.table_no)
    if (!tafel) {
      tafel = { no: r.table_no, seats: r.seats, isOpen: r.is_open, stoelen: [] }
      tafels.push(tafel)
    }
    tafel.stoelen.push(r)
  }

  async function zetNeer(tableNo: number, seatNo: number) {
    if (!opgepakt) return
    const wie = opgepakt
    setOpgepakt(null)
    await run(() => supabase.rpc('floor_seat_player', {
      p_tournament_player_id: wie.id, p_table_no: tableNo, p_seat_no: seatNo,
    }))
  }

  if (finished) return null

  if (!open) {
    return (
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="w-full rounded-xl border border-[var(--line-strong)] px-4 py-3 text-sm font-medium transition hover:bg-[var(--surface-hover)]"
      >
        {t('seat.open')}
      </button>
    )
  }

  const heeftVoorstel = voorstel !== null && voorstel.kind !== 'none' && voorstel.moves.length > 0

  return (
    <section className="space-y-3 rounded-xl border border-[var(--line)] p-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h2 className="text-sm uppercase tracking-widest text-[var(--text-faint)]">
          {t('seat.title')}
        </h2>
        <div className="flex flex-wrap items-center gap-2">
          <Klein onClick={() => void run(() => supabase.rpc('floor_autoseat', { p_tournament_id: tournamentId }))} disabled={busy}>
            {t('seat.autoseat')}
          </Klein>
          <Klein onClick={() => void run(() => supabase.rpc('floor_open_table', { p_tournament_id: tournamentId }))} disabled={busy}>
            {t('seat.openTable')}
          </Klein>
          <Klein onClick={() => setOpen(false)} disabled={busy}>{t('players.close')}</Klein>
        </div>
      </div>

      {error && (
        <p className="rounded-lg border border-[color-mix(in_oklab,var(--danger)_35%,transparent)] bg-[color-mix(in_oklab,var(--danger)_10%,transparent)] p-2.5 text-sm text-[var(--danger)]">
          {error}
        </p>
      )}

      {/* Wie nog geen plaats heeft. Tik iemand aan en daarna een stoel. */}
      {zonderStoel.length > 0 && (
        <div className="rounded-lg bg-[var(--surface-2)] p-3">
          <p className="mb-2 text-xs uppercase tracking-widest text-[var(--text-faint)]">
            {t('seat.unseated')}
          </p>
          <div className="flex flex-wrap gap-1.5">
            {zonderStoel.map((p) => (
              <button
                key={p.id}
                type="button"
                onClick={() => setOpgepakt(opgepakt?.id === p.id ? null : p)}
                className={`rounded-lg px-2.5 py-1.5 text-sm transition ${
                  opgepakt?.id === p.id
                    ? 'bg-[var(--brand)] text-[var(--on-brand)]'
                    : 'border border-[var(--line-strong)] hover:bg-[var(--surface-hover)]'
                }`}
              >
                {p.name}
              </button>
            ))}
          </div>
        </div>
      )}

      {/* Het voorstel. Nooit uitgevoerd zonder dat je hier drukt, en je kan
          het altijd links laten liggen en zelf iemand verzetten. */}
      {heeftVoorstel && (
        <div className="rounded-lg border border-[color-mix(in_oklab,var(--warn)_35%,transparent)] bg-[color-mix(in_oklab,var(--warn)_8%,transparent)] p-3">
          <p className="text-sm font-medium text-[var(--warn)]">
            {voorstel.kind === 'break'
              ? t('seat.proposeBreak').replace('{n}', String(voorstel.break_table ?? ''))
              : t('seat.proposeBalance')}
          </p>
          <ul className="mt-2 space-y-1 text-xs text-[var(--text-muted)]">
            {voorstel.moves.map((m) => (
              <li key={m.tournament_player_id} className="tnum">
                {m.name} · {t('seat.from')} {m.from_table}
                {m.from_seat !== null ? `.${m.from_seat}` : ''} → {t('seat.to')} {m.to_table}.{m.to_seat}
              </li>
            ))}
          </ul>
          <div className="mt-3 flex flex-wrap gap-2">
            <button
              type="button"
              disabled={busy}
              onClick={() => void run(() => supabase.rpc('floor_apply_moves', {
                p_tournament_id: tournamentId, p_moves: voorstel.moves,
              }))}
              className="rounded-lg bg-[var(--brand)] px-4 py-2 text-sm font-medium text-[var(--on-brand)] transition hover:brightness-110 disabled:opacity-40"
            >
              {t('seat.apply')}
            </button>
            <Klein onClick={() => setVoorstel({ kind: 'none', moves: [] })} disabled={busy}>
              {t('seat.ignore')}
            </Klein>
          </div>
          <p className="mt-2 text-xs text-[var(--text-faint)]">{t('seat.overrideHint')}</p>
        </div>
      )}

      {/* De tafels. */}
      {tafels.length === 0 ? (
        <p className="text-sm text-[var(--text-muted)]">{t('seat.noTables')}</p>
      ) : (
        <div className="space-y-3">
          {tafels.map((tafel) => {
            const bezet = tafel.stoelen.filter((s) => s.tournament_player_id !== null).length
            return (
              <div key={tafel.no} className={tafel.isOpen ? '' : 'opacity-45'}>
                <div className="mb-1.5 flex items-center justify-between gap-2">
                  <p className="text-sm font-medium">
                    {t('seat.table')} {tafel.no}
                    <span className="ml-2 text-xs font-normal text-[var(--text-faint)]">
                      {bezet} / {tafel.seats}
                      {!tafel.isOpen && ` · ${t('seat.closed')}`}
                    </span>
                  </p>
                  {tafel.isOpen && bezet === 0 && (
                    <Klein
                      onClick={() => void run(() => supabase.rpc('floor_close_table', {
                        p_tournament_id: tournamentId, p_table_no: tafel.no,
                      }))}
                      disabled={busy}
                    >
                      {t('seat.closeTable')}
                    </Klein>
                  )}
                </div>

                {/* Eén kolom op een telefoon. Twee kolommen paste er wel op,
                    maar kapte elke naam af tot "Jean-B…" — en de naam is net
                    waar je op zoekt als iemand vraagt waar hij moet zitten. */}
                <div className="grid grid-cols-1 gap-1.5 sm:grid-cols-2 lg:grid-cols-3">
                  {tafel.stoelen.map((s) => {
                    const leeg = s.tournament_player_id === null
                    const dezeOpgepakt = opgepakt?.id === s.tournament_player_id
                    return (
                      <button
                        key={s.seat_no}
                        type="button"
                        disabled={busy || !tafel.isOpen}
                        onClick={() => {
                          if (opgepakt) return void zetNeer(tafel.no, s.seat_no)
                          if (!leeg) {
                            setOpgepakt({
                              id: s.tournament_player_id as string,
                              name: s.display_name ?? '—',
                            })
                          }
                        }}
                        className={`flex min-w-0 items-center gap-2 rounded-lg border px-2.5 py-2 text-left text-sm transition disabled:opacity-40 ${
                          dezeOpgepakt
                            ? 'border-[var(--brand)] bg-[color-mix(in_oklab,var(--brand)_18%,transparent)]'
                            : leeg
                              ? 'border-dashed border-[var(--line)] text-[var(--text-faint)] hover:bg-[var(--surface-hover)]'
                              : 'border-[var(--line-strong)] hover:bg-[var(--surface-hover)]'
                        }`}
                      >
                        <span className="tnum w-5 shrink-0 text-xs text-[var(--text-faint)]">
                          {s.seat_no}
                        </span>
                        <span className="min-w-0 flex-1 truncate">
                          {leeg ? (opgepakt ? t('seat.placeHere') : t('seat.free')) : s.display_name}
                        </span>
                        {!leeg && s.chip_count !== null && (
                          <span className="tnum shrink-0 text-xs text-[var(--text-faint)]">
                            {s.chip_count.toLocaleString('nl-BE')}
                          </span>
                        )}
                      </button>
                    )
                  })}
                </div>
              </div>
            )
          })}
        </div>
      )}

      <p className="text-xs leading-relaxed text-[var(--text-faint)]">
        {opgepakt
          ? t('seat.pickedUp').replace('{n}', opgepakt.name)
          : t('seat.hint').replace('{n}', String(seatsPerTable))}
      </p>
    </section>
  )
}

function Klein({
  children, onClick, disabled,
}: { children: React.ReactNode; onClick?: () => void; disabled?: boolean }) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      className="rounded-lg border border-[var(--line-strong)] px-2.5 py-1.5 text-sm transition hover:bg-[var(--surface-hover)] disabled:cursor-not-allowed disabled:opacity-40"
    >
      {children}
    </button>
  )
}
