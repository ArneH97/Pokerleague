import { cookies } from 'next/headers'
import { isLocale, type Locale } from '@/lib/i18n/dictionaries'

/**
 * De taal van een bezoeker op de publieke kant.
 *
 * Eén koekje voor het hele product. Op de clubkant is `clubs.locale` de
 * standaard — de zaalklok in Baardegem staat in het Nederlands zonder dat
 * iemand iets kiest — maar wie wél kiest, houdt die keuze overal: op het
 * platform, op de clubpagina en op het floorscherm. Een Vlaamse club met een
 * Waalse floor is geen randgeval, en die man moet zijn knoppen kunnen lezen.
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

/**
 * De taal van een clubscherm.
 *
 * De keuze van de bezoeker wint; de taal van de club is de standaard. Zo
 * staat de zaalklok in Baardegem vanzelf in het Nederlands, en leest een
 * Franstalige floor bij diezelfde club toch zijn eigen knoppen.
 *
 * Eén functie in plaats van dezelfde regel op vijftien pagina's: die regel
 * stond overal net iets anders, en op de helft van de schermen ontbrak de
 * bezoekerskeuze volledig.
 */
export async function clubLocale(clubLocaleValue: string | null | undefined): Promise<Locale> {
  return (await visitorLocale())
    ?? (isLocale(clubLocaleValue) ? clubLocaleValue : 'nl')
}
