import { createServerClient } from '@supabase/ssr'
import { NextResponse, type NextRequest } from 'next/server'
import { clubSlugForHost, isPassthroughPath, normalizeHost } from '@/lib/hosts'

/**
 * Draait vóór elk verzoek en doet twee dingen.
 *
 * 1. De Supabase-sessie verversen, zodat niemand halverwege een tornooiavond
 *    wordt uitgelogd.
 * 2. Het domein vertalen naar een clubomgeving. Een verzoek op app.cutoff.be
 *    voor /floor/123 wordt intern /c/cutoff/floor/123. De club ziet dus schone
 *    URL's zonder clubnaam, terwijl er maar één app draait.
 *
 * Bewust géén autorisatie hier. Dat hoort bij RLS in de database; wat hier
 * gebeurt is routering en comfort.
 */
export async function proxy(request: NextRequest) {
  let response = NextResponse.next({ request })

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll()
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value))
          response = NextResponse.next({ request })
          cookiesToSet.forEach(({ name, value, options }) =>
            response.cookies.set(name, value, options),
          )
        },
      },
    },
  )

  // getClaims() verifieert de handtekening serverside. getSession() doet dat
  // niet en is dus ongeschikt om beslissingen op te baseren.
  await supabase.auth.getClaims()

  const { pathname } = request.nextUrl
  if (isPassthroughPath(pathname)) return response

  const slug = await clubSlugForHost(normalizeHost(request.headers.get('host')))
  if (!slug) return response

  const url = request.nextUrl.clone()
  url.pathname = `/c/${slug}${pathname === '/' ? '' : pathname}`

  const rewritten = NextResponse.rewrite(url, { request })
  // Cookies die het verversen van de sessie heeft gezet moeten mee.
  response.cookies.getAll().forEach((c) => rewritten.cookies.set(c))
  return rewritten
}

export const config = {
  matcher: [
    /*
     * Alles behalve statische bestanden en afbeeldingen. De zaalweergave
     * draait uren achter elkaar; elke overbodige verversing is verspild.
     */
    '/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp|woff2?)$).*)',
  ],
}
