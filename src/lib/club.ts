import { cache } from 'react'
import { createClient } from '@/lib/supabase/server'

/**
 * Eén club ophalen op basis van zijn slug.
 *
 * `cache` zorgt dat layout en pagina binnen hetzelfde verzoek dezelfde query
 * delen in plaats van hem twee keer te doen.
 */
export interface Club {
  id: string
  slug: string
  name: string
  city: string | null
  currency: string
  timezone: string
  locale: string
  logo_url: string | null
  primary_color: string | null
}

export const getClub = cache(async (slug: string): Promise<Club | null> => {
  const supabase = await createClient()
  const { data } = await supabase
    .from('clubs')
    .select('id,slug,name,city,currency,timezone,locale,logo_url,primary_color')
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
 * bij een club met een gele of lichtblauwe huisstijl.
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
