import { cookies } from 'next/headers'
import { isLocale, type Locale } from '@/lib/i18n/dictionaries'

/**
 * De taal van een bezoeker op de publieke kant.
 *
 * Op de clubkant staat de taal vast: die komt uit `clubs.locale`, want de
 * floor van Cutoff hoort elke avond hetzelfde scherm te zien. Op
 * pokerleague.be ligt dat anders — daar komen Vlamingen, Walen en af en toe
 * iemand die geen van beide spreekt. Vandaar een keuze bij binnenkomst, en
 * een koekje zodat het maar één keer gevraagd wordt.
 *
 * Bewust géén automatische keuze op basis van de browsertaal. In België staat
 * de helft van de browsers op Engels of op een taal die niets zegt over wat
 * iemand liever leest, en niets is vervelender dan een site die zelf beslist
 * en het fout heeft.
 */
export const LOCALE_COOKIE = 'pl_lang'

/** De gekozen taal, of null als de bezoeker nog niets koos. */
export async function visitorLocale(): Promise<Locale | null> {
  const jar = await cookies()
  const v = jar.get(LOCALE_COOKIE)?.value
  return isLocale(v) ? v : null
}

/** De taal om mee te renderen. Nederlands zolang er niets gekozen is. */
export async function publicLocale(): Promise<Locale> {
  return (await visitorLocale()) ?? 'nl'
}
