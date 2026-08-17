'use client'

import { useMemo, useState } from 'react'
import { useRouter } from 'next/navigation'
import Link from 'next/link'
import { createClient } from '@/lib/supabase/client'
import { Button, ButtonLink, Card, Field, Notice, inputClass } from '@/components/ui'
import { useT } from '@/lib/i18n/context'

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
  const t = useT()

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
  const [rebuyPrice, setRebuyPrice] = useState(centsToEuro(defaults?.buyinCents ?? 2000))
  const [rebuyFee, setRebuyFee] = useState(centsToEuro(defaults?.feeCents ?? 500))
  const [addonOn, setAddonOn] = useState(false)
  const [addonPrice, setAddonPrice] = useState('10.00')
  const [addonFee, setAddonFee] = useState('0.00')
  const [addonStack, setAddonStack] = useState('20000')
  const [bountyOn, setBountyOn] = useState(false)
  const [bounty, setBounty] = useState('5.00')
  const [structureId, setStructureId] = useState(structures[0]?.id ?? '')
  const [payoutId, setPayoutId] = useState(payouts[0]?.id ?? '')
  const [seasonId, setSeasonId] = useState(seasons[0]?.id ?? '')

  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const buyinCents = euroToCents(buyin)
  const feeCents = euroToCents(fee)
  const rebuyCents = euroToCents(rebuyPrice)
  const rebuyFeeCents = euroToCents(rebuyFee)
  const addonCents = euroToCents(addonPrice)
  const addonFeeCents = euroToCents(addonFee)
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
        // Altijd publiek: elk tornooi hoort op PokerLeague te verschijnen.
        // Wat een buitenstaander te zien krijgt zijn gebruikersnamen en
        // klasseringen, nooit persoonsgegevens — dat wordt afgedwongen
        // door de publieke views in de database, niet hier.
        player_visibility: 'public',
        buyin_cents: buyinCents,
        fee_cents: feeCents,
        // Een rebuy en een re-entry volgen dezelfde afspraak: opnieuw
        // inkopen. Wat naar de pot gaat en wat naar de club, staat hier los
        // van de buy-in — clubs doen dat niet allemaal hetzelfde.
        rebuy_cents: rebuyCents,
        rebuy_fee_cents: rebuyFeeCents,
        addon_fee_cents: addonOn ? addonFeeCents : null,
        bounty_mode: bountyOn ? 'fixed' : 'none',
        bounty_cents: bountyCents,
        starting_stack: Number.parseInt(stack, 10) || 0,
        // Leeg laten betekent: een addon kost de buy-in en geeft een
        // startstack. Wie hem aanzet mag beide apart zetten, want een addon
        // is bij de meeste clubs goedkoper én meer chips dan een buy-in.
        addon_cents: addonOn ? addonCents : null,
        addon_stack: addonOn ? (Number.parseInt(addonStack, 10) || null) : null,
        max_reentries: Number.parseInt(reentries, 10) || 0,
        late_reg_level: lateReg === '' ? null : Number.parseInt(lateReg, 10),
      })
      .select('id')
      .single<{ id: string }>()

    if (err) {
      setError(
        err.code === '42501' || err.message.includes('row-level security')
          ? t('tour.noRights')
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
      <Field label={t('tour.name')}>
        <input
          required
          value={name}
          onChange={(e) => setName(e.target.value)}
          placeholder={t('tour.namePlaceholder')}
          className={inputClass}
        />
      </Field>

      <Field label={t('tour.when')}>
        <input
          type="datetime-local"
          required
          value={when}
          onChange={(e) => setWhen(e.target.value)}
          className={inputClass}
        />
      </Field>

      {/* Het geld, in één overzicht.
          Per soort inkoop twee bedragen: wat naar de prijzenpot gaat en wat
          de club houdt. Dat waren eerst twee losse velden voor de buy-in en
          één afspraak die stilzwijgend ook voor rebuys gold — maar clubs
          doen dat niet allemaal hetzelfde, en je moet kunnen aantonen wat
          een speler betaald heeft. Naast elke rij staat het totaal dat de
          speler afrekent, want dát is het cijfer aan de kassa. */}
      <Card>
        <div className="grid grid-cols-[1fr_auto_auto_auto] items-end gap-x-3 gap-y-3">
          <span />
          <span className="text-center text-xs uppercase tracking-widest text-[var(--text-faint)]">
            {t('tour.toPot')}
          </span>
          <span className="text-center text-xs uppercase tracking-widest text-[var(--text-faint)]">
            {t('tour.toClub')}
          </span>
          <span className="text-right text-xs uppercase tracking-widest text-[var(--text-faint)]">
            {t('tour.total')}
          </span>

          <MoneyRow
            label={t('tour.buyin')}
            sub={t('tour.buyinAlsoReentry')}
            pot={buyin} onPot={setBuyin}
            fee={fee} onFee={setFee}
            totalCents={buyinCents + feeCents + bountyCents}
            currency={currency}
          />

          <MoneyRow
            label={t('tour.rebuy')}
            pot={rebuyPrice} onPot={setRebuyPrice}
            fee={rebuyFee} onFee={setRebuyFee}
            totalCents={rebuyCents + rebuyFeeCents + (bountyOn ? bountyCents : 0)}
            currency={currency}
          />

          {addonOn && (
            <MoneyRow
              label={t('tour.addonRow')}
              pot={addonPrice} onPot={setAddonPrice}
              fee={addonFee} onFee={setAddonFee}
              totalCents={addonCents + addonFeeCents}
              currency={currency}
            />
          )}
        </div>

        <p className="mt-3 text-xs leading-relaxed text-[var(--text-faint)]">
          {t('tour.moneyHint')}
        </p>
      </Card>

      <Card>
        <label className="flex items-center gap-3">
          <input
            type="checkbox"
            checked={addonOn}
            onChange={(e) => setAddonOn(e.target.checked)}
            className="size-4"
          />
          <span>{t('tour.addon')}</span>
        </label>
        {addonOn && (
          <div className="mt-3">
            <Field label={t('tour.addonStack')} hint={t('tour.addonHint')}>
              <input inputMode="numeric" value={addonStack}
                     onChange={(e) => setAddonStack(e.target.value)} className={inputClass} />
            </Field>
          </div>
        )}
      </Card>

      <Card>
        <label className="flex items-center gap-3">
          <input
            type="checkbox"
            checked={bountyOn}
            onChange={(e) => setBountyOn(e.target.checked)}
            className="size-4"
          />
          <span>{t('tour.bounty')}</span>
        </label>
        {bountyOn && (
          <div className="mt-3">
            <input inputMode="decimal" value={bounty} onChange={(e) => setBounty(e.target.value)} className={inputClass} />
            <p className="mt-1 text-xs text-[var(--text-faint)]">
              {t('tour.bountyHint')}
            </p>
          </div>
        )}
      </Card>

      <p className="text-sm text-[var(--text-muted)]">
        {t('tour.totalPerPlayer')} <span className="tnum font-semibold text-[var(--text)]">
          {new Intl.NumberFormat('nl-BE', { style: 'currency', currency }).format(totalCents / 100)}
        </span>
      </p>

      {overLimit && (
        <Notice tone="warn">
          {t('tour.overLimit')}
        </Notice>
      )}

      <div className="grid gap-4 sm:grid-cols-3">
        <Field label={t('tour.startingStack')}>
          <input inputMode="numeric" value={stack} onChange={(e) => setStack(e.target.value)} className={inputClass} />
        </Field>
        <Field label={t('tour.maxRebuys')} hint={t('tour.maxRebuysHint')}>
          <input inputMode="numeric" value={reentries} onChange={(e) => setReentries(e.target.value)} className={inputClass} />
        </Field>
        <Field label={t('tour.lateReg')} hint={t('tour.lateRegHint')}>
          <input inputMode="numeric" value={lateReg} onChange={(e) => setLateReg(e.target.value)} className={inputClass} />
        </Field>
      </div>

      <Field
        label={t('tour.structure')}
        hint={
          structures.length === 0
            ? undefined
            : t('tour.structureHint')
        }
      >
        {structures.length === 0 ? (
          <Notice tone="warn">
            {t('tour.noStructure')}{' '}
            <Link href={`/c/${clubSlug}/structuren`} className="underline">
              {t('tour.noStructureLink')}
            </Link>{' '}
            {t('tour.noStructureTail')}
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
            <ButtonLink href={`/c/${clubSlug}/structuren`} className="shrink-0">{t('tour.manage')}</ButtonLink>
          </div>
        )}
      </Field>

      <div className="grid gap-4 sm:grid-cols-2">
        <Field label={t('tour.payouts')}>
          <select value={payoutId} onChange={(e) => setPayoutId(e.target.value)} className={inputClass}>
            {payouts.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
          </select>
        </Field>
        <Field label={t('tour.season')} hint={t('tour.seasonHint')}>
          <select value={seasonId} onChange={(e) => setSeasonId(e.target.value)} className={inputClass}>
            <option value="">{t('tour.seasonNone')}</option>
            {seasons.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
          </select>
        </Field>
      </div>

      {error && (
        <Notice tone="error">{error}</Notice>
      )}

      <div className="flex gap-3">
        <Button type="submit" variant="brand" size="lg" disabled={busy || structures.length === 0}>
          {busy ? t('common.busy') : t('tour.create')}
        </Button>
        <ButtonLink href={`/c/${clubSlug}`} size="lg">{t('common.cancel')}</ButtonLink>
      </div>
    </form>
  )
}

/**
 * Eén regel in het geldoverzicht: wat naar de pot gaat, wat de club houdt,
 * en wat de speler in totaal afrekent.
 *
 * Het totaal is berekend en niet in te tikken. Anders krijg je drie velden
 * die elkaar tegenspreken, en dan is het de vraag welke van de drie klopt op
 * het moment dat je het aan iemand moet uitleggen.
 */
function MoneyRow({
  label, sub, pot, onPot, fee, onFee, totalCents, currency,
}: {
  label: string
  sub?: string
  pot: string
  onPot: (v: string) => void
  fee: string
  onFee: (v: string) => void
  totalCents: number
  currency: string
}) {
  return (
    <>
      <span className="min-w-0">
        <span className="block text-sm font-medium">{label}</span>
        {sub && <span className="block text-xs text-[var(--text-faint)]">{sub}</span>}
      </span>
      <input
        inputMode="decimal"
        aria-label={label}
        value={pot}
        onChange={(e) => onPot(e.target.value)}
        className={`${inputClass} w-24 text-right tabular-nums`}
      />
      <input
        inputMode="decimal"
        aria-label={label}
        value={fee}
        onChange={(e) => onFee(e.target.value)}
        className={`${inputClass} w-24 text-right tabular-nums`}
      />
      <span className="w-24 text-right text-sm font-semibold tabular-nums">
        {new Intl.NumberFormat('nl-BE', { style: 'currency', currency }).format(totalCents / 100)}
      </span>
    </>
  )
}
