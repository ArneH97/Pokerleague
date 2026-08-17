'use client'

import { useEffect, useRef } from 'react'
import { resolveClock, formatDuration, averageStack, breakLabel } from '@/lib/tournament/clock'
import { expectedChipsInPlay, formatMoney, toClockState } from '@/lib/types'
import { useClockSound } from '@/lib/useClockSound'
import { useServerTime, useTicker } from '@/lib/useServerTime'
import { useTournament } from '@/lib/useTournament'
import { FullscreenButton } from '@/components/FullscreenButton'
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
  const { tournament, club, levels, stats, loading, error, live, deal, prizes } = useTournament(tournamentId)
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
  const lastCallRef = useRef<number | null>(null)

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

  // Vijf minuten voor het einde van het laatste level waarop je nog kan
  // inkopen: één keer omroepen. Daarna weet de zaal het, en een tweede keer
  // is alleen maar storend — vandaar de ref die per level onthoudt of het al
  // gezegd is. Blijft de klok even stilstaan en loopt hij weer verder, dan
  // komt de melding niet opnieuw.
  useEffect(() => {
    if (!running || !tournament || !resolved?.level || resolved.level.isBreak) return
    if (tournament.late_reg_level === null) return
    if (secondsLeft > 300 || secondsLeft <= 0) return
    if (lastCallRef.current === levelIdx) return

    // De floor typt "late reg t/m level 6" in als gewoon levelnummer, dus we
    // tellen de speellevels en niet de index — die telt de pauzes mee.
    const playNo = levels.slice(0, levelIdx + 1).filter((l) => !l.isBreak).length
    if (playNo !== tournament.late_reg_level) return

    lastCallRef.current = levelIdx
    sound.playAttention()
    sound.say(t('clock.lastCallSpoken'))
  }, [running, tournament, resolved?.level, secondsLeft, levelIdx, levels, sound, t])

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

  // Gemiddelde stack = chips in spel gedeeld door wie er nog zit. Niet de
  // som van de doorgegeven chipcounts: die zijn onvolledig, en dan zou dit
  // cijfer de hele avond blijven hangen op de startstack in plaats van te
  // stijgen naarmate er spelers afvallen.
  const inPlay = expectedChipsInPlay(tournament, stats)
  const avg = inPlay > 0
    ? averageStack(inPlay, stats.playersLeft)
    : tournament.starting_stack ?? 0
  const bigBlind = level && !level.isBreak ? level.bigBlind : (resolved.nextLevel?.bigBlind ?? 0)

  // Het laatste level waarop nog ingekocht mag worden. De floor typt dat in
  // als gewoon levelnummer, dus we vergelijken met de speeltelling en niet
  // met de index (die telt pauzes mee).
  const lateReg = tournament.late_reg_level
  // De waarschuwing hoort bij de laatste vijf minuten, niet bij het hele
  // level: twintig minuten lang "nog 5 minuten" laten staan is onzin.
  const lastEntryOpen =
    lateReg !== null && !isBreak && playIdx === lateReg && secondsLeft <= 300 && secondsLeft > 0
  const entriesClosed = lateReg !== null && playIdx > lateReg

  // De prijzenverdeling loopt onderaan mee zodra de pot vastligt. Een balk
  // die blijft lopen is rustiger dan iets dat elke minuut opduikt en weer
  // verdwijnt, en de zaal kan er op elk moment naar kijken in plaats van te
  // moeten wachten tot het weer voorbijkomt. Staat er geen late reg
  // ingesteld, dan is er nooit een moment waarop de inkopen "sluiten" en
  // tonen we hem gewoon.
  const showPrizes = prizes.length > 0 && (entriesClosed || lateReg === null)

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
      <FullscreenButton />

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
            maskImage: 'radial-gradient(closest-side, #000 58%, transparent 94%)',
            WebkitMaskImage: 'radial-gradient(closest-side, #000 58%, transparent 94%)',
          }}
        >
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src={club.mark_url}
            alt=""
            className="h-[88vh] w-auto max-w-[90vw] object-contain"
            style={{
              // Genoeg om het merk te herkennen, te weinig om met de cijfers
              // te concurreren. De tijd blijft wit en helder bovenop.
              opacity: isBreak ? 0.34 : 0.26,
              filter: 'saturate(1.15) brightness(1.1)',
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

      {/* Klok in het midden, cijfers langs de zijkanten.
          Alles onderaan op één rij persen werkte niet: zeven blokken naast
          elkaar maakt elk cijfer klein en kapt "32.667" af tot "32.6…",
          terwijl links en rechts van de klok het scherm leeg staat. Nu heeft
          elk cijfer een hele kolombreedte en kan het groot. */}
      <div className="relative flex flex-1 items-stretch gap-[1.5vw] px-[2vw] pb-[1vh]">
        <aside className="flex w-[19vw] shrink-0 flex-col justify-center gap-[1.4vh]">
          <Stat
            label={t('clock.playersLeft')}
            value={String(stats.playersLeft)}
            sub={`${t('common.of')} ${stats.entriesTotal}`}
            big
            accent={accent}
          />
          {/* Geen aparte tegel voor de inkopen: "2 van 3" bij de spelers
              zegt al hoeveel er ingekocht hebben. Twee keer hetzelfde getal
              laat de zaal zoeken naar het verschil dat er niet is.

              Rebuy en re-entry zijn technisch twee dingen — de ene legt chips
              bij iemand die nog zit, de andere haalt een uitgevallen speler
              terug — maar voor de zaal is het één vraag: hoeveel keer is er
              opnieuw ingekocht. Twee tegels met elk een 1 erin zegt niemand
              iets. Op het floor-scherm blijven ze wel apart, want daar hangt
              het van de situatie af welke knop je ziet. */}
          {stats.rebuys + stats.reentries > 0 && (
            <Stat label={t('clock.rebuys')} value={String(stats.rebuys + stats.reentries)} />
          )}
          {stats.addons > 0 && (
            <Stat label={t('clock.addons')} value={String(stats.addons)} />
          )}
        </aside>

      <section className="relative flex flex-1 flex-col items-center justify-center px-[1vw]">
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

        {/* Niet alleen omroepen maar ook tonen: in een volle zaal hoort de
            helft het niet, en dit is de mededeling waar geld aan vastzit. */}
        {(lastEntryOpen || entriesClosed) && (
          <p
            className="mt-[2.2vh] rounded-full px-[2vw] py-[0.8vh] text-[2.2vh] font-semibold uppercase tracking-[0.16em]"
            style={
              entriesClosed
                ? { color: 'var(--text-faint)', border: '1px solid rgba(255,255,255,0.1)' }
                : {
                    color: '#fbbf24',
                    border: '1px solid #fbbf2455',
                    background: '#fbbf2414',
                  }
            }
          >
            {entriesClosed ? t('clock.lastCallOver') : t('clock.lastCallBanner')}
          </p>
        )}

        <p className="mt-[2vh] text-[2.5vh] text-[var(--text-faint)]">
          {resolved.nextLevel
            ? resolved.nextLevel.isBreak
              ? `${t('clock.next')} — ${breakLabel(resolved.nextLevel.label, t('clock.break'))}`
              : `${t('clock.next')} — ${resolved.nextLevel.smallBlind.toLocaleString('nl-BE')} / ${resolved.nextLevel.bigBlind.toLocaleString('nl-BE')}`
            : t('clock.lastLevel')}
        </p>
      </section>

        <aside className="flex w-[19vw] shrink-0 flex-col justify-center gap-[1.4vh]">
          <Stat
            label={t('clock.prizePool')}
            value={stats.prizePoolCents > 0
              ? formatMoney(stats.prizePoolCents, club?.currency ?? 'EUR')
              : '—'}
            big
            accent={accent}
          />
          <Stat
            label={t('clock.avgStack')}
            value={avg.toLocaleString('nl-BE')}
            // Het aantal big blinds zegt een speler meer dan het aantal chips:
            // twintig bb is kort, honderd bb is diep. Bij een pauze staat de
            // big blind op nul, dus dan tonen we niets.
            sub={bigBlind > 0 ? `${formatBb(avg / bigBlind)} bb` : undefined}
          />
          <Stat label={t('clock.elapsed')} value={elapsedTotal > 0 ? formatDuration(elapsedTotal) : '—'} />
        </aside>
      </div>

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

      {showPrizes && (
        <div
          className="relative mt-[1.2vh] overflow-hidden border-t py-[1.1vh]"
          style={{
            borderColor: `${accent}33`,
            background: `linear-gradient(90deg, transparent, ${accent}0f 20%, ${accent}0f 80%, transparent)`,
          }}
        >
          {/* Twee identieke reeksen achter elkaar: als de eerste eruit loopt
              staat de tweede precies op zijn plaats. */}
          <div className="pl-ticker">
            {[0, 1].map((copy) => (
              <span key={copy} className="inline-flex shrink-0 items-baseline">
                <span
                  className="px-[2vw] text-[1.7vh] font-semibold uppercase tracking-[0.3em]"
                  style={{ color: accent }}
                >
                  {t('payout.title')}
                </span>
                {prizes.map((cents, i) => (
                  <span key={i} className="inline-flex items-baseline gap-[0.6vw] px-[1.6vw]">
                    <span className="text-[1.9vh] text-[var(--text-faint)]">{i + 1}</span>
                    <span className="tnum text-[2.8vh] font-bold">
                      {formatMoney(cents, club?.currency ?? 'EUR')}
                    </span>
                  </span>
                ))}
              </span>
            ))}
          </div>
        </div>
      )}


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

      {/* Het dealvoorstel neemt het hele scherm over. Dat is geen detail:
          op dat moment praat de hele zaal hierover, en de klok staat toch
          stil. Zodra de floor het intrekt of de tafel akkoord gaat verdwijnt
          het vanzelf — het scherm luistert mee via realtime. */}
      {deal && deal.shares.length > 0 && (() => {
        // Welke kolommen de floor meegaf. Zijn het er meerdere, dan staan ze
        // naast elkaar: dát is de onderhandeling, en de tafel hoort het
        // verschil te zien in plaats van één cijfer voorgeschoteld te krijgen.
        const cols = ([
          ['icm_cents', t('deal.icm')],
          ['chop_cents', t('deal.chop')],
          ['even_cents', t('deal.even')],
        ] as const).filter(([k]) => deal.shares.some((sh) => sh[k] != null))
        const showAgreed = cols.length === 0
        const rows = [...deal.shares].sort((a, b) => b.agreed_cents - a.agreed_cents)

        return (
          <div className="absolute inset-0 z-40 flex flex-col items-center justify-center bg-[color-mix(in_oklab,var(--bg)_94%,transparent)] px-[3vw] backdrop-blur-sm">
            <p
              className="text-[2.6vh] font-medium uppercase tracking-[0.32em]"
              style={{ color: accent }}
            >
              {t('deal.hallTitle')}
            </p>

            <table className="mt-[3vh] w-full max-w-[86vw] border-collapse">
              <thead>
                <tr className="text-[1.9vh] uppercase tracking-[0.2em] text-[var(--text-faint)]">
                  <th />
                  <th className="pb-[1vh] text-right font-medium">{t('deal.chips')}</th>
                  {cols.map(([k, label]) => (
                    <th key={k} className="pb-[1vh] pl-[3vw] text-right font-medium">{label}</th>
                  ))}
                  {showAgreed && (
                    <th className="pb-[1vh] pl-[3vw] text-right font-medium">{t('deal.agreed')}</th>
                  )}
                </tr>
              </thead>
              <tbody>
                {rows.map((sh, i) => (
                  <tr key={i} className="border-t border-white/10">
                    <td className="py-[1.2vh] text-left text-[4vh] font-semibold">{sh.name}</td>
                    <td className="tnum py-[1.2vh] text-right text-[2.2vh] text-[var(--text-faint)]">
                      {sh.chips > 0 ? sh.chips.toLocaleString('nl-BE') : ''}
                    </td>
                    {cols.map(([k]) => (
                      <td
                        key={k}
                        className="tnum py-[1.2vh] pl-[3vw] text-right font-bold"
                        style={{ fontSize: 'min(4.6vh, 4vw)', color: accent }}
                      >
                        {sh[k] == null ? '' : formatMoney(sh[k] as number, club?.currency ?? 'EUR')}
                      </td>
                    ))}
                    {showAgreed && (
                      <td
                        className="tnum py-[1.2vh] pl-[3vw] text-right font-bold"
                        style={{ fontSize: 'min(5vh, 4.4vw)', color: accent }}
                      >
                        {formatMoney(sh.agreed_cents, club?.currency ?? 'EUR')}
                      </td>
                    )}
                  </tr>
                ))}
              </tbody>
            </table>

            <p className="mt-[3vh] text-[2.2vh] text-[var(--text-faint)]">
              {t('deal.hallFoot')}
            </p>
          </div>
        )
      })()}

      {!live && (
        <p className="absolute bottom-2 right-3 text-[1.5vh] text-[#fbbf24]">
          {t('clock.offline')}
        </p>
      )}
    </main>
  )
}

