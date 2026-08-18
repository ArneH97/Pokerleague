'use server'

import { revalidatePath } from 'next/cache'
import { createClient } from '@/lib/supabase/server'

/**
 * Je aansluiten bij een club.
 *
 * De hele beslissing zit in `join_club` in de database: bestaat de club, staat
 * ze open, ben je al lid. Hier staat geen enkele controle, en dat is met
 * opzet — anders zijn er twee plekken die het antwoord kennen en gaan ze ooit
 * uit elkaar lopen.
 */

export type JoinResult = 'joined' | 'already' | 'closed' | 'unknown' | 'error'

export async function joinClub(slug: string): Promise<JoinResult> {
  const supabase = await createClient()
  const { data, error } = await supabase.rpc('join_club', { p_club_slug: slug })
  if (error) return 'error'
  revalidatePath('/ik')
  return (data as unknown as JoinResult) ?? 'error'
}

/** Meerdere clubs tegelijk, voor het scherm na het aansluiten. */
export async function joinClubs(slugs: string[]): Promise<number> {
  let n = 0
  for (const slug of slugs) {
    if ((await joinClub(slug)) === 'joined') n++
  }
  return n
}
