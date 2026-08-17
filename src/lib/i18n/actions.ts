'use server'

import { cookies } from 'next/headers'
import { isLocale } from '@/lib/i18n/dictionaries'
import { LOCALE_COOKIE } from '@/lib/i18n/server'

/**
 * De taalkeuze van een bezoeker vastleggen.
 *
 * Een serveractie en geen knop met JavaScript: zo werkt de keuze ook als er
 * iets misloopt met het laden van scripts, en staat de juiste taal er meteen
 * bij de eerste render — geen flits van Nederlands voor een Waalse bezoeker.
 *
 * In een bestand met 'use server' moet élke export een asynchrone functie
 * zijn. De naam van het koekje staat daarom in server.ts.
 */
export async function chooseLocale(formData: FormData): Promise<void> {
  const value = formData.get('locale')
  if (!isLocale(typeof value === 'string' ? value : null)) return

  const jar = await cookies()
  jar.set(LOCALE_COOKIE, value as string, {
    path: '/',
    maxAge: 60 * 60 * 24 * 365,
    sameSite: 'lax',
    httpOnly: false,
  })
}
