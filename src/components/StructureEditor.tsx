'use client'

import { useMemo, useState } from 'react'
import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { Button, Card, Field, Notice, SectionTitle, inputClass } from '@/components/ui'
import { useT } from '@/lib/i18n/context'
import {
  generateLadder, makeLevel, nextBlinds, type EditorLevel,
} from '@/lib/tournament/structure'
import { isDefaultBreakLabel } from '@/lib/tournament/clock'

/**
 * Blindstructuur bewerken.
 *
 * De volgorde is de lijst zelf — er is geen apart nummerveld dat uit de pas
 * kan lopen. Bij opslaan krijgt elk level zijn index op basis van waar het
 * staat, wat betekent dat verslepen of verwijderen nooit gaten laat.
 */

interface Props {
  structureId: string
  clubSlug: string
  initialName: string
  initialLevels: EditorLevel[]
}

export function StructureEditor({ structureId, clubSlug, initialName, initialLevels }: Props) {
  const router = useRouter()
  const supabase = useMemo(() => createClient(), [])
  const t = useT()

  const [name, setName] = useState(initialName)
  const [levels, setLevels] = useState<EditorLevel[]>(
    initialLevels.length > 0 ? initialLevels : [makeLevel()],
  )
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [saved, setSaved] = useState(false)

  const totalMinutes = levels.reduce((s, l) => s + (l.minutes || 0), 0)
  const playLevels = levels.filter((l) => !l.isBreak).length

  function patch(key: string, p: Partial<EditorLevel>) {
    setLevels((ls) => ls.map((l) => (l.key === key ? { ...l, ...p } : l)))
    setSaved(false)
  }

  function addLevel() {
    setLevels((ls) => {
      const last = [...ls].reverse().find((l) => !l.isBreak)
      const n = last ? nextBlinds(last.bigBlind) : { sb: 25, bb: 50 }
      return [...ls, makeLevel({
        smallBlind: n.sb,
        bigBlind: n.bb,
        ante: last && last.ante > 0 ? n.bb : 0,
        minutes: last?.minutes ?? 20,
      })]
    })
    setSaved(false)
  }

  function addBreak() {
    setLevels((ls) => [...ls, makeLevel({ isBreak: true, label: t('clock.break'), minutes: 10 })])
    setSaved(false)
  }

  function move(key: string, dir: -1 | 1) {
    setLevels((ls) => {
      const i = ls.findIndex((l) => l.key === key)
      const j = i + dir
      if (i < 0 || j < 0 || j >= ls.length) return ls
      const copy = [...ls]
      ;[copy[i], copy[j]] = [copy[j], copy[i]]
      return copy
    })
    setSaved(false)
  }

  function remove(key: string) {
    setLevels((ls) => (ls.length <= 1 ? ls : ls.filter((l) => l.key !== key)))
    setSaved(false)
  }

  /** Vervangt de structuur door een volledige ladder voor deze speelduur. */
  function generate(hours: number) {
    setLevels(generateLadder(hours))
    setSaved(false)
  }

  async function save() {
    setBusy(true)
    setError(null)

    const { error: nameErr } = await supabase
      .from('blind_structures')
      .update({ name: name.trim() || t('struct.newName') })
      .eq('id', structureId)

    if (nameErr) {
      setError(nameErr.message)
      setBusy(false)
      return
    }

    const { error: err } = await supabase.rpc('replace_blind_levels', {
      p_structure_id: structureId,
      p_levels: levels.map((l) => ({
        is_break: l.isBreak,
        // Een gewoon pauzewoord slaan we niet op: dan volgt het label
        // vanzelf de taal van de club in plaats van die van de maker.
        label: l.isBreak && !isDefaultBreakLabel(l.label) ? l.label.trim() : null,
        small_blind: l.isBreak ? 0 : l.smallBlind,
        big_blind: l.isBreak ? 0 : l.bigBlind,
        ante: l.isBreak ? 0 : l.ante,
        duration_s: Math.max(1, l.minutes) * 60,
      })),
    })

    if (err) {
      setError(err.message)
      setBusy(false)
      return
    }

    setSaved(true)
    setBusy(false)
    router.refresh()
  }

  return (
    <div className="space-y-6">
      <Field label={t('struct.name')}>
        <input
          value={name}
          onChange={(e) => { setName(e.target.value); setSaved(false) }}
          className={inputClass}
          placeholder={`${t('struct.new')}`}
        />
      </Field>

      <div className="flex flex-wrap items-center gap-3 rounded-[var(--radius)] border border-[var(--line)] bg-[var(--surface)] px-4 py-3">
        <div className="tnum text-sm">
          <span className="text-[var(--text-muted)]">{t('struct.duration')}</span>{' '}
          <span className="font-semibold">
            {Math.floor(totalMinutes / 60)}u{String(totalMinutes % 60).padStart(2, '0')}
          </span>
          <span className="mx-2 text-[var(--text-faint)]">·</span>
          <span className="text-[var(--text-muted)]">{playLevels} {t('struct.levels')}</span>
          <span className="mx-2 text-[var(--text-faint)]">·</span>
          <span className="text-[var(--text-muted)]">
            {levels.length - playLevels} {t('struct.breaks')}
          </span>
        </div>
        <div className="ml-auto flex flex-wrap gap-2">
          <span className="self-center text-xs text-[var(--text-faint)]">{t('struct.quickSetup')}</span>
          {[3, 4, 5, 6].map((h) => (
            <Button key={h} size="sm" onClick={() => generate(h)} type="button">{h} {t('struct.hours')}</Button>
          ))}
        </div>
      </div>

      <div>
        <SectionTitle>{t('struct.levels')}</SectionTitle>
        <Card padded={false} className="overflow-hidden">
          <div className="hidden grid-cols-[2.5rem_1fr_1fr_1fr_5rem_5.5rem] gap-2 border-b border-[var(--line)] px-4 py-2.5 text-[0.65rem] font-medium uppercase tracking-[0.14em] text-[var(--text-faint)] sm:grid">
            <span>#</span><span>Small blind</span><span>Big blind</span><span>Ante</span>
            <span>{t('struct.minutes')}</span><span />
          </div>

          {levels.map((l, i) => {
            const playIdx = levels.slice(0, i + 1).filter((x) => !x.isBreak).length
            return (
              <div
                key={l.key}
                className={`hairline grid grid-cols-2 items-center gap-2 px-4 py-3 sm:grid-cols-[2.5rem_1fr_1fr_1fr_5rem_5.5rem] ${
                  l.isBreak ? 'bg-[color-mix(in_oklab,var(--brand)_7%,transparent)]' : ''
                }`}
              >
                <span className="tnum text-sm text-[var(--text-faint)]">
                  {l.isBreak ? '—' : playIdx}
                </span>

                {l.isBreak ? (
                  <input
                    value={l.label}
                    onChange={(e) => patch(l.key, { label: e.target.value })}
                    placeholder={t('clock.break')}
                    className={`${inputClass} col-span-1 sm:col-span-3`}
                  />
                ) : (
                  <>
                    <NumberCell value={l.smallBlind} onChange={(v) => patch(l.key, { smallBlind: v })} />
                    <NumberCell value={l.bigBlind} onChange={(v) => patch(l.key, { bigBlind: v })} />
                    <NumberCell value={l.ante} onChange={(v) => patch(l.key, { ante: v })} />
                  </>
                )}

                <NumberCell value={l.minutes} onChange={(v) => patch(l.key, { minutes: v })} />

                <div className="flex items-center justify-end gap-1">
                  <IconButton label={t('struct.up')} disabled={i === 0} onClick={() => move(l.key, -1)}>↑</IconButton>
                  <IconButton label={t('struct.down')} disabled={i === levels.length - 1} onClick={() => move(l.key, 1)}>↓</IconButton>
                  <IconButton label={t('struct.remove')} disabled={levels.length <= 1} onClick={() => remove(l.key)} danger>×</IconButton>
                </div>
              </div>
            )
          })}
        </Card>

        <div className="mt-3 flex flex-wrap gap-2">
          <Button type="button" onClick={addLevel}>+ Level</Button>
          <Button type="button" onClick={addBreak}>+ Pauze</Button>
        </div>
      </div>

      {error && <Notice tone="error">{error}</Notice>}

      <div className="flex flex-wrap items-center gap-3">
        <Button variant="brand" size="lg" onClick={save} disabled={busy}>
          {busy ? t('common.saving') : t('common.save')}
        </Button>
        {saved && <span className="text-sm text-[var(--ok)]">{t('common.saved')}</span>}
        <a
          href={`/c/${clubSlug}/structuren`}
          className="text-sm text-[var(--text-faint)] underline underline-offset-4 hover:text-[var(--text-muted)]"
        >
          {t('struct.backToList')}
        </a>
      </div>
    </div>
  )
}

function NumberCell({ value, onChange }: { value: number; onChange: (v: number) => void }) {
  return (
    <input
      inputMode="numeric"
      value={value}
      onChange={(e) => {
        const n = Number.parseInt(e.target.value.replace(/\D/g, ''), 10)
        onChange(Number.isFinite(n) ? n : 0)
      }}
      className={`${inputClass} tnum px-2.5 py-1.5 text-sm`}
    />
  )
}

function IconButton({
  children, label, onClick, disabled, danger,
}: {
  children: React.ReactNode
  label: string
  onClick: () => void
  disabled?: boolean
  danger?: boolean
}) {
  return (
    <button
      type="button"
      aria-label={label}
      title={label}
      onClick={onClick}
      disabled={disabled}
      className={`grid size-7 place-items-center rounded-md border border-[var(--line)] text-sm transition-colors disabled:opacity-25 ${
        danger
          ? 'text-[var(--danger)] hover:bg-[color-mix(in_oklab,var(--danger)_15%,transparent)]'
          : 'text-[var(--text-muted)] hover:bg-[var(--surface-hover)]'
      }`}
    >
      {children}
    </button>
  )
}
