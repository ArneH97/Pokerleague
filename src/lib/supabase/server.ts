import { createServerClient } from '@supabase/ssr'
import { cookies } from 'next/headers'

/**
 * Supabase-client voor Server Components en Route Handlers.
 *
 * De setAll-tak kan gooien wanneer hij vanuit een Server Component draait —
 * daar mag je geen cookies meer schrijven. Dat is onschuldig zolang proxy.ts
 * de sessie ververst, want die schrijft de cookies wél.
 */
export async function createClient() {
  const cookieStore = await cookies()

  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,
    {
      cookies: {
        getAll() {
          return cookieStore.getAll()
        },
        setAll(cookiesToSet) {
          try {
            cookiesToSet.forEach(({ name, value, options }) =>
              cookieStore.set(name, value, options),
            )
          } catch {
            // Server Component: proxy.ts handelt het verversen af.
          }
        },
      },
    },
  )
}
