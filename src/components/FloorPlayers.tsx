'use client'

import { useMemo, useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { formatMoney } from '@/lib/types'
import { useFloorPlayers } from '@/lib/useFloorPlayers'
import { useT } from '@/lib/i18n/context'

/**
 * Spelersbeheer aan de floor.
 *
 * Alles wat hier gebeurt loopt via één databankfunctie per handeling. Dat is
 * geen omweg maar de kern: een speler toevoegen raakt vier tabellen tegelijk,
 * en een eindplaats die de browser zou berekenen loopt mis zodra er twee
 * toestellen tegelijk iemand wegklikken. De server telt, de browser toont.
 *
 * Ontwerpregel zoals bij de klokknoppen: één klik per handeling, geen
 * bevestigingsvensters. De enige uitzondering is het afsluiten van het
 * tornooi — dat kan je niet met één klik terugdraaien.
 */
export function FloorPlayers({
  tournamentId,
  clubId,
  bountyMode,
  maxReentries,
  finished,
  money,
}: {
  tournamentId: string
  clubId: string
  /** 'none' betekent: geen vraag naar wie er uitschakelde. */
  bountyMode: string
  maxReentries: number
  finished: boolean
  /** Bedragen op de knoppen zetten: je ziet wát je boekt voor je klikt. */
  money: { buyinCents: number; addonCents: number | null; currency: string }
}) {
  const supabase = useMemo(() => createClient(), [])
  const { players, members, loading, error, reload } = useFloorPlayers(tournamentId, clubId)
  const t = useT()

  const [query, setQuery] = useState('')
  const [busy, setBusy] = useState(false)
  const [actionError, setActionError] = useState<string | null>(null)
  const [killing, setKilling] = useState<string | null>(null)
  const [confirmFinish, setConfirmFinish] = useState(false)
  /** Het tweede scherm bij een onbekende speler: naam plus mailadres. */
  const [draft, setDraft] = useState<{ name: string; email: string } | null>(null)
  /** Welke rij zijn geldknoppen open heeft staan. */
  const [openMoney, setOpenMoney] = useState<string | null>(null)
  const [sortBy, setSortBy] = useState<'name' | 'chips'>('name')

  const active = players
    .filter((p) => p.status === 'active' || p.status === 'registered')
    .sort((a, b) => sortBy === 'chips'
      // Grootste stapel bovenaan: dat is de vraag die aan de finaletafel
      // het vaakst gesteld wordt.
      ? (b.chipCount ?? 0) - (a.chipCount ?? 0)
      : a.name.localeCompare(b.name, 'nl'))
  const out = players
    .filter((p) => p.status === 'eliminated')
    .sort((a, b) => (a.finishPosition ?? 0) - (b.finishPosition ?? 0))

  const inTournament = new Set(players.map((p) => p.playerId))
  const needle = query.trim().toLowerCase()
  // Zoeken op naam én op mailadres. Aan de deur zegt iemand zijn naam, dus
  // dat is het gewone geval — maar met twee keer een Jan Peeters in het
  // bestand is het mailadres het enige waarmee je ze uit elkaar houdt.
  const matches = needle
    ? members
        .filter((m) =>
          m.name.toLowerCase().includes(needle) ||
          (m.email ?? '').toLowerCase().includes(needle))
        .sort((a, b) => a.name.localeCompare(b.name, 'nl'))
        .slice(0, 6)
    : []
  const exactMatch = members.some(
    (m) => m.name.toLowerCase() === needle || (m.email ?? '').toLowerCase() === needle,
  )

  // Hetzelfde veld filtert ook de lijst eronder. Bij veertig spelers is
  // scrollen naar de juiste naam het traagste wat er is; drie letters typen
  // is sneller, en je hoeft er geen tweede zoekveld voor te leren kennen.
  const shown = (list: typeof players) =>
    needle === '' ? list : list.filter((p) => p.name.toLowerCase().includes(needle))
  const visibleActive = shown(active)
  const visibleOut = shown(out)
  const hiddenCount = (active.length + out.length) - (visibleActive.length + visibleOut.length)

  // PromiseLike en niet Promise: de bouwers van supabase-js zijn "thenables"
  // die pas een echt verzoek doen zodra je erop wacht.
  async function run(fn: () => PromiseLike<{ error: { message: string } | null }>) {
    setBusy(true)
    setActionError(null)
    const { error: err } = await fn()
    if (err) {
      setActionError(
        err.message.includes('row-level security') || err.message.includes('Geen rechten')
          ? t('floor.noRights')
          : err.message,
      )
    }
    await reload()
    setBusy(false)
  }

  async function addExisting(playerId: string) {
    setQuery('')
    await run(() => supabase.rpc('floor_add_entry', {
      p_tournament_id: tournamentId, p_player_id: playerId,
    }))
  }

  async function addNew(name: string, email: string | null, reason: string | null) {
    setDraft(null)
    setQuery('')
    await run(() => supabase.rpc('floor_add_entry', {
      p_tournament_id: tournamentId,
      p_new_name: name,
      p_email: email,
      p_no_email_reason: reason,
    }))
  }

  async function eliminate(tpId: string, byId: string | null) {
    setKilling(null)
    await run(() => supabase.rpc('floor_eliminate', {
      p_tournament_player_id: tpId, p_by_tournament_player_id: byId,
    }))
  }

  async function rebuy(tpId: string, kind: 'reentry' | 'rebuy' | 'addon') {
    setOpenMoney(null)
    await run(() => supabase.rpc('floor_rebuy', {
      p_tournament_player_id: tpId, p_kind: kind,
    }))
  }

  async function undo(tpId: string) {
    await run(() => supabase.rpc('floor_undo_elimination', { p_tournament_player_id: tpId }))
  }

  async function undoBuyin(tpId: string) {
    setOpenMoney(null)
    await run(() => supabase.rpc('floor_undo_last_buyin', { p_tournament_player_id: tpId }))
  }

  async function setChips(tpId: string, value: number) {
    await run(() => supabase.from('tournament_players')
      .update({ chip_count: value }).eq('id', tpId))
  }

  async function finish() {
    setConfirmFinish(false)
    await run(() => supabase.rpc('floor_finish_tournament', { p_tournament_id: tournamentId }))
  }

  if (loading) {
    return <p className="text-sm text-[var(--text-muted)]">{t('common.loading')}</p>
  }

  return (
    <section className="space-y-4">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <h2 className="text-sm uppercase tracking-widest text-[var(--text-faint)]">
          {t('players.title')}
        </h2>
        {/* Alleen wat hier op het scherm staat: aan tafel van het totaal.
            Het aantal inkopen staat al bij de tegels boven — daar komt het
            uit het geldregister en klopt het ook met rebuys en addons. */}
        <div className="flex items-center gap-3">
          {/* Op naam om iemand te vinden, op chips om te zien wie er kort
              staat. Twee vragen, twee volgordes. */}
          {players.length > 1 && (
            <div className="flex items-center gap-0.5 rounded-lg border border-[var(--line)] p-0.5">
              {(['name', 'chips'] as const).map((k) => (
                <button
                  key={k}
                  type="button"
                  onClick={() => setSortBy(k)}
                  className={`rounded-md px-2 py-1 text-xs transition ${
                    sortBy === k
                      ? 'bg-[var(--surface-2)] text-[var(--text)]'
                      : 'text-[var(--text-faint)] hover:text-[var(--text)]'
                  }`}
                >
                  {k === 'name' ? t('players.sortName') : t('players.sortChips')}
                </button>
              ))}
            </div>
          )}
          <p className="tnum text-sm text-[var(--text-faint)]">
            {active.length} / {players.length}
          </p>
        </div>
      </div>

      {finished && (
        <p className="rounded-xl border border-[var(--line)] bg-[var(--surface-2)] p-3 text-sm text-[var(--text-muted)]">
          {t('players.isFinished')}
        </p>
      )}

      {/* ------------------------------------------------------- toevoegen */}
      {/* Zoekveld óf formulier, nooit allebei. Het uitklaplijstje zweeft over
          de pagina heen; laat je dat openstaan terwijl het formulier eronder
          verschijnt, dan overlappen ze elkaar. */}
      {!finished && !draft && (
        <div className="relative">
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder={t('players.searchPlaceholder')}
            autoComplete="off"
            name="speler-zoeken"
            disabled={busy}
            className="w-full rounded-xl border border-[var(--line-strong)] bg-[var(--surface)] px-4 py-3 text-base outline-none placeholder:text-[var(--text-faint)] focus:border-[var(--brand)]"
          />

          {needle !== '' && (
            <ul className="absolute inset-x-0 top-full z-20 mt-1 overflow-hidden rounded-xl border border-[var(--line-strong)] bg-[var(--surface-2)] shadow-2xl">
              {matches.map((m) => {
                const already = inTournament.has(m.playerId)
                return (
                  <li key={m.playerId}>
                    <button
                      type="button"
                      disabled={busy || already}
                      onClick={() => void addExisting(m.playerId)}
                      className="flex w-full items-center justify-between gap-3 px-4 py-3 text-left transition hover:bg-[var(--surface-hover)] disabled:opacity-45"
                    >
                      <span className="min-w-0">
                        <span className="block truncate">{m.name}</span>
                        {/* Het adres erbij, want twee keer dezelfde naam is
                            geen uitzondering in een ledenbestand. */}
                        {m.email && (
                          <span className="block truncate text-xs text-[var(--text-faint)]">
                            {m.email}
                          </span>
                        )}
                      </span>
                      {already && (
                        <span className="text-xs text-[var(--text-faint)]">{t('players.alreadyIn')}</span>
                      )}
                    </button>
                  </li>
                )
              })}

              {matches.length === 0 && (
                <li className="px-4 py-2.5 text-sm text-[var(--text-faint)]">
                  {t('players.noMatches')}
                </li>
              )}

              {/* Iemand die er voor het eerst is, staat nergens in. Dan komt
                  er één scherm bij, want zonder mailadres kunnen we hem
                  volgend seizoen niet terugvinden. */}
              {!exactMatch && (
                <li className="border-t border-[var(--line)]">
                  <button
                    type="button"
                    disabled={busy}
                    onClick={() => setDraft(
                      looksLikeEmail(query)
                        ? { name: '', email: query.trim() }
                        : { name: query.trim(), email: '' },
                    )}
                    className="w-full px-4 py-3 text-left transition hover:bg-[var(--surface-hover)] disabled:opacity-45"
                  >
                    <span className="font-medium text-[var(--brand)]">＋ {query.trim()}</span>{' '}
                    <span className="text-sm text-[var(--text-faint)]">{t('players.addNew')}</span>
                  </button>
                </li>
              )}
            </ul>
          )}
        </div>
      )}

      {draft && (
        <NewPlayerForm
          draft={draft}
          busy={busy}
          onCancel={() => setDraft(null)}
          onSubmit={(name, email, reason) => void addNew(name, email, reason)}
        />
      )}

      {actionError && (
        <p className="rounded-xl border border-[color-mix(in_oklab,var(--danger)_35%,transparent)] bg-[color-mix(in_oklab,var(--danger)_10%,transparent)] p-3 text-sm text-[var(--danger)]">
          {actionError}
        </p>
      )}
      {error && !actionError && (
        <p className="text-sm text-[var(--danger)]">{error}</p>
      )}

      {/* --------------------------------------------------------- aan tafel */}
      {players.length === 0 ? (
        <div className="rounded-xl border border-dashed border-[var(--line-strong)] p-8 text-center">
          <p className="font-medium">{t('players.none')}</p>
          <p className="mt-1 text-sm text-[var(--text-muted)]">{t('players.noneBody')}</p>
        </div>
      ) : (
        <ul className="grid gap-px overflow-hidden rounded-xl border border-[var(--line)] bg-[var(--line)] lg:grid-cols-2">
          {visibleActive.map((p) => (
            <li key={p.id} className="bg-[var(--bg)] px-3 py-2.5">
              <div className="flex flex-wrap items-center gap-x-3 gap-y-2">
                <span className="min-w-0 flex-1 truncate font-medium">
                  {p.name}
                  {/* Zonder mailadres kan je hem volgend seizoen niet
                      terugvinden. Hier staan zodat je het na de avond
                      alsnog kan aanvullen. */}
                  {p.email === null && (
                    <span className="ml-2 rounded px-1.5 py-0.5 text-[0.65rem] uppercase tracking-wider text-[var(--warn)] ring-1 ring-[color-mix(in_oklab,var(--warn)_35%,transparent)]">
                      {t('players.noEmailBadge')}
                    </span>
                  )}
                  {p.reentriesUsed > 0 && (
                    <span className="ml-2 text-xs text-[var(--text-faint)]">
                      {p.reentriesUsed}× {t('players.reentriesShort')}
                    </span>
                  )}
                  {p.bountiesWon > 0 && (
                    <span className="ml-2 text-xs text-[var(--gold,var(--brand))]">
                      {p.bountiesWon} {t('players.knockouts')}
                    </span>
                  )}
                </span>

                <ChipInput
                  value={p.chipCount ?? 0}
                  disabled={busy || finished}
                  label={t('players.chips')}
                  onCommit={(v) => void setChips(p.id, v)}
                />

                {/* De geldknoppen zitten achter één knop, en niet naast
                    "Uitschakelen". Ze stonden eerst wél naast elkaar, en dan
                    kost één misser aan een volle tafel twintig euro in de
                    pot die niemand betaald heeft. Nu moet je er bewust naar
                    grijpen — en alles wat je hier boekt is terug te draaien. */}
                {!finished && (
                  <div className="flex items-center gap-1.5">
                    <Small
                      onClick={() => setOpenMoney(openMoney === p.id ? null : p.id)}
                      disabled={busy}
                      active={openMoney === p.id}
                    >
                      {t('players.money')}
                    </Small>
                    <span className="mx-0.5 h-6 w-px bg-[var(--line)]" aria-hidden />
                    <Small
                      danger
                      onClick={() => (bountyMode === 'none'
                        ? void eliminate(p.id, null)
                        : setKilling(killing === p.id ? null : p.id))}
                      disabled={busy}
                    >
                      {t('players.eliminate')}
                    </Small>
                  </div>
                )}
              </div>

              {openMoney === p.id && (
                <div className="mt-2.5 flex flex-wrap gap-1.5 rounded-lg bg-[var(--surface-2)] p-2.5">
                  <Small onClick={() => void rebuy(p.id, 'rebuy')} disabled={busy}>
                    {t('players.rebuy')} {formatMoney(money.buyinCents, money.currency)}
                  </Small>
                  <Small onClick={() => void rebuy(p.id, 'addon')} disabled={busy}>
                    {t('players.addon')}{' '}
                    {formatMoney(money.addonCents ?? money.buyinCents, money.currency)}
                  </Small>
                  <Small onClick={() => void undoBuyin(p.id)} disabled={busy}>
                    ↩ {t('players.undoBuyin')}
                  </Small>
                  <Small onClick={() => setOpenMoney(null)} disabled={busy}>
                    {t('common.cancel')}
                  </Small>
                </div>
              )}

              {/* Bij een bountytornooi is de vraag wie hem eruit speelde geen
                  detail: daar hangt geld aan vast. Vandaar deze rij, en niet
                  een venster dat je eerst moet wegklikken. */}
              {killing === p.id && (
                <div className="mt-2.5 rounded-lg bg-[var(--surface-2)] p-2.5">
                  <p className="mb-2 text-xs uppercase tracking-widest text-[var(--text-faint)]">
                    {t('players.eliminatedBy')}
                  </p>
                  <div className="flex flex-wrap gap-1.5">
                    {active
                      .filter((o) => o.id !== p.id)
                      .map((o) => (
                        <Small key={o.id} onClick={() => void eliminate(p.id, o.id)} disabled={busy}>
                          {o.name}
                        </Small>
                      ))}
                    <Small onClick={() => void eliminate(p.id, null)} disabled={busy}>
                      {t('players.nobody')}
                    </Small>
                    <Small onClick={() => setKilling(null)} disabled={busy}>
                      {t('common.cancel')}
                    </Small>
                  </div>
                </div>
              )}
            </li>
          ))}

          {/* ------------------------------------------------- uitgeschakeld */}
          {visibleOut.length > 0 && (
            <li className="bg-[var(--surface-2)] px-3 py-1.5 text-xs uppercase tracking-widest text-[var(--text-faint)] lg:col-span-2">
              {t('players.eliminated')}
            </li>
          )}
          {visibleOut.map((p) => (
            <li key={p.id} className="flex flex-wrap items-center gap-x-3 gap-y-2 bg-[var(--bg)] px-3 py-2.5 text-[var(--text-muted)]">
              <span className="tnum w-8 shrink-0 text-right font-semibold text-[var(--text-faint)]">
                {p.finishPosition ?? '—'}
              </span>
              <span className="min-w-0 flex-1 truncate line-through decoration-[var(--line-strong)]">
                {p.name}
              </span>
              {!finished && (
                <div className="flex items-center gap-1.5">
                  {p.reentriesUsed < maxReentries && (
                    <Small onClick={() => void rebuy(p.id, 'reentry')} disabled={busy}>
                      {t('players.reentry')}
                    </Small>
                  )}
                  <Small onClick={() => void undo(p.id)} disabled={busy}>
                    {t('players.undo')}
                  </Small>
                </div>
              )}
            </li>
          ))}
        </ul>
      )}

      {hiddenCount > 0 && (
        <button
          type="button"
          onClick={() => setQuery('')}
          className="w-full rounded-lg border border-dashed border-[var(--line-strong)] px-3 py-2 text-sm text-[var(--text-faint)] transition hover:text-[var(--text)]"
        >
          {hiddenCount} {t('players.filtered')} · {t('players.showAll')}
        </button>
      )}

      {/* ---------------------------------------------------------- afsluiten */}
      {!finished && players.length > 0 && (
        confirmFinish ? (
          <div className="rounded-xl border border-[color-mix(in_oklab,var(--warn)_35%,transparent)] bg-[color-mix(in_oklab,var(--warn)_10%,transparent)] p-4">
            <p className="text-sm text-[var(--warn)]">{t('players.finishConfirm')}</p>
            <div className="mt-3 flex gap-2">
              <button
                type="button"
                disabled={busy}
                onClick={() => void finish()}
                className="rounded-lg bg-[var(--brand)] px-4 py-2 text-sm font-medium text-[var(--on-brand)] transition hover:brightness-110 disabled:opacity-45"
              >
                {t('players.finishYes')}
              </button>
              <button
                type="button"
                onClick={() => setConfirmFinish(false)}
                className="rounded-lg border border-[var(--line-strong)] px-4 py-2 text-sm transition hover:bg-[var(--surface-hover)]"
              >
                {t('common.cancel')}
              </button>
            </div>
          </div>
        ) : (
          <button
            type="button"
            onClick={() => setConfirmFinish(true)}
            className="w-full rounded-xl border border-[var(--line-strong)] px-4 py-3 text-sm font-medium transition hover:bg-[var(--surface-hover)]"
          >
            {t('players.finish')}
          </button>
        )
      )}
    </section>
  )
}

/** Ruwe controle, alleen om te raden of iemand een adres of een naam typte. */
function looksLikeEmail(v: string): boolean {
  return /^[^@\s]+@[^@\s]+\.[a-z]{2,}$/i.test(v.trim())
}

/**
 * Het tweede scherm bij een speler die er voor het eerst is.
 *
 * Het mailadres staat hier niet voor de vorm: het is de enige sleutel die
 * over clubs heen werkt. Zonder adres is dezelfde man bij Cutoff en bij een
 * tweede club twee spelers met elk een halve historie, en dat krijg je later
 * alleen nog met de hand recht.
 *
 * Toch is het niet hard verplicht. Wie iemand niet ingeschreven krijgt omdat
 * die zijn adres niet uit het hoofd kent, typt binnen de kortste keren
 * jan@jan.be — en een vervuilde sleutel is erger dan een ontbrekende. Wie
 * overslaat moet wel zeggen waarom, zodat je die spelers achteraf terugvindt.
 */
function NewPlayerForm({
  draft, busy, onCancel, onSubmit,
}: {
  draft: { name: string; email: string }
  busy: boolean
  onCancel: () => void
  onSubmit: (name: string, email: string | null, reason: string | null) => void
}) {
  const t = useT()
  const [name, setName] = useState(draft.name)
  const [email, setEmail] = useState(draft.email)
  const [reason, setReason] = useState<string | null>(null)
  const [askingReason, setAskingReason] = useState(false)

  const reasons = [
    t('players.reasonUnknown'),
    t('players.reasonRefused'),
    t('players.reasonNone'),
  ]

  const nameOk = name.trim() !== ''
  const emailOk = looksLikeEmail(email)

  return (
    <div className="rounded-xl border border-[var(--brand)] bg-[var(--surface)] p-4">
      <p className="mb-3 text-xs uppercase tracking-widest text-[var(--text-faint)]">
        {t('players.newTitle')}
      </p>

      <div className="grid gap-3 sm:grid-cols-2">
        <label className="block">
          <span className="mb-1 block text-xs text-[var(--text-muted)]">{t('players.name')}</span>
          <input
            autoFocus={draft.name === ''}
            autoComplete="off"
            name="speler-naam"
            value={name}
            onChange={(e) => setName(e.target.value)}
            className="w-full rounded-lg border border-[var(--line-strong)] bg-[var(--surface-2)] px-3 py-2.5 outline-none focus:border-[var(--brand)]"
          />
        </label>
        <label className="block">
          <span className="mb-1 block text-xs text-[var(--text-muted)]">{t('common.email')}</span>
          <input
            autoFocus={draft.name !== ''}
            type="email"
            autoComplete="off"
            name="speler-mail"
            inputMode="email"
            autoCapitalize="off"
            autoCorrect="off"
            spellCheck={false}
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter' && nameOk && emailOk && !busy) {
                onSubmit(name.trim(), email.trim(), null)
              }
            }}
            className="w-full rounded-lg border border-[var(--line-strong)] bg-[var(--surface-2)] px-3 py-2.5 outline-none focus:border-[var(--brand)]"
          />
        </label>
      </div>

      <p className="mt-2 text-xs leading-relaxed text-[var(--text-faint)]">
        {t('players.emailHint')}
      </p>

      {askingReason ? (
        <div className="mt-3 rounded-lg bg-[var(--surface-2)] p-3">
          <p className="mb-2 text-xs uppercase tracking-widest text-[var(--text-faint)]">
            {t('players.reasonLabel')}
          </p>
          <div className="flex flex-wrap gap-1.5">
            {reasons.map((r) => (
              <button
                key={r}
                type="button"
                onClick={() => setReason(r)}
                className={`rounded-lg border px-2.5 py-1.5 text-sm transition ${
                  reason === r
                    ? 'border-[var(--brand)] bg-[var(--brand)] text-[var(--on-brand)]'
                    : 'border-[var(--line-strong)] hover:bg-[var(--surface-hover)]'
                }`}
              >
                {r}
              </button>
            ))}
          </div>
          <input
            placeholder={t('players.reasonOther')}
            value={reasons.includes(reason ?? '') ? '' : (reason ?? '')}
            onChange={(e) => setReason(e.target.value)}
            className="mt-2 w-full rounded-lg border border-[var(--line)] bg-[var(--surface)] px-3 py-2 text-sm outline-none focus:border-[var(--brand)]"
          />
          <div className="mt-3 flex flex-wrap gap-2">
            <Primary
              disabled={busy || !nameOk || (reason ?? '').trim() === ''}
              onClick={() => onSubmit(name.trim(), null, (reason ?? '').trim())}
            >
              {t('players.addAnyway')}
            </Primary>
            <Small onClick={() => { setAskingReason(false); setReason(null) }}>
              {t('common.cancel')}
            </Small>
          </div>
        </div>
      ) : (
        <div className="mt-3 flex flex-wrap items-center gap-2">
          <Primary
            disabled={busy || !nameOk || !emailOk}
            onClick={() => onSubmit(name.trim(), email.trim(), null)}
          >
            {t('players.addConfirm')}
          </Primary>
          <Small onClick={() => setAskingReason(true)} disabled={busy}>
            {t('players.noEmail')}
          </Small>
          <Small onClick={onCancel} disabled={busy}>{t('common.cancel')}</Small>
        </div>
      )}
    </div>
  )
}

