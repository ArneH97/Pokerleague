'use client'

import { useCallback, useEffect, useMemo, useState } from 'react'
import { PokerTable } from '@/components/PokerTable'
import { PlayerSheet, type SheetContext, type SheetPlayer } from '@/components/PlayerSheet'
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
 *
 * 4. **Een stoel aantikken opent de speler.** Dat is de kortste weg van "wie
 *    zit daar" naar "doe iets met hem": rebuy, addon, verzetten, uitschakelen.
 *    Verzetten begint dus in het paneel en niet met een tik op de stoel —
 *    anders betekent dezelfde tik twee dingen, en dan pak je iemand op terwijl
 *    je zijn stapel wilde bijstellen.
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

interface SpelerRij {
  id: string
  status: string
  chip_count: number | null
  finish_position: number | null
  table_no: number | null
  seat_no: number | null
  reentries_used: number
  rebuys_used: number
  bounties_won: number
  prereg_bonus: number
  chip_count_by: string | null
  chip_count_updated_at: string | null
  players: { display_name: string; email: string | null } | null
}

/**
 * Wat de databank van de indeling vindt.
 *
 * `moves` komt nog mee uit `seating_proposal` maar wordt niet meer gebruikt:
 * sinds het verzetten helemaal bij de floor ligt, is alleen `kind` en de
 * tafel die opgebroken kan worden nog van belang. Het veld blijft in de vorm
 * staan omdat de functie het nu eenmaal teruggeeft.
 */
interface Proposal {
  kind: 'none' | 'balance' | 'break'
  break_table?: number
  moves: unknown[]
}

interface Tafel {
  no: number
  seats: number
  isOpen: boolean
  stoelen: PlanRow[]
}

