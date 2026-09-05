'use client'

import { useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { useT } from '@/lib/i18n/context'
import { dbMessage } from '@/lib/dbMessage'
import { formatBlinds } from '@/lib/tournament/clock'
import type { BlindLevel } from '@/lib/tournament/clock'

/**
 * De blindstructuur van deze avond, aanpasbaar terwijl er gespeeld wordt.
 *
 * **Alleen vooruit.** Wat al gespeeld is, staat grijs en op slot: de duur van
 * die levels is wat de klok gebruikt heeft om te komen waar hij staat, en die
 * achteraf veranderen zou de klok verschuiven naar een moment dat de zaal niet
 * heeft meegemaakt. De databank weigert het ook — dit scherm laat het gewoon
 * niet proberen.
 *
 * **Uitloopknoppen bovenaan het handelingenrijtje.** "+ Level" en "+ Pauze"
 * zetten er meteen eentje bij in het verlengde van de structuur, zonder dat je
 * de bewerkstand in hoeft. Dat is de meest voorkomende reden om hier te zijn:
 * het loopt uit en de blinds moeten door.
 *
 * **En één ding dat het scherm niet zegt maar wel doet:** bij de eerste
 * wijziging krijgt deze avond een eigen kopie van de structuur. Het
 * clubsjabloon dat aan elke zondag hangt, blijft zoals het was.
 */

interface Rij {
  isBreak: boolean
  label: string
  smallBlind: string
  bigBlind: string
  ante: string
  minuten: string
}

function naarRij(l: BlindLevel): Rij {
  return {
    isBreak: l.isBreak,
    label: l.label ?? '',
    smallBlind: String(l.smallBlind),
    bigBlind: String(l.bigBlind),
    ante: String(l.ante),
    minuten: String(Math.round(l.durationS / 60)),
  }
}

export function StructurePanel({
  tournamentId, levels, currentIdx, playNo, finished, onChanged,
}: {
  tournamentId: string
  levels: BlindLevel[]
  /** Waar de klok staat. Alles daarvoor ligt vast. */
  currentIdx: number
  /** Levelnummer zonder de pauzes mee te tellen, zoals de zaal telt. */
  playNo: Map<number, number>
  finished: boolean
  onChanged: () => void
}) {
  const supabase = useState(() => createClient())[0]
  const t = useT()

  const [bewerken, setBewerken] = useState(false)
  const [rijen, setRijen] = useState<Rij[]>([])
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  /** De levels die nog moeten komen, inclusief het level dat nu loopt. */
  const komend = levels.filter((l) => l.idx >= currentIdx)
  const gespeeld = levels.filter((l) => l.idx < currentIdx)

  function start() {
    setRijen(komend.map(naarRij))
    setError(null)
    setBewerken(true)
  }

  async function run(fn: () => PromiseLike<{ error: { message: string } | null }>) {
    setBusy(true)
    setError(null)
    const { error: err } = await fn()
    if (err) setError(dbMessage(err, t))
    setBusy(false)
    onChanged()
  }

  async function bewaar() {
    await run(() => supabase.rpc('floor_set_upcoming_levels', {
      p_tournament_id: tournamentId,
      p_from_idx: currentIdx,
      p_levels: rijen.map((r) => ({
        is_break: r.isBreak,
        label: r.label || null,
        small_blind: Number.parseInt(r.smallBlind, 10) || 0,
        big_blind: Number.parseInt(r.bigBlind, 10) || 0,
        ante: Number.parseInt(r.ante, 10) || 0,
        duration_s: Math.max(1, Number.parseInt(r.minuten, 10) || 20) * 60,
      })),
    }))
    setBewerken(false)
  }

  const zet = (i: number, veld: keyof Rij, waarde: string) =>
    setRijen((r) => r.map((x, j) => (j === i ? { ...x, [veld]: waarde } : x)))

  if (levels.length === 0) return null

  return (
    <section>
      <div className="mb-2 flex flex-wrap items-center justify-between gap-2">
        <h2 className="text-sm uppercase tracking-widest text-[var(--text-faint)]">
          {t('floor.structure')}
        </h2>
        {!finished && (
          <div className="flex flex-wrap gap-2">
            {bewerken ? (
              <>
                <Klein onClick={() => setRijen((r) => [...r, {
                  isBreak: false, label: '', smallBlind: '0', bigBlind: '0', ante: '0', minuten: '20',
                }])} disabled={busy}>
                  {t('struct.addRow')}
                </Klein>
                <Klein onClick={() => setRijen((r) => [...r, {
                  isBreak: true, label: t('clock.break'), smallBlind: '0', bigBlind: '0', ante: '0', minuten: '10',
                }])} disabled={busy}>
                  {t('struct.addBreakRow')}
                </Klein>
                <button
                  type="button"
                  disabled={busy}
                  onClick={() => void bewaar()}
                  className="rounded-lg bg-[var(--brand)] px-3 py-1.5 text-sm font-medium text-[var(--on-brand)] transition hover:brightness-110 disabled:opacity-40"
                >
                  {busy ? t('common.busy') : t('common.save')}
                </button>
                <Klein onClick={() => setBewerken(false)} disabled={busy}>{t('common.cancel')}</Klein>
              </>
            ) : (
              <>
                <Klein onClick={() => void run(() => supabase.rpc('floor_append_level', {
                  p_tournament_id: tournamentId, p_is_break: false,
                }))} disabled={busy}>
                  {t('struct.appendLevel')}
                </Klein>
                <Klein onClick={() => void run(() => supabase.rpc('floor_append_level', {
                  p_tournament_id: tournamentId, p_is_break: true,
                }))} disabled={busy}>
                  {t('struct.appendBreak')}
                </Klein>
                <Klein onClick={start} disabled={busy}>{t('struct.edit')}</Klein>
              </>
            )}
          </div>
        )}
      </div>

      {error && (
        <p className="mb-2 rounded-lg border border-[color-mix(in_oklab,var(--danger)_35%,transparent)] bg-[color-mix(in_oklab,var(--danger)_10%,transparent)] p-2.5 text-sm text-[var(--danger)]">
          {error}
        </p>
      )}

      <ol className="divide-y divide-[var(--line)] overflow-hidden rounded-xl border border-[var(--line)]">
        {/* Het verleden. Altijd zichtbaar en nooit aanpasbaar: hier staat wat
            de klok gebruikt heeft om te komen waar hij staat. */}
        {gespeeld.map((l) => (
          <li
            key={l.idx}
            className={`flex items-center justify-between px-4 py-2 text-sm opacity-45 ${
              l.isBreak ? 'text-[#7dd3fc]' : ''
            }`}
          >
            <span className="w-16 text-[var(--text-faint)]">
              {l.isBreak ? t('clock.break') : `#${playNo.get(l.idx) ?? l.idx + 1}`}
            </span>
            <span className="flex-1 tabular-nums">{formatBlinds(l)}</span>
            <span className="tabular-nums text-[var(--text-faint)]">
              {Math.round(l.durationS / 60)} {t('floor.min')}
            </span>
          </li>
        ))}

        {bewerken
          ? rijen.map((r, i) => (
            /* Op een telefoon zakken ante, duur en het kruisje naar een eigen
               regel. Op één regel geperst kruipen de velden over elkaar heen,
               en dan tik je de duur aan terwijl je de ante bedoelde. */
            <li key={i} className="flex flex-wrap items-center gap-x-2 gap-y-1.5 px-3 py-2 text-sm">
              <span className="w-12 shrink-0 text-xs text-[var(--text-faint)]">
                {r.isBreak ? t('clock.break') : `#${i + 1}`}
              </span>
              {r.isBreak ? (
                <input
                  value={r.label}
                  onChange={(e) => zet(i, 'label', e.target.value)}
                  placeholder={t('clock.break')}
                  className="min-w-0 flex-1 rounded-lg border border-[var(--line)] bg-[var(--surface-2)] px-2 py-1.5 text-sm outline-none focus:border-[var(--brand)]"
                />
              ) : (
                <span className="flex items-center gap-1.5">
                  <Getal waarde={r.smallBlind} onChange={(v) => zet(i, 'smallBlind', v)} label="SB" />
                  <span className="text-[var(--text-faint)]">/</span>
                  <Getal waarde={r.bigBlind} onChange={(v) => zet(i, 'bigBlind', v)} label="BB" />
                </span>
              )}
              <span className="ml-auto flex basis-full items-center justify-end gap-1.5 pl-12 sm:basis-auto sm:pl-0">
                {!r.isBreak && (
                  <span className="flex items-center gap-1">
                    <span className="text-xs text-[var(--text-faint)]">{t('struct.ante')}</span>
                    <Getal waarde={r.ante} onChange={(v) => zet(i, 'ante', v)} label={t('struct.ante')} />
                  </span>
                )}
                <span className="flex items-center gap-1">
                  <Getal waarde={r.minuten} onChange={(v) => zet(i, 'minuten', v)} label={t('floor.min')} smal />
                  <span className="text-xs text-[var(--text-faint)]">{t('floor.min')}</span>
                </span>
                <button
                  type="button"
                  onClick={() => setRijen((rs) => rs.filter((_, j) => j !== i))}
                  className="shrink-0 rounded-lg border border-[color-mix(in_oklab,var(--danger)_45%,transparent)] px-2 py-1.5 text-xs text-[var(--danger)] transition hover:bg-[color-mix(in_oklab,var(--danger)_12%,transparent)]"
                  aria-label={t('struct.remove')}
                >
                  ✕
                </button>
              </span>
            </li>
          ))
          : komend.map((l) => (
            <li
              key={l.idx}
              className={`flex items-center justify-between px-4 py-2 text-sm ${
                l.idx === currentIdx ? 'bg-[var(--surface-2)]' : ''
              } ${l.isBreak ? 'text-[#7dd3fc]' : ''}`}
            >
              <span className="w-16 text-[var(--text-faint)]">
                {l.isBreak ? t('clock.break') : `#${playNo.get(l.idx) ?? l.idx + 1}`}
              </span>
              <span className="flex-1 tabular-nums">{formatBlinds(l)}</span>
              <span className="tabular-nums text-[var(--text-faint)]">
                {Math.round(l.durationS / 60)} {t('floor.min')}
              </span>
            </li>
          ))}
      </ol>

      {bewerken && (
        <p className="mt-2 text-xs leading-relaxed text-[var(--text-faint)]">
          {t('struct.editHint')}
        </p>
      )}
    </section>
  )
}

function Getal({
  waarde, onChange, label, smal,
}: { waarde: string; onChange: (v: string) => void; label: string; smal?: boolean }) {
  return (
    <input
      inputMode="numeric"
      aria-label={label}
      value={waarde}
      onChange={(e) => onChange(e.target.value)}
      onFocus={(e) => e.target.select()}
      className={`tnum ${smal ? 'w-14' : 'w-20'} shrink-0 rounded-lg border border-[var(--line)] bg-[var(--surface-2)] px-2 py-1.5 text-right text-sm outline-none focus:border-[var(--brand)]`}
    />
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
