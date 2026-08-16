import { createServerClient } from '@supabase/ssr'
import { NextResponse, type NextRequest } from 'next/server'

/**
 * Ververst de Supabase-sessie bij elk verzoek.
 *
 * In Next 16 heet dit `proxy` in plaats van `middleware`; de werking is
 * dezelfde. Dit bestand doet bewust GEEN autorisatie — dat hoort thuis bij
 * RLS in de database en bij de paginacontroles. Hier alleen tokens verversen
 * zodat een sessie niet halverwege een tornooiavond verloopt.
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
          cookiesToSet.forEach(({ name, value }) =>
            request.cookies.set(name, value),
          )
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

  return response
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
