'use server'

import { revalidatePath } from 'next/cache'
import type { Key } from '@/lib/i18n/dictionaries'
import { createClient } from '@/lib/supabase/server'

/**
 * De serveracties achter het instellingenscherm.
 *
 * Geen enkele van deze functies controleert zelf of iemand mag wijzigen, en
 * dat is met opzet. De poort staat in de database: `clubs_update`,
 * `payout_templates_write`, `ranking_configs_write` en `seasons_write` laten
 * alleen owner en admin door. Zou ik hier ook nog eens gaan controleren, dan
 * staan er twee waarheden over wie wat mag en drift er ooit één weg. Wat een
 * floor probeert te bewaren komt terug als een foutmelding uit Postgres, en
 * dat is precies goed.
 *
 * Wél afgedwongen: welke kolommen bestaan. Een formulier mag `slug` niet
 * meesturen — dan verandert het adres van de club onder de floor vandaan —
 * en `custom_domain` niet, want daar hangt DNS aan die hier niet meeverhuist.
 */

/**
 * Wat een formulier terugkrijgt.
 *
 * `error` is een **sleutel** uit het woordenboek en geen zin. Hier op de
 * server weten we niet welke taal de kijker gekozen heeft — die keuze zit in
 * een koekje dat het formulier al gelezen heeft — dus vertalen gebeurt aan de
 * andere kant. Stonden hier zinnen, dan kreeg een Franstalige floor midden in
 * een Frans scherm ineens Nederlands terug.
 *
 * `detail` is voor wat niet te vertalen valt: de regel die de gebruiker zelf
 * intikte, of het getal dat niet klopt.
 */
type Result = { ok: true } | { ok: false; error: Key; detail?: string }

/** Leest een tekstveld en maakt van leegte netjes null. */
function text(fd: FormData, key: string): string | null {
  const v = fd.get(key)
  if (typeof v !== 'string') return null
  const t = v.trim()
  return t === '' ? null : t
}

function num(fd: FormData, key: string, fallback: number): number {
  const v = Number(text(fd, key) ?? '')
  return Number.isFinite(v) ? v : fallback
}

/** Van een fout uit Postgres naar een sleutel. */
function human(message: string): { error: Key; detail?: string } {
  return message.includes('row-level security') || message.includes('Geen rechten')
    ? { error: 'db.noRightsEdit' }
    : { error: 'common.error', detail: message }
}

async function save(
  slug: string,
  table: 'clubs' | 'payout_templates' | 'ranking_configs' | 'seasons',
  id: string,
  patch: Record<string, unknown>,
): Promise<Result> {
  const supabase = await createClient()
  const { error } = await supabase.from(table).update(patch).eq('id', id)
  if (error) return { ok: false, ...human(error.message) }

  // De publieke pagina's van de club lezen dit ook, dus die moeten mee.
  revalidatePath(`/c/${slug}`, 'layout')
  return { ok: true }
}

// ---------------------------------------------------------------------------
// De club zelf
// ---------------------------------------------------------------------------

export async function saveClubBasics(_prev: Result | null, fd: FormData): Promise<Result> {
  const slug = String(fd.get('slug'))
  const id = String(fd.get('id'))
  const naam = text(fd, 'name')
  if (!naam) return { ok: false, error: 'set.errNoName' }

  return save(slug, 'clubs', id, {
    name: naam,
    city: text(fd, 'city'),
    locale: text(fd, 'locale') ?? 'nl',
    timezone: text(fd, 'timezone') ?? 'Europe/Brussels',
    currency: text(fd, 'currency') ?? 'EUR',
  })
}

export async function saveClubLook(_prev: Result | null, fd: FormData): Promise<Result> {
  const slug = String(fd.get('slug'))
  const id = String(fd.get('id'))
  const kleur = text(fd, 'primary_color')

  // Een halve kleurcode maakt de hele huisstijl stuk, en dat merk je pas op
  // de beamer. Hier weigeren is vriendelijker dan daar.
  if (kleur && !/^#[0-9a-f]{6}$/i.test(kleur)) {
    return { ok: false, error: 'set.errColor' }
  }

  return save(slug, 'clubs', id, {
    logo_url: text(fd, 'logo_url'),
    mark_url: text(fd, 'mark_url'),
    primary_color: kleur,
  })
}

export async function saveClubPublic(_prev: Result | null, fd: FormData): Promise<Result> {
  const slug = String(fd.get('slug'))
  const id = String(fd.get('id'))

  return save(slug, 'clubs', id, {
    intro: text(fd, 'intro'),
    address_line: text(fd, 'address_line'),
    maps_url: text(fd, 'maps_url'),
    play_rhythm: text(fd, 'play_rhythm'),
    contact_email: text(fd, 'contact_email'),
    contact_phone: text(fd, 'contact_phone'),
    opens_on: text(fd, 'opens_on'),
    public_names: fd.get('public_names') === 'on',
  })
}

