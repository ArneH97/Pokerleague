/**
 * Van domeinnaam naar club.
 *
 * Elke club krijgt zijn eigen domein — Cutoff draait op app.cutoff.be, en het
 * spelersplatform op pokerleague.be. Onder de motorkap is dat dezelfde app:
 * de proxy schrijft een verzoek op een clubdomein door naar /c/<slug>/…, zodat
 * de club schone URL's ziet zonder clubnaam erin.
 *
 * Waarom niet gewoon subdomeinen van één hoofddomein? Omdat een club die
 * betaalt voor "hun eigen platform" ook hun eigen adres verwacht. Dat kost
 * hier één opzoeking, en die cachen we.
 */

/** Hoe lang een gevonden koppeling blijft hangen voor we opnieuw kijken. */
const TTL_MS = 5 * 60_000

interface Entry {
  slug: string | null
  at: number
}

// Per serverinstantie. Serverless betekent dat elke instantie zijn eigen
// cache opbouwt; dat is prima, het gaat om het vermijden van een opzoeking
// per verzoek, niet om een gedeelde waarheid.
const cache = new Map<string, Entry>()

export function normalizeHost(host: string | null): string {
  return (host ?? '').toLowerCase().split(':')[0].replace(/^www\./, '')
}

/** Domeinen die nooit bij een club horen. */
export function isPlatformHost(host: string): boolean {
  const league = normalizeHost(process.env.NEXT_PUBLIC_LEAGUE_DOMAIN ?? 'pokerleague.be')
  return (
    host === league ||
    host === 'localhost' ||
    host === '127.0.0.1' ||
    host.endsWith('.vercel.app')
  )
}

/**
 * Zoekt de club bij een domein. Geeft null als het domein niet van een club
 * is — dan blijft het pad ongewijzigd en werkt /c/<slug>/… gewoon rechtstreeks.
 */
export async function clubSlugForHost(host: string): Promise<string | null> {
  if (!host || isPlatformHost(host)) return null

  const hit = cache.get(host)
  if (hit && Date.now() - hit.at < TTL_MS) return hit.slug

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL
  const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY
  if (!url || !key) return null

  try {
    const res = await fetch(
      `${url}/rest/v1/clubs?select=slug&is_active=eq.true&custom_domain=ilike.${encodeURIComponent(host)}&limit=1`,
      {
        headers: { apikey: key, Authorization: `Bearer ${key}` },
        cache: 'no-store',
      },
    )
    const rows = res.ok ? ((await res.json()) as { slug: string }[]) : []
    const slug = rows[0]?.slug ?? null
    cache.set(host, { slug, at: Date.now() })
    return slug
  } catch {
    // Database onbereikbaar: liever het verzoek gewoon doorlaten dan een
    // foutpagina. Zonder doorschrijving werkt /c/<slug>/… nog steeds.
    cache.set(host, { slug: null, at: Date.now() })
    return null
  }
}

/** Paden die nooit naar een clubomgeving mogen worden doorgeschreven. */
export function isPassthroughPath(pathname: string): boolean {
  return (
    pathname.startsWith('/c/') ||
    pathname.startsWith('/api/') ||
    pathname.startsWith('/auth/') ||
    pathname.startsWith('/_next/') ||
    pathname === '/favicon.ico'
  )
}
