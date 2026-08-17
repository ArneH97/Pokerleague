import { createClient as createSupabaseClient } from '@supabase/supabase-js'

/**
 * De client met de geheime sleutel. Omzeilt RLS volledig.
 *
 * Hier is er precies één reden voor: achtergrondwerk dat aan geen enkele
 * gebruiker hangt. De verzender van uitnodigingen draait om vier uur 's nachts
 * en moet dan over alle clubs heen kunnen kijken — er is geen sessie waarvan
 * hij de rechten kan lenen.
 *
 * Dit hoort dus nooit in een Server Component en nooit in iets dat een
 * bezoeker aanstuurt. Waar er wél een gebruiker is, gebruik je de gewone
 * client uit `server.ts`: dan filtert de database mee en kan een fout in een
 * query hoogstens tonen wat die persoon toch al mocht zien.
 *
 * De sessie wordt uitgezet omdat er niets te bewaren valt: geen cookies, geen
 * verversing, geen gebruiker.
 */
export function createServiceClient() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL
  const key = process.env.SUPABASE_SECRET_KEY

  if (!url || !key) {
    throw new Error('NEXT_PUBLIC_SUPABASE_URL of SUPABASE_SECRET_KEY ontbreekt')
  }

  return createSupabaseClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  })
}
