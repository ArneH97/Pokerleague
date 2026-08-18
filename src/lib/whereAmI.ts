import { headers } from 'next/headers'
import { isPlatformHost, normalizeHost } from '@/lib/hosts'

/**
 * Sta ik op het spelersplatform of op het werkdomein van een club?
 *
 * Sinds we de twee werelden uit elkaar trokken is dat geen detail meer maar
 * het verschil tussen twee pagina's. Op `pokerleague.be` is `/c/cutoff` de
 * clubpagina voor spelers: wie de club is, wanneer er gespeeld wordt, en —
 * met een account — de agenda en het klassement. Op `app.cutoff.be` is
 * dezelfde route het gereedschap van de club, en heeft een bezoeker daar
 * niets te zoeken.
 *
 * Waarom de scheiding zo hard is, staat in `lib/site.ts`: een aanmeldkoekje
 * gaat niet over domeinen heen, en op het clubdomein zit al de sessie van de
 * floor. Eén browser houdt er per domein maar één bij.
 */
export async function onPlatform(): Promise<boolean> {
  const host = normalizeHost((await headers()).get('host'))
  // Een leeg of onbekend adres: dan liever de spelerskant tonen dan iemand
  // op een aanmeldscherm zetten waar hij niets mee kan.
  if (!host) return true
  return isPlatformHost(host)
}
