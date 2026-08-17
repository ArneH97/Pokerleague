'use client'

import { useMemo, useState } from 'react'
import { useRouter } from 'next/navigation'
import Link from 'next/link'
import { createClient } from '@/lib/supabase/client'
import { Button, ButtonLink, Card, Field, Notice, inputClass } from '@/components/ui'

/**
 * Tornooi aanmaken.
 *
 * Bedragen worden in euro ingevuld en in centen bewaard — nooit floats, want
 * een halve cent in een prijzenpot betekent dat de kas 's avonds niet klopt.
 *
 * De structuur is verplicht: zonder blindstructuur heeft de klok niets om af
 * te tellen, en dat merk je liever nu dan om acht uur 's avonds.
 */

export interface Option { id: string; name: string; extra?: string }

interface Props {
  clubSlug: string
  clubId: string
  currency: string
  structures: Option[]
  payouts: Option[]
  seasons: Option[]
  defaults?: { buyinCents: number; feeCents: number; startingStack: number }
}

function euroToCents(v: string): number {
  const n = Number.parseFloat(v.replace(',', '.'))
  return Number.isFinite(n) ? Math.round(n * 100) : 0
}

function centsToEuro(c: number): string {
  return (c / 100).toFixed(2)
}

/** Datum-tijd voor een <input type="datetime-local">, in lokale tijd. */
function toLocalInput(d: Date): string {
  const pad = (n: number) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`
}

export function TournamentForm({
  clubSlug, clubId, currency, structures, payouts, seasons, defaults,
}: Props) {
  const router = useRouter()
  const supabase = useMemo(() => createClient(), [])

  const nextFriday = useMemo(() => {
    const d = new Date()
    d.setDate(d.getDate() + ((5 - d.getDay() + 7) % 7 || 7))
    d.setHours(20, 0, 0, 0)
    return toLocalInput(d)
  }, [])

  const [name, setName] = useState('')
  const [when, setWhen] = useState(nextFriday)
  const [buyin, setBuyin] = useState(centsToEuro(defaults?.buyinCents ?? 2000))
  const [fee, setFee] = useState(centsToEuro(defaults?.feeCents ?? 500))
  const [stack, setStack] = useState(String(defaults?.startingStack ?? 20000))
  const [reentries, setReentries] = useState('1')
  const [lateReg, setLateReg] = useState('6')
  const [bountyOn, setBountyOn] = useState(false)
  const [bounty, setBounty] = useState('5.00')
  const [structureId, setStructureId] = useState(structures[0]?.id ?? '')
  const [payoutId, setPayoutId] = useState(payouts[0]?.id ?? '')
  const [seasonId, setSeasonId] = useState(seasons[0]?.id ?? '')
  const [visibility, setVisibility] = useState<'private' | 'members' | 'public'>('members')

  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const buyinCents = euroToCents(buyin)
  const feeCents = euroToCents(fee)
  const bountyCents = bountyOn ? euroToCents(bounty) : 0
  const totalCents = buyinCents + feeCents + bountyCents

  // Gedoogbeleid: maximaal €50 inzet per tornooi. Waarschuwen, niet blokkeren
  // — het is beleid en geen wet, en de club stelt de grens zelf in.
  const overLimit = totalCents > 5000

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault()
    setBusy(true)
    setError(null)

    const { data, error: err } = await supabase
      .from('tournaments')
      .insert({
        club_id: clubId,
        season_id: seasonId || null,
        structure_id: structureId || null,
        payout_template_id: payoutId || null,
        name: name.trim(),
        scheduled_at: new Date(when).toISOString(),
        status: 'scheduled',
        player_visibility: visibility,
        buyin_cents: buyinCents,
        fee_cents: feeCents,
        bounty_mode: bountyOn ? 'fixed' : 'none',
        bounty_cents: bountyCents,
        starting_stack: Number.parseInt(stack, 10) || 0,
        max_reentries: Number.parseInt(reentries, 10) || 0,
        late_reg_level: lateReg === '' ? null : Number.parseInt(lateReg, 10),
      })
      .select('id')
      .single<{ id: string }>()

    if (err) {
      setError(
        err.code === '42501' || err.message.includes('row-level security')
          ? 'Je hebt geen rechten om tornooien aan te maken bij deze club.'
          : err.message,
      )
      setBusy(false)
      return
    }

    router.push(`/c/${clubSlug}/floor/${data.id}`)
    router.refresh()
  }

  return (
    <form onSubmit={onSubmit} className="space-y-6">
      <Field label="Naam">
        <input
          required
          value={name}
          onChange={(e) => setName(e.target.value)}
          placeholder="Vrijdagavondtornooi"
          className={inputClass}
        />
      </Field>

      <Field label="Wanneer">
        <input
          type="datetime-local"
          required
          value={when}
          onChange={(e) => setWhen(e.target.value)}
          className={inputClass}
        />
      </Field>

      <div className="grid gap-4 sm:grid-cols-2">
        <Field label={`Buy-in (${currency})`} hint="Gaat naar de prijzenpot">
          <input inputMode="decimal" value={buyin} onChange={(e) => setBuyin(e.target.value)} className={inputClass} />
        </Field>
        <Field label={`Clubbijdrage (${currency})`} hint="Blijft bij de club">
          <input inputMode="decimal" value={fee} onChange={(e) => setFee(e.target.value)} className={inputClass} />
        </Field>
      </div>

      <Card>
        <label className="flex items-center gap-3">
          <input
            type="checkbox"
            checked={bountyOn}
            onChange={(e) => setBountyOn(e.target.checked)}
            className="size-4"
          />
          <span>Bounty per knock-out</span>
        </label>
        {bountyOn && (
          <div className="mt-3">
            <input inputMode="decimal" value={bounty} onChange={(e) => setBounty(e.target.value)} className={inputClass} />
            <p className="mt-1 text-xs text-[var(--text-faint)]">
              Wordt rechtstreeks uitbetaald aan wie de speler uitschakelt, buiten de prijzenpot om.
            </p>
          </div>
        )}
      </Card>

      <p className="text-sm text-[var(--text-muted)]">
        Totaal per speler: <span className="tnum font-semibold text-[var(--text)]">
          {new Intl.NumberFormat('nl-BE', { style: 'currency', currency }).format(totalCents / 100)}
        </span>
      </p>

      {overLimit && (
        <Notice tone="warn">
          Boven de €50 die het gedoogbeleid van de Kansspelcommissie toelaat per
          tornooi. Je kan doorgaan — de grens staat per club ingesteld — maar
          weet dat je er dan buiten valt.
        </Notice>
      )}

      <div className="grid gap-4 sm:grid-cols-3">
        <Field label="Startstack">
          <input inputMode="numeric" value={stack} onChange={(e) => setStack(e.target.value)} className={inputClass} />
        </Field>
        <Field label="Re-entries" hint="Max. per speler">
          <input inputMode="numeric" value={reentries} onChange={(e) => setReentries(e.target.value)} className={inputClass} />
        </Field>
        <Field label="Late reg t/m level" hint="Leeg = onbeperkt">
          <input inputMode="numeric" value={lateReg} onChange={(e) => setLateReg(e.target.value)} className={inputClass} />
        </Field>
      </div>

      <Field
        label="Blindstructuur"
        hint={
          structures.length === 0
            ? undefined
            : 'Bepaalt wat de klok aftelt'
        }
      >
        {structures.length === 0 ? (
          <Notice tone="warn">
            Deze club heeft nog geen blindstructuur.{' '}
            <Link href={`/c/${clubSlug}/structuren`} className="underline">
              Maak er eerst een aan
            </Link>{' '}
            — zonder structuur heeft de klok niets om af te tellen.
          </Notice>
        ) : (
          <div className="flex gap-2">
            <select value={structureId} onChange={(e) => setStructureId(e.target.value)} className={inputClass}>
              {structures.map((s) => (
                <option key={s.id} value={s.id}>
                  {s.name}{s.extra ? ` — ${s.extra}` : ''}
                </option>
              ))}
            </select>
            <ButtonLink href={`/c/${clubSlug}/structuren`} className="shrink-0">Beheren</ButtonLink>
          </div>
        )}
      </Field>

      <div className="grid gap-4 sm:grid-cols-2">
        <Field label="Prijzenverdeling">
          <select value={payoutId} onChange={(e) => setPayoutId(e.target.value)} className={inputClass}>
            {payouts.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
          </select>
        </Field>
        <Field label="Seizoen" hint="Voor de ranking">
          <select value={seasonId} onChange={(e) => setSeasonId(e.target.value)} className={inputClass}>
            <option value="">Telt niet mee</option>
            {seasons.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
          </select>
        </Field>
      </div>

      <Field label="Zichtbaar voor">
        <select
          value={visibility}
          onChange={(e) => setVisibility(e.target.value as typeof visibility)}
          className={inputClass}
        >
          <option value="members">Leden van de club</option>
          <option value="public">Iedereen, ook op PokerLeague</option>
          <option value="private">Alleen de staf</option>
        </select>
      </Field>

      {error && (
        <Notice tone="error">{error}</Notice>
      )}

      <div className="flex gap-3">
        <Button type="submit" variant="brand" size="lg" disabled={busy || structures.length === 0}>
          {busy ? 'Bezig…' : 'Tornooi aanmaken'}
        </Button>
        <ButtonLink href={`/c/${clubSlug}`} size="lg">Annuleren</ButtonLink>
      </div>
    </form>
  )
}

