'use server'

import { revalidatePath } from 'next/cache'
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
}): Promise<{ ok: boolean; error?: string }> {
  const supabase = await createClient()
  const { data: claims } = await supabase.auth.getClaims()
  if (!claims?.claims) return { ok: false, error: 'Niet aangemeld.' }

  const clean = (v: string) => {
    const s = v.trim()
    return s === '' ? null : s
  }

  const username = clean(input.username)
  if (username && !/^[a-zA-Z0-9._-]{3,24}$/.test(username)) {
    return { ok: false, error: 'Een gebruikersnaam is 3 tot 24 tekens.' }
  }

  const first = clean(input.first)
  const last = clean(input.last)
  const full = [first, last].filter(Boolean).join(' ')

  const { error } = await supabase
    .from('players')
    .update({
      first_name: first,
      last_name: last,
      username,
      public_listing: input.listing,
      // De weergavenaam volgt de echte naam zolang de speler zelf aan het
      // invullen is. Later laat de trigger uit 0005 hem met rust.
      ...(full ? { display_name: full } : {}),
    })
    .eq('auth_user_id', String(claims.claims.sub))

  if (error) {
    return {
      ok: false,
      error: error.code === '23505' ? 'Die gebruikersnaam is al bezet.' : error.message,
    }
  }

  revalidatePath('/ik')
  return { ok: true }
}

export async function finishOnboarding(): Promise<void> {
  const supabase = await createClient()
  await supabase.rpc('finish_onboarding')
  revalidatePath('/ik')
}