/**
 * Chipcount die pas wegschrijft als je klaar bent met typen.
 *
 * Bij elke toetsaanslag opslaan zou betekenen dat "20000" onderweg even
 * "2", "20", "200" is — en dat staat dan zo op het zaalscherm.
 */
function ChipInput({
  value, disabled, label, onCommit,
}: {
  value: number
  disabled?: boolean
  label: string
  onCommit: (v: number) => void
}) {
  const [text, setText] = useState<string | null>(null)
  const shown = text ?? String(value)

  function commit() {
    const parsed = Number.parseInt(shown.replace(/\D/g, ''), 10)
    setText(null)
    if (Number.isFinite(parsed) && parsed !== value) onCommit(Math.max(0, parsed))
  }

  return (
    <input
      inputMode="numeric"
      aria-label={label}
      value={shown}
      disabled={disabled}
      onChange={(e) => setText(e.target.value)}
      onBlur={commit}
      onKeyDown={(e) => { if (e.key === 'Enter') (e.target as HTMLInputElement).blur() }}
      className="tnum w-24 rounded-lg border border-[var(--line)] bg-[var(--surface-2)] px-2.5 py-1.5 text-right text-sm outline-none focus:border-[var(--brand)] disabled:opacity-45"
    />
  )
}

function Primary({
  children, onClick, disabled,
}: { children: React.ReactNode; onClick?: () => void; disabled?: boolean }) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      className="rounded-lg bg-[var(--brand)] px-4 py-2 text-sm font-medium text-[var(--on-brand)] transition hover:brightness-110 disabled:cursor-not-allowed disabled:opacity-40"
    >
      {children}
    </button>
  )
}

function Small({
  children, onClick, disabled, danger, active,
}: {
  children: React.ReactNode
  onClick?: () => void
  disabled?: boolean
  danger?: boolean
  active?: boolean
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      className={`rounded-lg px-2.5 py-1.5 text-sm transition disabled:cursor-not-allowed disabled:opacity-40 ${
        danger
          ? 'border border-[color-mix(in_oklab,var(--danger)_45%,transparent)] text-[var(--danger)] hover:bg-[color-mix(in_oklab,var(--danger)_12%,transparent)]'
          : active
            ? 'border border-[var(--brand)] bg-[color-mix(in_oklab,var(--brand)_16%,transparent)]'
            : 'border border-[var(--line-strong)] hover:bg-[var(--surface-hover)]'
      }`}
    >
      {children}
    </button>
  )
}
