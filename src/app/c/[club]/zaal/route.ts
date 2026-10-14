import type { NextRequest } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import { zaalHtml, type ZaalBord, type ZaalLevel } from '@/lib/zaalscherm'

/**
 * De klok voor een tv die te oud is voor de app.
 *
 * Een route en geen pagina, en dat is de hele kern. Elke andere pagina van
 * PokerLeague wordt door Next en Tailwind gebouwd voor een browser van maart
 * 2023; de tv's die in clubzalen hangen zijn vaak ouder en laten dan de hele
 * stylesheet vallen. Hier gaat er geen framework overheen: wat de server
 * terugstuurt is precies wat de tv krijgt, handgeschreven en te controleren.
 *
 * Twee antwoorden op hetzelfde adres. Zonder `json=1` de pagina, met `json=1`
 * de kale cijfers — dat is wat de pagina zelf elke tien seconden ophaalt. Eén
 * route dus, en geen tweede adres dat iemand later vergeet mee te verhuizen.
 *
 * **De sleutel.** Zonder geldige sleutel komt er een 404 en verder niets —
 * ook niet of die club bestaat. Zie migratie 0070 waarom een tv geen account
 * kan hebben.
 */

export const dynamic = 'force-dynamic'

const GEEN_CACHE = {
  // Een klok die uit een cache komt is geen klok. Ook de tussenliggende
  // proxies van een internetaanbieder moeten dit met rust laten.
  'Cache-Control': 'no-store, no-cache, must-revalidate, max-age=0',
  Pragma: 'no-cache',
}

export async function GET(req: NextRequest, ctx: RouteContext<'/c/[club]/zaal'>) {
  const { club } = await ctx.params
  const sleutel = req.nextUrl.searchParams.get('k') ?? ''
  const alsJson = req.nextUrl.searchParams.get('json') === '1'

  if (sleutel === '') return nee()

  const supabase = await createClient()
  const { data: bordData, error } = await supabase.rpc('club_screen_board', {
    p_club_slug: club,
    p_key: sleutel,
  })
  if (error) return nee()

  const rijen = (bordData ?? []) as unknown as ZaalBord[]
  const bord = rijen[0] ?? null

  // Geen rij kan twee dingen betekenen: verkeerde sleutel, of er is vanavond
  // niets te doen. Die twee uit elkaar houden kan niet zonder iets prijs te
  // geven, dus doen we dat niet — behalve als de tv al weet dat hij goed zit.
  // Vandaar: bij het ophalen van de cijfers antwoorden we gewoon "niets", en
  // de pagina blijft rustig verder kijken. Bij het openen van de pagina
  // zonder rij is een 404 juist: dan heeft iemand het adres verkeerd getikt.
  if (alsJson) {
    const levels = bord ? await haalLevels(supabase, club, sleutel) : []
    return Response.json({ bord, levels }, { headers: GEEN_CACHE })
  }

  if (!bord) return nee()

  const levels = await haalLevels(supabase, club, sleutel)

  return new Response(
    zaalHtml({ sleutel, bord, levels, clubNaam: bord.club_name }),
    { headers: { 'Content-Type': 'text/html; charset=utf-8', ...GEEN_CACHE } },
  )
}

async function haalLevels(
  supabase: Awaited<ReturnType<typeof createClient>>,
  club: string,
  sleutel: string,
): Promise<ZaalLevel[]> {
  const { data } = await supabase.rpc('club_screen_levels', {
    p_club_slug: club,
    p_key: sleutel,
  })
  return (data ?? []) as unknown as ZaalLevel[]
}

/**
 * Niets te zien.
 *
 * Met opzet geen uitleg over wat er mis is. Het enige dat hier ooit staat is
 * een verkeerd ingetikt adres, en dan helpt "sleutel klopt niet" de tikker
 * net zoveel als iemand die aan het raden is.
 */
function nee(): Response {
  return new Response(
    '<!doctype html><meta charset="utf-8"><title>Niet gevonden</title>'
    + '<body style="margin:0;background:#07090c;color:#6b7484;'
    + 'font:4vh Arial,sans-serif;display:flex;align-items:center;'
    + 'justify-content:center;height:100vh">Dit adres klopt niet.</body>',
    { status: 404, headers: { 'Content-Type': 'text/html; charset=utf-8', ...GEEN_CACHE } },
  )
}
