'use client'

import Link from 'next/link'
import { useEffect, useMemo, useRef, useState } from 'react'
import { FloorPlayers } from '@/components/FloorPlayers'
import { SeatingPanel } from '@/components/SeatingPanel'
import { StructurePanel } from '@/components/StructurePanel'
import type { SheetContext } from '@/components/PlayerSheet'
import { createClient } from '@/lib/supabase/client'
import {
  resolveClock, levelsForClock, formatDuration, formatBlinds, breakLabel, averageStack,
  start, pause, resume, nextLevel, prevLevel, adjustTime, normalise,
  type ClockState,
} from '@/lib/tournament/clock'
import { entryPriceCents, expectedChipsInPlay, toClockState } from '@/lib/types'
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
  const {
    tournament, club, levels: planned, stats, prizes, loading, error, live, reload,
  } = useTournament(tournamentId)
  const { nowMs, nowIso } = useServerTime()
  const [busy, setBusy] = useState(false)
  const [actionError, setActionError] = useState<string | null>(null)
  const t = useT()
  const rolledRef = useRef<number | null>(null)
  useTicker(250)

  /**
   * De klokbalk.
   *
   * De grote klok staat bovenaan, en dat is juist: daar kijk je naar als je
   * het scherm opent. Maar de rest van de avond sta je onderin — bij de
   * spelers, bij de tafels — en dan is "even een minuut bijzetten" een reis
   * naar boven en terug. Op een telefoon is dat een halve meter scrollen met
   * iemand die voor je staat te wachten.
   *
   * Dus: zodra de grote klok uit beeld is, komt er bovenaan een smalle balk
   * met dezelfde knoppen. Eerder niet — twee klokken tegelijk op één scherm
   * is precies het soort dubbel dat ervoor zorgt dat je op de verkeerde drukt.
   */
  const klokRef = useRef<HTMLElement | null>(null)
  const [balkAan, setBalkAan] = useState(false)

  useEffect(() => {
    const el = klokRef.current
    if (!el) return
    const waarnemer = new IntersectionObserver(
      ([stuk]) => setBalkAan(!stuk.isIntersecting),
      // Pas als er echt niets meer van te zien is. Een klok die half in beeld
      // staat lees je nog; dan hoort er geen tweede bij te komen.
      { threshold: 0.2 },
    )
    waarnemer.observe(el)
    return () => waarnemer.disconnect()
  }, [loading])

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

  /**
   * De gemiddelde stapel, in fiches én in big blinds.
   *
   * De vraag die de floor het vaakst krijgt is niet "hoeveel fiches" maar
   * "hoe diep zitten we". 38.500 zegt pas iets als je weet dat de big blind
   * op 1.500 staat; 26 bb zegt het meteen. Vandaar allebei, en het aantal
   * blinds even groot als het aantal fiches in plaats van als voetnoot —
   * anders staat het er wel, maar lees je het niet.
   *
   * Tijdens een break staat de big blind op nul. Dan is er geen verhouding om
   * te tonen en blijft alleen het aantal fiches staan.
   */
  const avg = averageStack(expectedChips, stats.playersLeft)
  const avgBb = resolved.level && resolved.level.bigBlind > 0
    ? avg / resolved.level.bigBlind
    : null

  // Hoeveel tafels er open horen te staan. Nog geen indeling — dat komt —
  // maar wél het getal waar je aan de deur naar kijkt terwijl de zaal
  // volloopt, en het moment waarop je er eentje kan breken.
  const tafels = tournament.seats_per_table > 0
    ? Math.ceil(stats.playersLeft / tournament.seats_per_table)
    : 0

  /**
   * Alles wat het spelerspaneel van deze avond moet weten.
   *
   * Eén keer hier samengesteld en daarna doorgegeven aan de spelerslijst én de
   * tafelweergave. Dat is het punt: het paneel gaat uit twee schermen open, en
   * als elk scherm zijn eigen idee heeft van wat een rebuy kost, dan staat er
   * op de ene tik een ander bedrag dan op de andere.
   */
  const sheetCtx: SheetContext = {
    maxReentries: tournament.max_reentries,
    bountyMode: tournament.bounty_mode,
    startingStack: tournament.starting_stack,
    preregBonusStack: tournament.prereg_bonus_stack,
    currency: club?.currency ?? 'EUR',
    rebuyCents: entryPriceCents(tournament, 'rebuy').total,
    addonCents: entryPriceCents(tournament, 'addon').total,
    prizes,
    playersLeft: stats.playersLeft,
    entriesTotal: stats.entriesTotal,
  }

  return (
    <Shell back={back}>
      {/* Vast bovenaan en niet meescrollend: een knop die wegglijdt terwijl je
          ernaar reikt is erger dan geen knop. Hij ligt onder het
          spelerspaneel (z-30 tegen z-40), zodat hij niet door de waas heen
          prikt wanneer dat openstaat. */}
      <div
        aria-hidden={!balkAan}
        className={`fixed inset-x-0 top-0 z-30 border-b border-[var(--line)] bg-[color-mix(in_oklab,var(--bg)_92%,black)] pt-safe backdrop-blur transition-opacity ${
          balkAan ? 'opacity-100' : 'pointer-events-none opacity-0'
        }`}
      >
        <div className="mx-auto flex max-w-3xl items-center gap-1.5 px-3 py-2 sm:gap-2">
          <span className="tnum shrink-0 text-xl font-bold leading-none">
            {formatDuration(resolved.remainingMs)}
          </span>
          {/* De blinds, niet het levelnummer. Op een telefoon past er één
              ding naast de tijd en vijf knoppen, en de vraag aan tafel is
              altijd "wat zijn de blinds" en nooit "welk level is het". Het
              nummer en de ante komen erbij zodra er plaats is. */}
          <span className="min-w-0 flex-1 truncate text-xs leading-tight text-[var(--text-muted)]">
            {resolved.level?.isBreak ? (
              breakLabel(resolved.level.label, t('clock.break'))
            ) : (
              <>
                <span className="hidden sm:inline">{t('clock.level')} {playIdx} · </span>
                <span className="tnum">
                  {(resolved.level?.smallBlind ?? 0).toLocaleString('nl-BE')}
                  {' / '}
                  {(resolved.level?.bigBlind ?? 0).toLocaleString('nl-BE')}
                </span>
              </>
            )}
          </span>
          <BalkKnop
            label={t('floor.prevLevel')}
            disabled={busy || resolved.levelIdx === 0}
            onClick={() => apply(prevLevel(state, levels, nowMs(), nowIso()))}
          >
            ←
          </BalkKnop>
          <BalkKnop
            label={t('floor.minusMinute')}
            disabled={busy}
            onClick={() => apply(adjustTime(state, levels, -60_000, nowMs(), nowIso()))}
          >
            −1
          </BalkKnop>
          {/* Een teken en geen woord: "Mettre en pause" past niet naast vier
              andere knoppen op een telefoon van 390 pixels, en dit teken staat
              op elke afstandsbediening ter wereld. De naam staat in het
              voorleeslabel. */}
          <BalkKnop
            primair
            label={neverStarted ? t('floor.start') : running ? t('floor.pause') : t('floor.resume')}
            disabled={busy || (neverStarted && levels.length === 0)}
            onClick={() => apply(
              neverStarted ? start(nowIso())
                : running ? pause(state, levels, nowMs())
                  : resume(state, nowIso()),
            )}
          >
            {running ? '❚❚' : '▶'}
          </BalkKnop>
          <BalkKnop
            label={t('floor.plusMinute')}
            disabled={busy}
            onClick={() => apply(adjustTime(state, levels, 60_000, nowMs(), nowIso()))}
          >
            +1
          </BalkKnop>
          <BalkKnop
            label={t('floor.nextLevel')}
            disabled={busy || resolved.levelIdx >= levels.length - 1}
            onClick={() => apply(nextLevel(state, levels, nowMs(), nowIso()))}
          >
            →
          </BalkKnop>
        </div>
      </div>

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

      <section ref={klokRef} className="rounded-2xl bg-[var(--surface)] p-6 text-center">
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
            {t('floor.rolledOver')
              .replace('{n}', String(resolved.rolledOver))
              .replace('{blinds}', resolved.level ? formatBlinds(resolved.level) : '—')}
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

      <section className="grid grid-cols-2 gap-3 text-center sm:grid-cols-4">
        <Tile
          label={t('clock.playersLeft')}
          value={`${stats.playersLeft} / ${stats.entriesTotal}`}
          {...(tafels > 0
            ? { sub: t('floor.tablesNeeded')
                  .replace('{n}', String(tafels))
                  .replace('{m}', String(tournament.seats_per_table)) }
            : {})}
        />
        <Tile
          label={t('clock.avgStack')}
          value={avg.toLocaleString('nl-BE')}
          {...(avgBb !== null ? { sterk: `${formatBb(avgBb)} bb` } : {})}
        />
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

      {/* De tafelindeling, meteen onder de klok. Dit is het hoofdbeeld: wie
          zit waar, wie staat kort, wie moet verhuizen — en vanaf hier open je
          met één tik alles wat je met een speler kan doen. */}
      <SeatingPanel
        tournamentId={tournamentId}
        seatsPerTable={tournament.seats_per_table}
        ctx={sheetCtx}
        bigBlind={resolved.level?.bigBlind ?? 0}
        finished={tournament.status === 'finished' || tournament.status === 'cancelled'}
      />

      {/* Het spelersbeheer, onder de tafels.
          Het stond bovenaan toen er nog geen tafelweergave was. Nu die er is,
          is dát het beeld waar de floor de avond door naar kijkt — hij ziet
          de zaal voor zich en tikt aan wie er voor hem staat. De lijst blijft
          nodig om iemand te zóeken, om in te schrijven en om de kassa bij te
          houden, maar dat zijn handelingen en geen uitzicht. Dus: eronder. */}
      <FloorPlayers
        tournamentId={tournamentId}
        clubId={tournament.club_id}
        ctx={sheetCtx}
        finished={tournament.status === 'finished' || tournament.status === 'cancelled'}
        money={{
          buyinCents: tournament.buyin_cents,
          currency: club?.currency ?? 'EUR',
        }}
        potCents={stats.prizePoolCents}
        entriesClosed={entriesClosed}
        expectedChips={expectedChips}
        countsFrozenAt={tournament.counts_frozen_at}
        clubLocale={club?.locale ?? 'nl'}
      />

      {/* De blindstructuur van deze avond. Aanpasbaar terwijl er gespeeld
          wordt, want een tornooi dat uitloopt heeft meer levels nodig dan er
          bij het aanmaken bedacht zijn. */}
      <StructurePanel
        tournamentId={tournamentId}
        levels={levels}
        currentIdx={resolved.levelIdx}
        playNo={playNo}
        finished={tournament.status === 'finished' || tournament.status === 'cancelled'}
        onChanged={reload}
      />
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

/**
 * Eén knop in de klokbalk.
 *
 * Minstens 40 pixels in het vierkant, ook al staat er maar "−1" op: dat is de
 * ondergrens waarop een duim in een donkere zaal raakt wat hij bedoelt. De
 * naam staat in `aria-label` en in `title`, zodat het teken op het scherm kort
 * kan blijven zonder dat iemand moet raden wat het doet.
 */
function BalkKnop({
  children, label, onClick, disabled, primair,
}: {
  children: React.ReactNode
  label: string
  onClick: () => void
  disabled?: boolean
  primair?: boolean
}) {
  return (
    <button
      type="button"
      aria-label={label}
      title={label}
      onClick={onClick}
      disabled={disabled}
      className={`tnum h-9 min-w-9 shrink-0 rounded-lg px-1.5 text-sm font-medium leading-none transition active:scale-95 disabled:cursor-not-allowed disabled:opacity-35 sm:h-10 sm:min-w-10 sm:px-2 ${
        primair
          ? 'bg-[var(--brand)] text-[var(--on-brand)] hover:brightness-110'
          : 'border border-[var(--line-strong)] hover:bg-[var(--surface-hover)]'
      }`}
    >
      {children}
    </button>
  )
}

/** Onder de tien big blinds is één cijfer na de komma zinvol, daarboven niet. */
function formatBb(v: number): string {
  if (!Number.isFinite(v) || v <= 0) return '0'
  return v < 10 ? v.toFixed(1).replace('.', ',') : String(Math.round(v))
}

function Tile({
  label, value, sub, sterk,
}: {
  label: string
  value: string
  sub?: string
  /**
   * Een tweede getal dat even hard meetelt als het eerste, in de accentkleur.
   * Voor het aantal big blinds onder de gemiddelde stapel: dat is geen
   * voetnoot bij het cijfer maar de vertaling ervan naar de taal waarin aan
   * tafel gedacht wordt.
   */
  sterk?: string
}) {
  return (
    <div className="rounded-xl border border-[var(--line)] p-4">
      <p className="text-xs uppercase tracking-widest text-[var(--text-faint)]">{label}</p>
      <p className="mt-1 text-2xl font-semibold tabular-nums">{value}</p>
      {sterk && (
        <p className="tnum mt-0.5 text-lg font-semibold leading-tight text-[var(--brand)]">
          {sterk}
        </p>
      )}
      {sub && <p className="mt-0.5 text-xs text-[var(--text-faint)]">{sub}</p>}
    </div>
  )
}