export async function saveCompliance(_prev: Result | null, fd: FormData): Promise<Result> {
  const slug = String(fd.get('slug'))
  const id = String(fd.get('id'))

  return save(slug, 'clubs', id, {
    compliance: {
      profile: text(fd, 'profile') ?? 'be_tolerance',
      max_buyin_cents: Math.round(num(fd, 'max_buyin', 50) * 100),
      max_daily_cents: Math.round(num(fd, 'max_daily', 100) * 100),
      max_reentries: Math.max(0, Math.round(num(fd, 'max_reentries', 1))),
      allow_cash_games: fd.get('allow_cash_games') === 'on',
      min_age: Math.max(0, Math.round(num(fd, 'min_age', 18))),
      enforce: text(fd, 'enforce') ?? 'warn',
    },
  })
}

// ---------------------------------------------------------------------------
// Prijzenverdeling
// ---------------------------------------------------------------------------

/**
 * Het sjabloon komt binnen als één veld per rij, gescheiden door regels:
 * "van;tot;percentages". Dat leest een mens en het reist door een gewoon
 * formulier zonder JavaScript.
 */
export async function savePayoutTemplate(_prev: Result | null, fd: FormData): Promise<Result> {
  const slug = String(fd.get('slug'))
  const id = String(fd.get('id'))
  const ruw = (text(fd, 'tiers') ?? '').split('\n').map((r) => r.trim()).filter(Boolean)

  const tiers: { min_entries: number; max_entries: number; percentages: number[] }[] = []
  for (const regel of ruw) {
    const [van, tot, pct] = regel.split(';').map((x) => (x ?? '').trim())
    const min = Number(van)
    const max = Number(tot)
    const percentages = (pct ?? '').split(',').map((x) => Number(x.trim())).filter((n) => n > 0)

    if (!Number.isFinite(min) || !Number.isFinite(max) || min < 1 || max < min) {
      return { ok: false, error: 'set.errRowShape', detail: regel }
    }
    if (percentages.length === 0) {
      return { ok: false, error: 'set.errNoPercentages', detail: regel }
    }
    const som = percentages.reduce((a, b) => a + b, 0)
    // Niet exact 100 eisen: clubs rekenen met 33/21/14/… en dat is 99,x. Wat
    // overblijft gaat naar plaats 1, en dat is al zo geregeld. Ver ernaast is
    // wel een tikfout.
    if (som < 95 || som > 105) {
      return { ok: false, error: 'set.errSum', detail: `${regel} → ${som}` }
    }
    tiers.push({ min_entries: min, max_entries: max, percentages })
  }

  if (tiers.length === 0) {
    return { ok: false, error: 'set.errEmpty' }
  }

  return save(slug, 'payout_templates', id, {
    name: text(fd, 'name') ?? 'Standaard',
    rounding: Math.max(100, Math.round(num(fd, 'rounding', 1) * 100)),
    tiers,
  })
}

// ---------------------------------------------------------------------------
// Punten
// ---------------------------------------------------------------------------

export async function saveRankingConfig(_prev: Result | null, fd: FormData): Promise<Result> {
  const slug = String(fd.get('slug'))
  const id = String(fd.get('id'))
  const method = text(fd, 'method') ?? 'sqrt_ratio'

  let params: Record<string, unknown> = {}
  if (method === 'sqrt_ratio' || method === 'pokerstars') {
    params = { multiplier: num(fd, 'multiplier', 10) }
  } else if (method === 'linear') {
    params = {
      base: num(fd, 'base', 100),
      decrement: num(fd, 'decrement', 5),
      floor: num(fd, 'floor', 1),
    }
  } else if (method === 'fixed_table') {
    const tabel = (text(fd, 'table') ?? '')
      .split(',').map((x) => Number(x.trim())).filter((n) => Number.isFinite(n))
    if (tabel.length === 0) {
      return { ok: false, error: 'set.errPointsTable' }
    }
    params = { table: tabel, tail: num(fd, 'tail', 0) }
  }

  const bestN = text(fd, 'count_best_n')

  return save(slug, 'ranking_configs', id, {
    name: text(fd, 'name') ?? 'Klassement',
    method,
    params,
    bonus_per_ko: num(fd, 'bonus_per_ko', 0),
    bonus_entry: num(fd, 'bonus_entry', 0),
    count_best_n: bestN === null ? null : Math.max(1, Math.round(Number(bestN))),
    min_tournaments: Math.max(0, Math.round(num(fd, 'min_tournaments', 0))),
  })
}

// ---------------------------------------------------------------------------
// Seizoenen
// ---------------------------------------------------------------------------

export async function saveSeason(_prev: Result | null, fd: FormData): Promise<Result> {
  const slug = String(fd.get('slug'))
  const id = text(fd, 'id')
  const clubId = String(fd.get('club_id'))
  const naam = text(fd, 'name')
  const start = text(fd, 'starts_on')

  if (!naam) return { ok: false, error: 'set.errSeasonName' }
  if (!start) return { ok: false, error: 'set.errSeasonStart' }

  const patch = {
    name: naam,
    starts_on: start,
    ends_on: text(fd, 'ends_on'),
    ranking_config_id: text(fd, 'ranking_config_id'),
    is_active: fd.get('is_active') === 'on',
  }

  const supabase = await createClient()
  const { error } = id
    ? await supabase.from('seasons').update(patch).eq('id', id)
    : await supabase.from('seasons').insert({ ...patch, club_id: clubId })

  if (error) return { ok: false, ...human(error.message) }
  revalidatePath(`/c/${slug}`, 'layout')
  return { ok: true }
}
