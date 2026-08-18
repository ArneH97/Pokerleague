'use server'

import { revalidatePath } from 'next/cache'
import { isLocale, type Key } from '@/lib/i18n/dictionaries'
import { createClient } from '@/lib/supabase/server'

/**
 * Wat een speler over zichzelf wijzigt.
 *
 * Geen rechtencontrole hier: `players_self_update` laat alleen door wat aan
 * `auth.uid()` hangt. Probeert iemand met een geknutseld formulier het profiel
 * van een ander te raken, dan raakt de update nul rijen — en dat is precies
 * wat er hoort te gebeuren.
 */

/**
 * `error` is een sleutel, geen zin: de taal van de kijker staat in een koekje
 * dat het formulier al las, dus vertalen gebeurt daar. Zie settingsActions.
 */
type Result = { ok: true } | { ok: false; error: Key; detail?: string }

export async function savePlayerProfile(_prev: Result | null, fd: FormData): Promise<Result> {
  const supabase = await createClient()
  const { data: claims } = await supabase.auth.getClaims()
  if (!claims?.claims) return { ok: false, error: 'me.errNotSignedIn' }

  const txt = (k: string) => {
    const v = fd.get(k)
    const s = typeof v === 'string' ? v.trim() : ''
    return s === '' ? null : s
  }

  const username = txt('username')
  if (username && !/^[a-zA-Z0-9._-]{3,24}$/.test(username)) {
    return { ok: false, error: 'me.errUsernameShape' }
  }

  // Alleen een taal die we ook echt spreken. Wie het formulier zelf in elkaar
  // knutselt kan hier van alles insturen, en een onbekende taal betekent dat
  // de mailer stil terugvalt op Nederlands zonder dat iemand snapt waarom.
  const rawLocale = txt('locale')
  const locale = isLocale(rawLocale) ? rawLocale : undefined

  const { error } = await supabase
    .from('players')
    .update({
      ...(locale ? { locale } : {}),
      first_name: txt('first_name'),
      last_name: txt('last_name'),
      username,
      public_listing: fd.get('public_listing') === 'on',
      public_profile: fd.get('public_profile') === 'on',
    })
    .eq('auth_user_id', String(claims.claims.sub))

  if (error) {
    // Een unieke index op de gebruikersnaam: iemand was je voor.
    return error.code === '23505'
      ? { ok: false, error: 'me.errUsernameTaken' }
      : { ok: false, error: 'common.error', detail: error.message }
  }

  revalidatePath('/ik')
  return { ok: true }
}