export function SeatingPanel({
  tournamentId, seatsPerTable, finished, ctx, bigBlind = 0,
}: {
  tournamentId: string
  seatsPerTable: number
  finished: boolean
  /** Wat het spelerspaneel van deze avond moet weten; zie PlayerSheet. */
  ctx: SheetContext
  /** Om stapels ook in blinds te tonen. Nul laat ze weg. */
  bigBlind?: number
}) {
  const supabase = useMemo(() => createClient(), [])
  const t = useT()

  const [plan, setPlan] = useState<PlanRow[]>([])
  const [voorstel, setVoorstel] = useState<Proposal | null>(null)
  /**
   * De deelnemers die nog meespelen, met alles wat het paneel nodig heeft.
   *
   * Ruimer dan wat deze lijst strikt vraagt — hij toont alleen wie nog geen
   * stoel heeft — maar het scheelt een tweede rondje naar de server op het
   * moment dat de floor een stoel aantikt. Een paneel dat een tiende seconde
   * leeg opengaat, voelt stuk.
   */
  const [mee, setMee] = useState<SheetPlayer[]>([])
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [open, setOpen] = useState(true)
  /** Wie er opgepakt is en op de volgende stoel gaat die je aantikt. */
  const [opgepakt, setOpgepakt] = useState<{ id: string; name: string } | null>(null)
  /** Welke tafel in beeld staat. */
  const [tafelNo, setTafelNo] = useState(1)
  /** Wiens paneel open staat. Alleen het id; de rest komt uit de verse lijst. */
  const [sheetId, setSheetId] = useState<string | null>(null)

  const load = useCallback(async () => {
    const [planRes, voorRes, zonderRes] = await Promise.all([
      supabase.rpc('seating_plan', { p_tournament_id: tournamentId }),
      supabase.rpc('seating_proposal', { p_tournament_id: tournamentId }),
      supabase
        .from('tournament_players')
        .select('id,status,chip_count,finish_position,table_no,seat_no,reentries_used,rebuys_used,bounties_won,prereg_bonus,chip_count_by,chip_count_updated_at,players(display_name,email)')
        .eq('tournament_id', tournamentId)
        .in('status', ['active', 'registered'])
        .overrideTypes<SpelerRij[]>(),
    ])
    setPlan((planRes.data ?? []) as unknown as PlanRow[])
    setVoorstel((voorRes.data ?? null) as unknown as Proposal | null)
    setMee((zonderRes.data ?? []).map((r) => ({
      id: r.id,
      name: r.players?.display_name ?? '—',
      status: r.status,
      chipCount: r.chip_count,
      finishPosition: r.finish_position,
      tableNo: r.table_no,
      seatNo: r.seat_no,
      reentriesUsed: r.reentries_used,
      rebuysUsed: r.rebuys_used,
      bountiesWon: r.bounties_won,
      preregBonus: r.prereg_bonus ?? 0,
      email: r.players?.email ?? null,
      chipCountBy: r.chip_count_by,
      chipCountAt: r.chip_count_updated_at,
    })))
  }, [supabase, tournamentId])

  const zonderStoel = mee.filter((p) => p.tableNo === null)

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

  // Welke tafel je op dit moment ziet. Hij volgt het vegen; de puntjes
  // boven de tafel zetten hem.
  const huidig = tafels.find((x) => x.no === tafelNo) ?? tafels[0]

  // De grootste stapel van het hele veld, niet van deze tafel: wie aan de
  // leiding staat, staat aan de leiding waar hij ook zit.
  const leiderId = plan.reduce<{ id: string | null; chips: number }>((a, r) => (
    r.tournament_player_id !== null && (r.chip_count ?? 0) > a.chips
      ? { id: r.tournament_player_id, chips: r.chip_count ?? 0 }
      : a
  ), { id: null, chips: -1 }).id

  /**
   * Naar een andere tafel.
   *
   * Vegen werkt op een telefoon en nergens anders. Aan de floor staat ook een
   * laptop, en daar is er geen gebaar om mee te wisselen — dan blijven alleen
   * de puntjes over, en die zijn vijf pixels hoog. Vandaar twee pijlen die
   * altijd staan: op een muis is dat de hele bediening, op een duim een extra.
   */
  function naarTafel(index: number) {
    const el = document.getElementById(`tafelstrook-${tournamentId}`)
    if (!el) return
    const i = Math.min(Math.max(index, 0), Math.max(tafels.length - 1, 0))
    el.scrollTo({ left: i * el.clientWidth, behavior: 'smooth' })
  }

  async function zetNeer(tableNo: number, seatNo: number) {
    if (!opgepakt) return
    const wie = opgepakt
    setOpgepakt(null)
    await run(() => supabase.rpc('floor_seat_player', {
      p_tournament_player_id: wie.id, p_table_no: tableNo, p_seat_no: seatNo,
    }))
  }

  const hier = Math.max(0, tafels.findIndex((x) => x.no === (huidig?.no ?? 1)))

  const sheetPlayer = sheetId === null ? null : mee.find((p) => p.id === sheetId) ?? null

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

  // De databank rekent nog steeds uit of het scheef staat; we gebruiken dat
  // alleen niet meer om iemand te verzetten.
  const heeftMelding = voorstel !== null && voorstel.kind !== 'none'

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

      {/* Een melding, geen voorstel.
          Hier stond een lijstje "deze man van tafel 1 naar tafel 2" met een
          knop eronder die het uitvoerde. Dat las handig en was het niet: één
          tik verzette iemand die net de big blind betaald had, en dat merk je
          pas als hij aan de andere tafel meteen weer moet betalen. Zo'n
          beslissing hoort bij de floor, die de hand ziet en de knoppen kent.
          Wat de databank wél goed kan is tellen — dus dat is wat er staat:
          waar het scheef zit en hoeveel. Wie er verhuist, kies jij. */}
      {heeftMelding && (
        <div className="rounded-lg border border-[color-mix(in_oklab,var(--warn)_35%,transparent)] bg-[color-mix(in_oklab,var(--warn)_8%,transparent)] p-3">
          <p className="text-sm font-medium text-[var(--warn)]">
            {voorstel.kind === 'break'
              ? t('seat.proposeBreak').replace('{n}', String(voorstel.break_table ?? ''))
              : t('seat.proposeBalance')}
          </p>
          {/* De bezetting per tafel. Eén regel die zegt waar het scheef zit,
              in plaats van drie regels die zeggen wie er moet lopen. */}
          <p className="tnum mt-1.5 flex flex-wrap gap-x-3 gap-y-1 text-xs text-[var(--text-muted)]">
            {tafels.filter((x) => x.isOpen).map((x) => (
              <span key={x.no}>
                {t('seat.table')} {x.no}:{' '}
                {x.stoelen.filter((y) => y.tournament_player_id !== null).length}
              </span>
            ))}
          </p>
          <p className="mt-2 text-xs leading-relaxed text-[var(--text-faint)]">
            {t('seat.youDecide')}
          </p>
          <div className="mt-2.5">
            <Klein onClick={() => setVoorstel({ kind: 'none', moves: [] })} disabled={busy}>
              {t('seat.ignore')}
            </Klein>
          </div>
        </div>
      )}

      {/* De tafels, elk op volle breedte en met vegen ertussen.
          Eén tafel per scherm in plaats van drie lijstjes onder elkaar: zo
          blijft elke stoel groot genoeg om met een duim te raken, ook met
          tien stoelen aan tafel. */}
      {tafels.length === 0 ? (
        <p className="text-sm text-[var(--text-muted)]">{t('seat.noTables')}</p>
      ) : (
        <>
          <div className="flex items-center gap-2">
            <p className="text-sm font-medium">
              {t('seat.table')} {huidig?.no ?? 1}
              <span className="tnum ml-2 text-xs font-normal text-[var(--text-faint)]">
                {huidig ? huidig.stoelen.filter((x) => x.tournament_player_id !== null).length : 0}
                {' / '}{huidig?.seats ?? seatsPerTable}
                {huidig && !huidig.isOpen && ` · ${t('seat.closed')}`}
              </span>
            </p>
            {huidig && huidig.isOpen
              && huidig.stoelen.every((x) => x.tournament_player_id === null) && (
              <Klein
                onClick={() => void run(() => supabase.rpc('floor_close_table', {
                  p_tournament_id: tournamentId, p_table_no: huidig.no,
                }))}
                disabled={busy}
              >
                {t('seat.closeTable')}
              </Klein>
            )}
            {tafels.length > 1 && (
              <div className="ml-auto flex items-center gap-1.5">
                <Pijl
                  label={t('seat.prevTable')}
                  disabled={hier <= 0}
                  onClick={() => naarTafel(hier - 1)}
                >
                  ←
                </Pijl>
                {tafels.map((x, i) => (
                  <button
                    key={x.no}
                    type="button"
                    aria-current={x.no === (huidig?.no ?? 1) ? 'true' : 'false'}
                    aria-label={`${t('seat.table')} ${x.no}`}
                    onClick={() => naarTafel(i)}
                    className={`h-1.5 w-5 rounded-full transition ${
                      x.no === (huidig?.no ?? 1) ? 'bg-[var(--brand)]' : 'bg-[var(--line-strong)]'
                    }`}
                  />
                ))}
                <Pijl
                  label={t('seat.nextTable')}
                  disabled={hier >= tafels.length - 1}
                  onClick={() => naarTafel(hier + 1)}
                >
                  →
                </Pijl>
              </div>
            )}
          </div>

          <div
            id={`tafelstrook-${tournamentId}`}
            onScroll={(e) => {
              const el = e.currentTarget
              const i = Math.round(el.scrollLeft / el.clientWidth)
              const volgende = tafels[Math.min(Math.max(i, 0), tafels.length - 1)]
              if (volgende && volgende.no !== tafelNo) setTafelNo(volgende.no)
            }}
            className="-mx-1 flex snap-x snap-mandatory overflow-x-auto [scrollbar-width:none] [&::-webkit-scrollbar]:hidden"
          >
            {tafels.map((tafel) => (
              <div
                key={tafel.no}
                className={`flex w-full shrink-0 snap-center flex-col px-1 ${
                  tafel.isOpen ? '' : 'opacity-45'
                }`}
              >
                <PokerTable
                  seats={tafel.stoelen.map((x) => ({
                    seatNo: x.seat_no,
                    tournamentPlayerId: x.tournament_player_id,
                    name: x.display_name,
                    chipCount: x.chip_count,
                  }))}
                  pickedId={opgepakt?.id ?? null}
                  bigBlind={bigBlind}
                  leaderId={leiderId}
                  disabled={busy || !tafel.isOpen}
                  labelFree={t('seat.free')}
                  placeHere={t('seat.placeHere')}
                  onSeat={(seatNo, tpId) => {
                    // Heb je iemand op de hand, dan is elke tik een zetje.
                    // Anders opent de stoel de speler die erop zit.
                    if (opgepakt) return void zetNeer(tafel.no, seatNo)
                    if (tpId) setSheetId(tpId)
                  }}
                />
              </div>
            ))}
          </div>
        </>
      )}

      <p className="text-xs leading-relaxed text-[var(--text-faint)]">
        {opgepakt
          ? t('seat.pickedUp').replace('{n}', opgepakt.name)
          : t('seat.hint').replace('{n}', String(seatsPerTable))}
      </p>

      {/* Hetzelfde paneel als in de spelerslijst. Het doet zijn eigen
          aanroepen, dus deze weergave hoeft niets te weten van rebuys of
          uitbetalingen — alleen wanneer ze opnieuw moet laden. */}
      {sheetPlayer && (
        <PlayerSheet
          player={sheetPlayer}
          ctx={ctx}
          others={mee.filter((o) => o.id !== sheetPlayer.id && o.status !== 'eliminated')
            .map((o) => ({ id: o.id, name: o.name }))}
          onClose={() => setSheetId(null)}
          onChanged={load}
          onMove={(id, name) => setOpgepakt({ id, name })}
        />
      )}
    </section>
  )
}

/** Een pijl naast de puntjes. Groot genoeg voor een duim, klein genoeg om
 *  niet met de tafelnaam te concurreren. */
function Pijl({
  children, label, onClick, disabled,
}: { children: React.ReactNode; label: string; onClick: () => void; disabled?: boolean }) {
  return (
    <button
      type="button"
      aria-label={label}
      title={label}
      onClick={onClick}
      disabled={disabled}
      className="size-8 shrink-0 rounded-lg border border-[var(--line-strong)] text-sm leading-none transition active:scale-95 hover:bg-[var(--surface-hover)] disabled:cursor-not-allowed disabled:opacity-30"
    >
      {children}
    </button>
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
