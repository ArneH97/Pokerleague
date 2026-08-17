/**
 * Van domeinnaam naar club.
 *
 * Eén app, veel adressen. Een verzoek op een clubdomein wordt doorgeschreven
 * naar /c/<slug>/…, zodat de club schone URL's ziet zonder zijn eigen naam er
 * nog eens in.
 *
 * Er zijn twee soorten clubadressen, en dat is bewust:
 *
 * **cutoff.pokerleague.be** — werkt vanaf het moment dat de club bestaat. Eén
 * jokerteken in DNS en in de hosting, één keer door ons gezet, en elke
 * volgende club is meteen bereikbaar zonder dat er iemand iets moet doen. Dat
 * is wat je wil op de dag dat een club zich aanmeldt.
 *
 * **app.cutoff.be** — het eigen domein van de club. Mooier op een affiche, en
 * een club die betaalt voor "hun eigen platform" verwacht ook hun eigen adres.
 * Maar het kost aan beide kanten werk: de club zet een CNAME, wij zetten het
 * domein bij de hosting en vullen clubs.custom_domain in. Daarom een keuze en
 * geen voorwaarde: een club begint op het subdomein en verhuist wanneer het
 * hem uitkomt. Beide blijven daarna werken.
 *
 * Het subdomein wordt hier afgeleid zonder de database aan te raken; alleen
 * een eigen domein kost een opzoeking, en die cachen we.
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

/**
 * De domeinen waaronder een clubnaam als subdomein gelezen mag worden.
 *
 * Bewust een lijst en niet één instelling. NEXT_PUBLIC_LEAGUE_DOMAIN staat er
 * als eerste in, zodat een andere omgeving zijn eigen hoofddomein kan opgeven
 * — maar pokerleague.be staat er hoe dan ook bij. Dat is geen geheim en geen
 * variabele: het is het adres van het platform.
 *
 * Zonder die vaste tweede waarde hangt cutoff.pokerleague.be af van of er
 * ergens in een dashboard een omgevingsvariabele juist staat, en dat is een
 * afhankelijkheid die je pas ontdekt wanneer een club belt dat zijn adres het
 * niet doet.
 */
export function leagueDomains(): string[] {
  const set = new Set<string>()
  const env = normalizeHost(process.env.NEXT_PUBLIC_LEAGUE_DOMAIN ?? '')
  if (env) set.add(env)
  set.add('pokerleague.be')
  return [...set]
}

export function leagueDomain(): string {
  return leagueDomains()[0]
}

/**
 * Namen die we nooit als clubnaam lezen.
 *
 * Zonder deze lijst zou een toekomstige status.pokerleague.be of
 * mail.pokerleague.be als club "status" of "mail" doorgeschreven worden. Beter
 * hier een korte lijst dan later een raadsel.
 */
const RESERVED = new Set([
  'www', 'app', 'api', 'admin', 'auth', 'mail', 'smtp', 'ftp',
  'status', 'docs', 'blog', 'cdn', 'static', 'assets', 'staging', 'test',
])

/** Domeinen die nooit bij een club horen. */
export function isPlatformHost(host: string): boolean {
  return (
    leagueDomains().includes(host) ||
    host === 'localhost' ||
    host === '127.0.0.1' ||
    host.endsWith('.vercel.app')
  )
}

/**
 * De clubnaam uit een subdomein van het platform, of null.
 *
 * Ook `cutoff.localhost` telt mee: zo kan je de clubkant en de platformkant
 * lokaal naast elkaar openen zonder je hosts-bestand aan te raken — elke
 * browser stuurt *.localhost vanzelf naar je eigen machine.
 */
export function platformSubdomainSlug(host: string): string | null {
  if (!host || isPlatformHost(host)) return null

  for (const base of [...leagueDomains(), 'localhost']) {
    const suffix = `.${base}`
    if (!host.endsWith(suffix)) continue

    const label = host.slice(0, -suffix.length)
    // Alleen één laag diep. a.b.pokerleague.be is geen club.
    if (!label || label.includes('.')) return null
    if (RESERVED.has(label)) return null
    if (!/^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/.test(label)) return null
    return label
  }
  return null
}

/**
 * Zoekt de club bij een domein. Geeft null als het domein niet van een club
 * is — dan blijft het pad ongewijzigd en werkt /c/<slug>/… gewoon rechtstreeks.
 */
export async function clubSlugForHost(host: string): Promise<string | null> {
  if (!host || isPlatformHost(host)) return null

  // Een subdomein van het platform kost geen opzoeking: de naam ís de slug.
  // Bestaat die club niet, dan loopt het verzoek op /c/<naam> gewoon op een
  // 404 — goedkoper dan hier eerst gaan kijken.
  const sub = platformSubdomainSlug(host)
  if (sub) return sub

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
