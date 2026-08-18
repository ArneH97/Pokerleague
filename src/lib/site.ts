import { leagueDomains } from '@/lib/hosts'

/**
 * Een absoluut adres op het spelersplatform.
 *
 * Nodig omdat de spelerskant en de clubkant op verschillende domeinen staan,
 * en een gewone `/registreren` op `app.cutoff.be` door de proxy vertaald wordt
 * naar `/c/cutoff/registreren` — een pagina die niet bestaat. Dat is precies
 * wat er misging: de knop "Profiel aanmaken" op de clubpagina liep dood, en
 * "Aanmelden" kwam uit op het personeelsscherm.
 *
 * Waarom niet gewoon die paden doorlaten op clubdomeinen? Omdat een
 * aanmeldkoekje niet over domeinen heen gaat. Registreer je op
 * `app.cutoff.be`, dan ben je dáár aangemeld en op `pokerleague.be` niet — en
 * dan heb je twee plekken waar je "wel of niet ingelogd" kan zijn in plaats
 * van één. Erger nog: op het clubdomein zit al de sessie van de floor, en één
 * browser houdt er per domein maar één bij. Een speler die zich daar aanmeldt
 * zou de floor eruit gooien, midden in een tornooi.
 *
 * Dus: het clubdomein is van de club — de etalage en de bediening. Alles wat
 * van de speler zelf is, staat op het platform. Deze functie maakt dat
 * verschil zichtbaar in de code in plaats van het te laten afhangen van waar
 * een component toevallig gerenderd wordt.
 */
export function leagueUrl(path = '/'): string {
  const base = process.env.NEXT_PUBLIC_SITE_URL?.replace(/\/+$/, '')
  if (base) return `${base}${path}`

  // Zonder ingestelde basis: het platformdomein uit hosts.ts. In ontwikkeling
  // is dat localhost, en dan is een relatief pad juist wél het goede antwoord.
  const domain = leagueDomains()[0]
  if (!domain || domain.includes('localhost')) return path
  return `https://www.${domain}${path}`
}