/** Onder de tien big blinds is één cijfer na de komma zinvol, daarboven niet. */
function formatBb(v: number): string {
  if (!Number.isFinite(v) || v <= 0) return '0'
  return v < 10 ? v.toFixed(1).replace('.', ',') : String(Math.round(v))
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

/**
 * Eén cijfer in een zijkolom.
 *
 * `big` krijgt de clubkleur en een groter cijfer: dat zijn de twee dingen
 * waar vanaf de andere kant van de zaal naar gekeken wordt — hoeveel spelers
 * er nog zitten, en hoeveel er in de pot ligt. De rest is context.
 *
 * Het cijfer wordt niet afgekapt maar krimpt mee: "32.667" is een antwoord,
 * "32.6…" is er geen.
 */
function Stat({
  label, value, sub, big, accent,
}: {
  label: string
  value: string
  sub?: string
  big?: boolean
  accent?: string
}) {
  return (
    <div
      className="rounded-[1.4vh] border px-[0.9vw] py-[1.2vh] text-center backdrop-blur-sm"
      style={{
        borderColor: big && accent ? `${accent}55` : 'rgba(255,255,255,0.07)',
        background: big && accent ? `${accent}12` : 'rgba(255,255,255,0.035)',
      }}
    >
      <p className="truncate text-[1.5vh] font-medium uppercase tracking-[0.18em] text-[var(--text-faint)]">
        {label}
      </p>
      <p
        className="tnum font-bold leading-tight"
        style={{
          fontSize: big ? 'min(6.6vh, 4.6vw)' : 'min(4.8vh, 3.4vw)',
          color: big && accent ? accent : undefined,
        }}
      >
        {value}
      </p>
      {sub && <p className="tnum text-[1.6vh] text-[var(--text-faint)]">{sub}</p>}
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
