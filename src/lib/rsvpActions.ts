'use server'

import { createClient } from '@/lib/supabase/server'

/**
 * Vooraf inschrijven voor een avond.
 *
 * De hele beslissing zit in `rsvp_for_tournament` in de database: staat de
 * avond open, is dit adres bruikbaar, is deze persoon oud genoeg, bestaat hij
 * al. Hier staat geen enkele controle die daar ook staat — anders zijn er twee
 * plekken die het antwoord kennen en lopen ze ooit uit elkaar.
 *
 * Wel hier: het afvangen van een lege of onmogelijke invoer vóór er een
 * verzoek naar de database vertrekt. Dat is geen tweede waarheid maar
 * beleefdheid tegenover iemand die op zijn telefoon staat te tikken.
 */

export type RsvpStatus =
  | 'ok' | 'already' | 'closed' | 'too_young'
  | 'bad_email' | 'bad_name' | 'full' | 'error'

export interface RsvpResult {
  status: RsvpStatus
  /**
   * Staat er al een PokerLeague-account op dit adres?
   *
   * Bepaalt waar de knop erna naartoe wijst. Zonder dit stuurden we iemand
   * die hier al jaren speelt naar een registratieformulier dat hem vertelt
   * dat zijn adres bezet is — een doodlopende straat op het moment dat hij
   * net goedgezind was.
   */
  hasAccount: boolean
}

export async function rsvp(
  tournamentId: string,
  form: { firstName: string; lastName: string; email: string; birthdate: string },
): Promise<RsvpResult> {
  const first = form.firstName.trim()
  const last = form.lastName.trim()
  const email = form.email.trim().toLowerCase()
  const birthdate = form.birthdate.trim()

  const mis = (status: RsvpStatus): RsvpResult => ({ status, hasAccount: false })

  if (!first && !last) return mis('bad_name')
  if (!/^[^@\s]+@[^@\s]+\.[a-z]{2,}$/i.test(email)) return mis('bad_email')
  if (!/^\d{4}-\d{2}-\d{2}$/.test(birthdate)) return mis('too_young')

  const supabase = await createClient()
  const { data, error } = await supabase.rpc('rsvp_for_tournament', {
    p_tournament_id: tournamentId,
    p_first_name: first,
    p_last_name: last,
    p_email: email,
    p_birthdate: birthdate,
  })

  if (error) return mis('error')

  const row = data as unknown as { status?: string; has_account?: boolean } | null
  return {
    status: (row?.status as RsvpStatus) ?? 'error',
    hasAccount: row?.has_account === true,
  }
}
