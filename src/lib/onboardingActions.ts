'use server'

import { revalidatePath } from 'next/cache'
import type { Key } from '@/lib/i18n/dictionaries'
import { createClient } from '@/lib/supabase/server'

/**
 * Wat het welkomstscherm wegschrijft.
 *
 * Twee losse acties en niet één, omdat ze op verschillende momenten gebeuren:
 * het profiel bij stap drie, het afvinken pas op het einde. Wie halverwege
 * wegklikt heeft zijn naam dan wel al opgeslagen, maar krijgt het scherm de
 * volgende keer opnieuw — en dat is precies goed: hij was niet klaar.
 */

export async function saveOnboardingProfile(input: {
  first: string
  last: string
  username: string
  listing: boolean
  /** null = niet gevraagd op dit scherm, dus niet aanraken. */
  birthdate?: string | null
  consent?: boolean | null
}): Promise<{ ok: boolean; error?: Key; detail?: string }> {
  const supabase = await createClient()
  const { data: claims } = await supabase.auth.getClaims()
  if (!claims?.claims) return { ok: false, error: 'me.errNotSignedIn' }

  const clean = (v: string) => {
    const s = v.trim()
    return s === '' ? null : s
  }

  const username = clean(input.username)
  if (username && !/^[a-zA-Z0-9._-]{3,24}$/.test(username)) {
    return { ok: false, error: 'me.errUsernameShape' }
  }

  const first = clean(input.first)
  const last = clean(input.last)
  const full = [first, last].filter(Boolean).join(' ')

  // De leeftijd wordt door de database bewaakt (trigger uit 0036); hier
  // vangen we hem alleen af om een leesbare melding te kunnen geven.
  if (input.birthdate) {
    const [y, m, d] = input.birthdate.split('-').map(Number)
    const now = new Date()
    let age = now.getFullYear() - y
    const had = now.getMonth() + 1 > m || (now.getMonth() + 1 === m && now.getDate() >= d)
    if (!had) age -= 1
    if (age < 18) return { ok: false, error: 'db.under18' }
  }

  const { error } = await supabase
    .from('players')
    .update({
      first_name: first,
      last_name: last,
      username,
      public_listing: input.listing,
      ...(input.birthdate ? { birthdate: input.birthdate } : {}),
      ...(input.consent ? { stats_consent_at: new Date().toISOString() } : {}),
      // De weergavenaam volgt de echte naam zolang de speler zelf aan het
      // invullen is. Later laat de trigger uit 0005 hem met rust.
      ...(full ? { display_name: full } : {}),
    })
    .eq('auth_user_id', String(claims.claims.sub))

  if (error) {
    return error.code === '23505'
      ? { ok: false, error: 'me.errUsernameTaken' }
      : { ok: false, error: 'common.error', detail: error.message }
  }

  revalidatePath('/ik')
  return { ok: true }
}

export async function finishOnboarding(): Promise<void> {
  const supabase = await createClient()
  await supabase.rpc('finish_onboarding')
  revalidatePath('/ik')
}
