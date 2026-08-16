import { createBrowserClient } from '@supabase/ssr'

/**
 * Supabase-client voor de browser. Praat met de publishable key en is dus
 * volledig afhankelijk van RLS voor beveiliging — wat het punt is: de
 * policies in 0003 zijn de enige poort.
 */
export function createClient() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,
  )
}
