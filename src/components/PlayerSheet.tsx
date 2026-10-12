'use client'

import { useEffect, useMemo, useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { formatMoney } from '@/lib/types'
import { useT } from '@/lib/i18n/context'
import { dbMessage } from '@/lib/dbMessage'

/**
 * Alles wat je met één speler kan doen, in één paneel dat van onder opkomt.
 *
 * **Waarom van onderen.** De floor houdt zijn telefoon in één hand en bedient
 * hem met de duim van diezelfde hand. De onderste derde van het scherm is het
 * enige deel dat die duim comfortabel haalt; daar horen dus de knoppen te
 * staan, en niet in een rij rechts van een naam bovenaan een lijst.
 *
 * **Waarom één paneel en niet vier.** Rebuy, addon, verplaatsen, uitschakelen
 * en annuleren zaten tot nu verspreid over een geldrij, een knoppenrij en een
 * bevestigingsrij, elk op een andere plaats in de lijst. Dat werkt op een
 * laptop en niet in een zaal: je tikt de verkeerde rij aan omdat de lijst net
 * verschoof. Eén paneel per speler lost dat op — je ziet wiens paneel open
 * staat, en alles wat je met hém kan staat erin.
 *
 * **Het doet zijn eigen aanroepen.** Zo kan hetzelfde paneel open uit de
 * tafelweergave én uit de spelerslijst, zonder dat die twee elkaars
 * handelingen moeten kennen. Wat erna moet gebeuren — lijsten verversen —
 * zegt de ouder via `onChanged`.
 */

export interface SheetPlayer {
  id: string
  name: string
  status: string
  chipCount: number | null
  finishPosition: number | null
  tableNo: number | null
  seatNo: number | null
  reentriesUsed: number
  rebuysUsed: number
  bountiesWon: number
  /** Hoeveel bonuschips hij kreeg voor een voorinschrijving. 0 = geen. */
  preregBonus: number
  /** Zijn mailadres, of null als hij er geen gaf. */
  email?: string | null
  /** Wie zijn stapel het laatst zette: 'floor', 'player', of niemand. */
  chipCountBy?: string | null
  /** Wanneer dat gebeurde. */
  chipCountAt?: string | null
}

/**
 * Wat het paneel van de avond moet weten. Eén keer samengesteld in het
 * floorscherm en doorgegeven aan beide panelen, zodat de tafelweergave en de
 * spelerslijst niet elk hun eigen versie van "wat kost een rebuy" krijgen.
 */
export interface SheetContext {
  maxReentries: number
  /** 'none' betekent: niemand vragen wie hem eruit speelde. */
  bountyMode: string
  startingStack: number
  /** Hoeveel bonuschips deze avond geeft voor voorinschrijven. 0 = geen. */
  preregBonusStack: number
  currency: string
  rebuyCents: number
  addonCents: number
  /** De prijzenladder in cent, van eerste plaats naar beneden. */
  prizes: number[]
  /** Hoeveel spelers er nu nog zitten; bepaalt welke plaats er vrijkomt. */
  playersLeft: number
  /** Hoeveel er in totaal meespeelden; voor "wordt 7e van 13". */
  entriesTotal: number
}

export function PlayerSheet({
  player, ctx, others, onClose, onChanged, onMove,
}: {
  player: SheetPlayer
  ctx: SheetContext
  /** De andere spelers die nog zitten; voor de vraag wie hem eruit speelde. */
  others: { id: string; name: string }[]
  onClose: () => void
  onChanged: () => void | Promise<void>
  /** Zet de speler op de hand om hem te verplaatsen. Weg = geen knop. */
  onMove?: (id: string, name: string) => void
}) {
  const supabase = useMemo(() => createClient(), [])
  const t = useT()

  const [busy, setBusy] = useState(false)
  const [fout, setFout] = useState<string | null>(null)
  const [weergave, setWeergave] = useState<'hoofd' | 'uit' | 'annuleren'>('hoofd')
  /** De fiches in dit paneel; pas weggeschreven als je klaar bent met tikken. */
  const [fiches, setFiches] = useState<string>(getal(player.chipCount ?? 0))

  const uit = player.status === 'eliminated'
  const inkopen = player.reentriesUsed + player.rebuysUsed
  const opDeLimiet = inkopen >= ctx.maxReentries

  // Welke plaats er vrijkomt als deze man nu opstaat, en wat daar in de ladder
  // tegenover staat. Alleen om te tónen: de server beslist het echte bedrag.
  const plaats = Math.max(1, ctx.playersLeft)
  const prijsCents = ctx.prizes[plaats - 1] ?? 0

  // Escape sluit. Op een telefoon haalt niemand die toets, maar aan de floor
  // staat ook een laptop, en daar is wegklikken met het toetsenbord sneller.
  useEffect(() => {
    function toets(e: KeyboardEvent) {
      if (e.key === 'Escape') onClose()
    }
    window.addEventListener('keydown', toets)
    return () => window.removeEventListener('keydown', toets)
  }, [onClose])

  // PromiseLike en niet Promise: de bouwers van supabase-js doen pas een
  // verzoek zodra je erop wacht.
  async function run(
    fn: () => PromiseLike<{ error: { message: string } | null }>,
    sluiten = true,
  ) {
    setBusy(true)
    setFout(null)
    const { error: err } = await fn()
    if (err) {
      setFout(dbMessage(err, t))
      setBusy(false)
      return
    }
    await onChanged()
    setBusy(false)
    if (sluiten) onClose()
  }

  /**
   * De stap van de plus- en minknop.
   *
   * Afgeleid van de startstapel en niet vast: een avond met 40.000 chips wil
   * met 5.000 op en neer, een avond met 5.000 niet. Afgerond op een rond
   * getal, want 4.167 op een knop leest als een fout.
   */
  const stap = Math.max(100, Math.round(ctx.startingStack / 8 / 500) * 500)

  function stapFiches(d: number) {
    const nu = Number.parseInt(fiches.replace(/\D/g, ''), 10) || 0
    setFiches(getal(Math.max(0, nu + d)))
  }

  async function bewaarFiches() {
    const n = Number.parseInt(fiches.replace(/\D/g, ''), 10)
    if (!Number.isFinite(n)) { setFiches(getal(player.chipCount ?? 0)); return }
    // Pas bij het loslaten netjes zetten. Tijdens het tikken niet: dan springt
    // de cursor achter het punt dat er net bijkwam.
    setFiches(getal(Math.max(0, n)))
    if (n === (player.chipCount ?? 0)) return
    await run(() => supabase.from('tournament_players')
      .update({ chip_count: Math.max(0, n) }).eq('id', player.id), false)
  }

  const plek = player.tableNo !== null && player.seatNo !== null
    ? `T${player.tableNo}·${player.seatNo}`
    : uit
      ? t('sheet.place').replace('{p}', String(player.finishPosition ?? '—'))
      : t('sheet.seatless')

  const onder = [
    inkopen > 0 ? t('sheet.boughtIn').replace('{n}', String(inkopen)) : null,
    player.bountiesWon > 0
      ? t('sheet.knockouts').replace('{n}', String(player.bountiesWon)) : null,
    player.preregBonus > 0
      ? t('sheet.earlyBadge').replace('{n}', player.preregBonus.toLocaleString('nl-BE')) : null,
  ].filter((x) => x !== null).join(' · ')

  return (
    <>
      {/* De waas. Hij vangt de tik die naast het paneel valt, en hij maakt van
          de lijst erachter iets waar je niet per ongeluk in tikt. */}
      <button
        type="button"
        aria-label={t('players.close')}
        onClick={onClose}
        className="fixed inset-0 z-40 bg-black/55 backdrop-blur-[2px]"
      />
      <div
        role="dialog"
        aria-modal="true"
        aria-label={player.name}
        /* Op een telefoon een blad dat van onderen opkomt; op een scherm met
           een muis een venster in het midden. Dat is geen smaak: een blad
           onderaan een breed scherm laat je met je ogen naar beneden springen
           terwijl je cursor bovenin staat, en het ziet eruit als een telefoon
           die per ongeluk in een laptop zit. Dezelfde knoppen, andere plaats. */
        className="fixed inset-x-0 bottom-0 z-50 mx-auto max-h-[88dvh] w-full max-w-lg overflow-y-auto rounded-t-2xl border border-[var(--line-strong)] border-b-0 bg-[var(--surface)] px-4 pb-safe pt-2 shadow-[0_-18px_40px_-12px_#000] sm:bottom-auto sm:top-1/2 sm:max-h-[86dvh] sm:-translate-y-1/2 sm:rounded-2xl sm:border-b sm:pb-4 sm:shadow-[0_24px_60px_-20px_#000]"
      >
        {/* Het greepje. Het sleept niets — het zegt dat dit ding van onderen
            komt en dat je het naar beneden mag denken. */}
        <div aria-hidden className="mx-auto mb-3 h-1 w-10 rounded-full bg-[var(--line-strong)] sm:hidden sm:mb-0" />

        <div className="flex items-baseline gap-2.5">
          <h2 className="min-w-0 flex-1 truncate text-lg font-semibold">{player.name}</h2>
          <span className="tnum shrink-0 rounded-md bg-[var(--surface-2)] px-2 py-0.5 text-xs text-[var(--text-muted)]">
            {plek}
          </span>
        </div>
        <p className="mt-0.5 min-h-[1.1rem] text-xs text-[var(--text-faint)]">{onder}</p>
        {/* Het mailadres en de herkomst van de stapel stonden in de lijst en
            maakten elke rij twee regels hoog. Ze horen hier: je kijkt ernaar
            als je met déze speler bezig bent, niet terwijl je de lijst
            afscant. */}
        <p className="mb-3 flex flex-wrap items-center gap-x-2 text-xs text-[var(--text-faint)]">
          {player.email
            ? <span className="truncate">{player.email}</span>
            : <span className="text-[var(--warn)]">{t('players.noEmailBadge')}</span>}
          {player.chipCountAt && (
            <span className={player.chipCountBy === 'player' ? 'text-[var(--warn)]' : ''}>
              {player.chipCountBy === 'player'
                ? t('players.chipsByPlayer')
                : t('players.chipsByFloor')}
              {' · '}
              {geleden(player.chipCountAt, t)}
            </span>
          )}
        </p>

        {fout && (
          <p className="mb-3 rounded-lg border border-[color-mix(in_oklab,var(--danger)_35%,transparent)] bg-[color-mix(in_oklab,var(--danger)_10%,transparent)] p-2.5 text-sm text-[var(--danger)]">
            {fout}
          </p>
        )}

        {weergave === 'hoofd' && (
          <>
            {/* ------------------------------------------------------- fiches
                Min, getal, plus. Grote vlakken, want dit is de handeling die
                aan de finaletafel het vaakst gebeurt en meestal met één hand.
                Een uitgeschakelde speler heeft geen stapel meer; dan staat er
                niets. */}
            {!uit && (
              <div className="mb-3 flex items-stretch gap-2">
                <Stapknop label="−" onClick={() => stapFiches(-stap)} disabled={busy} />
                <input
                  inputMode="numeric"
                  aria-label={t('sheet.chips')}
                  value={fiches}
                  disabled={busy}
                  onChange={(e) => setFiches(e.target.value)}
                  onBlur={() => void bewaarFiches()}
                  onKeyDown={(e) => {
                    if (e.key === 'Enter') (e.target as HTMLInputElement).blur()
                  }}
                  className="tnum min-w-0 flex-1 rounded-xl border border-[var(--line)] bg-[var(--surface-2)] px-3 py-3 text-center text-xl font-semibold outline-none focus:border-[var(--brand)] disabled:opacity-45"
                />
                <Stapknop label="+" onClick={() => stapFiches(stap)} disabled={busy} />
              </div>
            )}

            <div className="grid grid-cols-2 gap-2">
              <Actie
                goud
                disabled={busy || opDeLimiet}
                onClick={() => void run(() => supabase.rpc('floor_rebuy', {
                  p_tournament_player_id: player.id,
                  p_kind: uit ? 'reentry' : 'rebuy',
                }))}
                label={t('players.rebuy')}
                sub={opDeLimiet
                  ? t('players.rebuyLimit')
                  : `${formatMoney(ctx.rebuyCents, ctx.currency)} · ${
                      uit
                        ? ctx.startingStack.toLocaleString('nl-BE')
                        : `${(player.chipCount ?? 0).toLocaleString('nl-BE')} → ${ctx.startingStack.toLocaleString('nl-BE')}`
                    }`}
              />

              {!uit && (
                <Actie
                  disabled={busy}
                  onClick={() => void run(() => supabase.rpc('floor_rebuy', {
                    p_tournament_player_id: player.id, p_kind: 'addon',
                  }))}
                  label={t('players.addon')}
                  sub={formatMoney(ctx.addonCents, ctx.currency)}
                />
              )}

              {uit && (
                <Actie
                  disabled={busy}
                  onClick={() => void run(() => supabase.rpc('floor_undo_elimination', {
                    p_tournament_player_id: player.id,
                  }))}
                  label={t('players.undo')}
                  sub={t('sheet.undoElimSub')}
                />
              )}

              {!uit && onMove && (
                <Actie
                  disabled={busy}
                  onClick={() => { onMove(player.id, player.name); onClose() }}
                  label={t('sheet.move')}
                  sub={t('sheet.moveSub')}
                />
              )}

              <Actie
                disabled={busy}
                onClick={() => void run(() => supabase.rpc('floor_undo_last_buyin', {
                  p_tournament_player_id: player.id,
                }))}
                label={`↩ ${t('players.undoBuyin')}`}
                sub={t('sheet.undoBuyinSub')}
              />

              {/* ------------------------------------------------ early bird
                  Binnen bereik en niet alleen bij het inschrijven. Wie vooraf
                  mailde dat hij komt, wie vorige week al op de lijst stond,
                  wie het aan de toog zei: dat zijn allemaal mensen die de
                  bonus horen te krijgen, en soms weet je dat pas als hij al
                  zit. De knop boekt de chips ook op de inkoop, zodat de
                  gemiddelde stapel in de zaal blijft kloppen.

                  Eén richting, en hij verdwijnt zodra hij gegeven is. Chips
                  die al op tafel liggen en waarmee gespeeld is, neem je niet
                  meer terug; en de bonus hoort bij de eerste inkoop, dus na
                  een rebuy weigert de databank hem sowieso. Verkeerd gedaan?
                  Dan is het de inschrijving intrekken en opnieuw. */}
              {!uit && ctx.preregBonusStack > 0 && player.preregBonus === 0
                && inkopen === 0 && (
                <Actie
                  breed
                  disabled={busy}
                  onClick={() => void run(() => supabase.rpc('floor_grant_prereg_bonus', {
                    p_tournament_player_id: player.id,
                  }), false)}
                  label={t('sheet.earlyOn')}
                  sub={t('sheet.earlyOnSub')
                    .replace('{n}', ctx.preregBonusStack.toLocaleString('nl-BE'))
                    .replace('{totaal}', (ctx.startingStack + ctx.preregBonusStack).toLocaleString('nl-BE'))}
                />
              )}

              {!uit && (
                <Actie
                  breed
                  rood
                  disabled={busy}
                  onClick={() => (ctx.bountyMode === 'none'
                    ? void run(() => supabase.rpc('floor_eliminate', {
                        p_tournament_player_id: player.id,
                        p_by_tournament_player_id: null,
                      }))
                    : setWeergave('uit'))}
                  label={t('players.eliminate')}
                  sub={prijsCents > 0
                    ? `${t('sheet.willBe')
                        .replace('{p}', String(plaats))
                        .replace('{n}', String(ctx.entriesTotal))} · ${formatMoney(prijsCents, ctx.currency)}`
                    : t('sheet.willBe')
                        .replace('{p}', String(plaats))
                        .replace('{n}', String(ctx.entriesTotal))}
                />
              )}

              {/* De inschrijving intrekken. Dit is iets ánders dan
                  uitschakelen: deze man heeft niet verloren, hij heeft niet
                  gespeeld. Zijn geld gaat uit de kas en zijn chips uit het
                  spel. Onderaan, want het is de knop die je het minst nodig
                  hebt en het meest kapot maakt als je hem per ongeluk raakt. */}
              <Actie
                breed
                rood
                disabled={busy}
                onClick={() => setWeergave('annuleren')}
                label={t('sheet.cancelEntry')}
                sub={t('sheet.cancelEntrySub')}
              />

              <Actie breed disabled={busy} onClick={onClose} label={t('players.close')} />
            </div>
          </>
        )}

        {/* ------------------------------------------------------ wie sloeg hem
            Op een bountyavond hangt hier geld aan, dus het is geen detail dat
            je later invult. De lijst is lang genoeg om te scrollen en elke
            naam is een volle regel: aan een tafel van negen in halfduister
            tik je anders de buur aan. */}
        {weergave === 'uit' && (
          <div className="space-y-2">
            <p className="text-xs uppercase tracking-widest text-[var(--text-faint)]">
              {t('players.eliminatedBy')}
            </p>
            <div className="grid gap-1.5">
              {others.map((o) => (
                <Actie
                  key={o.id}
                  breed
                  disabled={busy}
                  onClick={() => void run(() => supabase.rpc('floor_eliminate', {
                    p_tournament_player_id: player.id,
                    p_by_tournament_player_id: o.id,
                  }))}
                  label={o.name}
                />
              ))}
              <Actie
                breed
                disabled={busy}
                onClick={() => void run(() => supabase.rpc('floor_eliminate', {
                  p_tournament_player_id: player.id,
                  p_by_tournament_player_id: null,
                }))}
                label={t('players.nobody')}
              />
              <Actie breed disabled={busy} onClick={() => setWeergave('hoofd')} label={t('common.cancel')} />
            </div>
          </div>
        )}

        {weergave === 'annuleren' && (
          <div className="space-y-2">
            <p className="rounded-lg border border-[color-mix(in_oklab,var(--danger)_35%,transparent)] bg-[color-mix(in_oklab,var(--danger)_8%,transparent)] p-3 text-sm leading-relaxed text-[var(--danger)]">
              {t('sheet.cancelConfirm').replace('{n}', player.name)}
            </p>
            <Actie
              breed
              rood
              disabled={busy}
              onClick={() => void run(() => supabase.rpc('floor_remove_entry', {
                p_tournament_player_id: player.id,
              }))}
              label={t('players.removeYes')}
            />
            <Actie breed disabled={busy} onClick={() => setWeergave('hoofd')} label={t('common.cancel')} />
          </div>
        )}
      </div>
    </>
  )
}

/**
 * "9 min geleden". Alleen de orde van grootte: je wil weten of een stapel vers
 * is, niet hoe vers precies.
 */
function geleden(wanneer: string, t: ReturnType<typeof useT>): string {
  const m = Math.max(0, Math.round((Date.now() - Date.parse(wanneer)) / 60_000))
  if (m < 1) return t('players.chipsJustNow')
  if (m < 60) return t('players.chipsMinutesAgo').replace('{n}', String(m))
  return t('players.chipsHoursAgo').replace('{n}', String(Math.floor(m / 60)))
}

/**
 * Fiches met punten ertussen. 87.500 is in één oogopslag te lezen en 87500
 * niet — en dit getal wordt aan de finaletafel om de twee minuten gelezen.
 */
function getal(n: number): string {
  return n.toLocaleString('nl-BE')
}

/** Min en plus. Vierkant en groot genoeg om met een duim te raken. */
function Stapknop({
  label, onClick, disabled,
}: { label: string; onClick: () => void; disabled?: boolean }) {
  return (
    <button
      type="button"
      aria-label={label}
      onClick={onClick}
      disabled={disabled}
      className="w-14 shrink-0 rounded-xl border border-[var(--line-strong)] text-xl font-semibold transition active:scale-95 hover:bg-[var(--surface-hover)] disabled:opacity-40"
    >
      {label}
    </button>
  )
}

/**
 * Eén handeling.
 *
 * De ondertitel staat op de knop en niet in een uitleg ernaast: wat een rebuy
 * kost en wat het met de stapel doet, hoort te staan waar je drukt. Dat is het
 * verschil tussen "weten wat je boekt" en "erna kijken wat er gebeurde".
 */
function Actie({
  label, sub, onClick, disabled, goud, rood, breed,
}: {
  label: string
  sub?: string
  onClick: () => void
  disabled?: boolean
  goud?: boolean
  rood?: boolean
  breed?: boolean
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      className={[
        'rounded-xl px-3 py-3 text-left text-sm font-medium transition active:scale-[0.98]',
        'disabled:cursor-not-allowed disabled:opacity-40',
        breed ? 'col-span-2' : '',
        goud
          ? 'bg-[var(--brand)] text-[var(--on-brand)] hover:brightness-110'
          : rood
            ? 'border border-[color-mix(in_oklab,var(--danger)_45%,transparent)] text-[var(--danger)] hover:bg-[color-mix(in_oklab,var(--danger)_12%,transparent)]'
            : 'border border-[var(--line-strong)] hover:bg-[var(--surface-hover)]',
      ].join(' ')}
    >
      {label}
      {sub && (
        <span className={`mt-0.5 block text-xs font-normal leading-snug ${
          goud ? 'opacity-75' : 'text-[var(--text-faint)]'
        }`}>
          {sub}
        </span>
      )}
    </button>
  )
}
