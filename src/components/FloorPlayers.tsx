'use client'

import { useMemo, useState } from 'react'
import { createClient } from '@/lib/supabase/client'
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
}: {
  tournamentId: string
  clubId: string
  /** 'none' betekent: geen vraag naar wie er uitschakelde. */
  bountyMode: string
  maxReentries: number
  finished: boolean
}) {
  const supabase = useMemo(() => createClient(), [])
  const { players, members, loading, error, reload } = useFloorPlayers(tournamentId, clubId)
  const t = useT()

  const [query, setQuery] = useState('')
  const [busy, setBusy] = useState(false)
  const [actionError, setActionError] = useState<string | null>(null)
  const [killing, setKilling] = useState<string | null>(null)
  const [confirmFinish, setConfirmFinish] = useState(false)

  const active = players
    .filter((p) => p.status === 'active' || p.status === 'registered')
    .sort((a, b) => a.name.localeCompare(b.name, 'nl'))
  const out = players
    .filter((p) => p.status === 'eliminated')
    .sort((a, b) => (a.finishPosition ?? 0) - (b.finishPosition ?? 0))

  const inTournament = new Set(players.map((p) => p.playerId))
  const needle = query.trim().toLowerCase()
  const matches = needle
    ? members
        .filter((m) => m.name.toLowerCase().includes(needle))
        .sort((a, b) => a.name.localeCompare(b.name, 'nl'))
        .slice(0, 6)
    : []
  const exactMatch = members.some((m) => m.name.toLowerCase() === needle)

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

  async function addNew(name: string) {
    setQuery('')
    await run(() => supabase.rpc('floor_add_entry', {
      p_tournament_id: tournamentId, p_new_name: name,
    }))
  }

  async function eliminate(tpId: string, byId: string | null) {
    setKilling(null)
    await run(() => supabase.rpc('floor_eliminate', {
      p_tournament_player_id: tpId, p_by_tournament_player_id: byId,
    }))
  }

  async function rebuy(tpId: string, kind: 'reentry' | 'rebuy' | 'addon') {
    await run(() => supabase.rpc('floor_rebuy', {
      p_tournament_player_id: tpId, p_kind: kind,
    }))
  }

  async function undo(tpId: string) {
    await run(() => supabase.rpc('floor_undo_elimination', { p_tournament_player_id: tpId }))
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
        <p className="text-sm text-[var(--text-faint)]">
          {active.length} / {players.length}
        </p>
      </div>

      {finished && (
        <p className="rounded-xl border border-[var(--line)] bg-[var(--surface-2)] p-3 text-sm text-[var(--text-muted)]">
          {t('players.isFinished')}
        </p>
      )}

      {/* ------------------------------------------------------- toevoegen */}
      {!finished && (
        <div className="relative">
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder={t('players.searchPlaceholder')}
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
                      <span>{m.name}</span>
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

              {/* Iemand die er voor het eerst is, staat nergens in. Eén klik
                  en hij zit aan tafel — een account komt later maar wel. */}
              {!exactMatch && (
                <li className="border-t border-[var(--line)]">
                  <button
                    type="button"
                    disabled={busy}
                    onClick={() => void addNew(query.trim())}
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
        <ul className="divide-y divide-[var(--line)] overflow-hidden rounded-xl border border-[var(--line)]">
          {active.map((p) => (
            <li key={p.id} className="px-3 py-2.5">
              <div className="flex flex-wrap items-center gap-x-3 gap-y-2">
                <span className="min-w-0 flex-1 truncate font-medium">
                  {p.name}
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

                {!finished && (
                  <div className="flex items-center gap-1.5">
                    <Small onClick={() => void rebuy(p.id, 'rebuy')} disabled={busy}>
                      {t('players.rebuy')}
                    </Small>
                    <Small onClick={() => void rebuy(p.id, 'addon')} disabled={busy}>
                      {t('players.addon')}
                    </Small>
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
          {out.length > 0 && (
            <li className="bg-[var(--surface-2)] px-3 py-1.5 text-xs uppercase tracking-widest text-[var(--text-faint)]">
              {t('players.eliminated')}
            </li>
          )}
          {out.map((p) => (
            <li key={p.id} className="flex flex-wrap items-center gap-x-3 gap-y-2 px-3 py-2.5 text-[var(--text-muted)]">
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

function Small({
  children, onClick, disabled, danger,
}: {
  children: React.ReactNode
  onClick?: () => void
  disabled?: boolean
  danger?: boolean
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      className={`rounded-lg px-2.5 py-1.5 text-sm transition disabled:cursor-not-allowed disabled:opacity-40 ${
        danger
          ? 'border border-[color-mix(in_oklab,var(--danger)_45%,transparent)] text-[var(--danger)] hover:bg-[color-mix(in_oklab,var(--danger)_12%,transparent)]'
          : 'border border-[var(--line-strong)] hover:bg-[var(--surface-hover)]'
      }`}
    >
      {children}
    </button>
  )
}
