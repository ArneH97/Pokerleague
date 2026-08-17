import { cache } from 'react'
import { createClient } from '@/lib/supabase/server'

/**
 * Eén club ophalen op basis van zijn slug.
 *
 * `cache` zorgt dat layout en pagina binnen hetzelfde verzoek dezelfde query
 * delen in plaats van hem twee keer te doen.
 */

/**
 * De huisstijl van een club is meer dan één accentkleur.
 *
 * Cutoff is goud op diepzwart; een andere club kan licht en blauw zijn. Wie
 * alleen een accentkleur laat instellen, dwingt elke club in hetzelfde jasje.
 * Vandaar dat een club ook zijn eigen vlakken mag meebrengen. Alles is
 * optioneel: wat je niet invult, valt terug op het platformthema.
 */
export interface ClubTheme {
  bg?: string
  surface?: string
  surface2?: string
  surfaceHover?: string
  line?: string
  lineStrong?: string
  text?: string
  textMuted?: string
  textFaint?: string
}

export interface Club {
  id: string
  slug: string
  name: string
  city: string | null
  currency: string
  timezone: string
  locale: string
  logo_url: string | null
  /** Alleen het beeldmerk, vrijstaand op een doorzichtige achtergrond. */
  mark_url: string | null
  primary_color: string | null
  settings: { theme?: ClubTheme } | null

  /** Het visitekaartje. Allemaal optioneel; de pagina laat weg wat leeg is. */
  intro: string | null
  address_line: string | null
  maps_url: string | null
  play_rhythm: string | null
  contact_email: string | null
  contact_phone: string | null
  /** Openingsdag. Zolang die er is en er niets gespeeld is, telt de pagina af. */
  opens_on: string | null
}

export const getClub = cache(async (slug: string): Promise<Club | null> => {
  const supabase = await createClient()
  const { data } = await supabase
    .from('clubs')
    .select('id,slug,name,city,currency,timezone,locale,logo_url,mark_url,primary_color,settings,'
      + 'intro,address_line,maps_url,play_rhythm,contact_email,contact_phone,opens_on')
    .eq('slug', slug)
    .eq('is_active', true)
    .maybeSingle<Club>()
  return data ?? null
})

/** Rol van de ingelogde gebruiker binnen deze club, of null. */
export const getClubRole = cache(async (clubId: string): Promise<string | null> => {
  const supabase = await createClient()
  const { data } = await supabase
    .from('club_members')
    .select('role')
    .eq('club_id', clubId)
    .maybeSingle<{ role: string }>()
  return data?.role ?? null
})

/**
 * Een leesbare tekstkleur bij de clubkleur. Donkere merkkleuren krijgen witte
 * tekst, lichte krijgen zwarte — anders is een knop in clubkleur onleesbaar
 * bij een club met een gouden of lichtblauwe huisstijl.
 */
export function readableTextOn(hex: string | null): string {
  if (!hex) return '#ffffff'
  const m = /^#?([0-9a-f]{6})$/i.exec(hex.trim())
  if (!m) return '#ffffff'
  const n = parseInt(m[1], 16)
  const [r, g, b] = [(n >> 16) & 255, (n >> 8) & 255, n & 255]
  // Relatieve helderheid volgens WCAG.
  const lin = (c: number) => {
    const s = c / 255
    return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4
  }
  const luminance = 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
  return luminance > 0.45 ? '#0a0a0a' : '#ffffff'
}

/** Zet de huisstijl van een club om naar CSS-variabelen. */
export function themeVars(club: Club): React.CSSProperties {
  const t = club.settings?.theme ?? {}
  const brand = club.primary_color ?? '#10b981'

  const vars: Record<string, string> = {
    '--brand': brand,
    '--on-brand': readableTextOn(brand),
  }

  const map: [keyof ClubTheme, string][] = [
    ['bg', '--bg'],
    ['surface', '--surface'],
    ['surface2', '--surface-2'],
    ['surfaceHover', '--surface-hover'],
    ['line', '--line'],
    ['lineStrong', '--line-strong'],
    ['text', '--text'],
    ['textMuted', '--text-muted'],
    ['textFaint', '--text-faint'],
  ]

  for (const [key, cssVar] of map) {
    const value = t[key]
    if (typeof value === 'string' && value.trim() !== '') vars[cssVar] = value
  }

  return vars as React.CSSProperties
}
