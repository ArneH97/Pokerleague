import { ImageResponse } from 'next/og'
import type { NextRequest } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import { getClub, getClubRole } from '@/lib/club'
import { isLocale, type Locale } from '@/lib/i18n/dictionaries'
import { clubUrl } from '@/lib/site'
import { afficheFonts } from '@/lib/promo/fonts'
import { qrDataUri } from '@/lib/promo/qr'
import { Affiche, afficheData, MATEN, type Vorm } from '@/lib/promo/poster'

/**
 * De affiche van één avond, als PNG.
 *
 * Eén afbeelding per aanroep, gestuurd door `?vorm=` en `?l=`. Vier bestanden
 * dus voor één tornooi, en dat is met opzet: een route die er vier tegelijk
 * maakt zou vier keer satori draaien binnen één verzoek, en dat is precies het
 * soort ding dat op een tragere avond in een tijdslimiet loopt. Nu haalt het
 * scherm ze los op en ziet de floor ze één voor één binnenkomen.
 *
 * **Waarom dit achter een rol zit terwijl de gegevens publiek zijn.** Alles wat
 * hier op staat, staat ook op de inschrijfpagina. Het punt is niet geheimhouding
 * maar rekenwerk: een open beeldroute is een knop waarmee iedereen onze
 * serverfuncties kan laten draaien. Vandaar owner, admin of floor.
 */

export const dynamic = 'force-dynamic'
// Satori plus twee lettertypes plus een QR: ruim binnen een seconde, maar de
// standaard van tien is krap als Vercel net koud start.
export const maxDuration = 30

interface Rij {
  id: string
  name: string
  scheduled_at: string
  starting_stack: number
  prereg_bonus_stack: number
  buyin_cents: number
  fee_cents: number
  late_reg_level: number | null
  structure_id: string | null
}

export async function GET(req: NextRequest, ctx: RouteContext<'/api/promo/[club]/[id]'>) {
  const { club: slug, id } = await ctx.params

  const club = await getClub(slug)
  if (!club) return new Response('Onbekende club', { status: 404 })

  const rol = await getClubRole(club.id)
  if (rol === null || !['owner', 'admin', 'floor'].includes(rol)) {
    return new Response('Geen rechten', { status: 403 })
  }

  const vorm: Vorm = req.nextUrl.searchParams.get('vorm') === 'verhaal' ? 'verhaal' : 'vierkant'
  const gevraagd = req.nextUrl.searchParams.get('l') ?? 'nl'
  const locale: Locale = isLocale(gevraagd) ? gevraagd : 'nl'

  const supabase = await createClient()
  const { data } = await supabase
    .from('tournaments')
    .select('id,name,scheduled_at,starting_stack,prereg_bonus_stack,buyin_cents,fee_cents,late_reg_level,structure_id')
    .eq('id', id)
    .eq('club_id', club.id)
    .maybeSingle<Rij>()

  if (!data) return new Response('Onbekend tornooi', { status: 404 })

  // De duur van een level staat in de structuur en niet op het tornooi. We
  // nemen het eerste speelniveau: bijna elke structuur gebruikt overal dezelfde
  // duur, en waar dat niet zo is, is het eerste getal wat de zaal verwacht.
  // Hangt er geen structuur, dan laat de affiche die tegel gewoon weg.
  let levelMin: number | null = null
  if (data.structure_id) {
    const { data: lvl } = await supabase
      .from('blind_levels')
      .select('duration_s')
      .eq('structure_id', data.structure_id)
      .eq('is_break', false)
      .order('idx')
      .limit(1)
      .maybeSingle<{ duration_s: number }>()
    if (lvl) levelMin = Math.round(lvl.duration_s / 60)
  }

  // Het adres dat op de affiche komt én in de QR zit: het korte clubadres met
  // de taal erin. Zo komt wie de Franse affiche scant ook op een Franse
  // pagina uit, zonder eerst een taalknop te moeten zoeken.
  const url = clubUrl(club, `/inschrijven/${data.id}?l=${locale}`)

  // Onder de QR staat het kórte adres, zonder de id van dit tornooi. Niemand
  // typt een uuid van zesendertig tekens over van een scherm — dan is de tekst
  // er alleen om de affiche vol te maken. `/inschrijven` zonder id brengt je
  // naar de eerstvolgende avond, en dat is voor wie de QR niet kan scannen het
  // juiste antwoord. De QR zelf blijft wél naar déze avond wijzen.
  const toonUrl = clubUrl(club, '/inschrijven')

  // Een relatief logopad ('/clubs/cutoff.png') kan satori niet ophalen; die
  // heeft een volledig adres nodig. De oorsprong van dit verzoek is het
  // dichtste dat we bij de waarheid komen — op een clubdomein, een
  // preview-adres of localhost klopt hij allemaal.
  const logo = club.logo_url
    ? (club.logo_url.startsWith('http') ? club.logo_url : new URL(club.logo_url, req.nextUrl.origin).toString())
    : null

  const d = afficheData(locale, {
    clubNaam: club.name,
    logoUrl: logo,
    merk: club.primary_color ?? '#10b981',
    tornooi: data.name,
    scheduledAt: data.scheduled_at,
    timezone: club.timezone ?? 'Europe/Brussels',
    stad: club.city,
    adres: club.address_line,
    buyinCents: data.buyin_cents,
    feeCents: data.fee_cents,
    currency: club.currency ?? 'EUR',
    stapel: data.starting_stack,
    bonus: data.prereg_bonus_stack,
    levelMin,
    lateReg: data.late_reg_level,
    telefoon: club.contact_phone,
    web: club.custom_domain ?? null,
    toonUrl,
    qr: await qrDataUri(url),
  })

  return new ImageResponse(<Affiche vorm={vorm} locale={locale} d={d} />, {
    ...MATEN[vorm],
    fonts: afficheFonts(),
    headers: {
      // Geen cache: verandert de floor de datum of de bonus, dan hoort de
      // volgende affiche die te tonen en niet de vorige.
      'Cache-Control': 'no-store',
      'Content-Disposition':
        `inline; filename="${slug}-${vorm}-${locale}.png"`,
    },
  })
}
