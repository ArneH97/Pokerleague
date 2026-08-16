/**
 * Servertijd, zodat de klok niet afhangt van de laptop in de zaal.
 *
 * Een verkeerd ingestelde clientklok is geen randgeval: een laptop die net
 * uit slaapstand komt kan er seconden naast zitten. De client meet hiermee
 * zijn eigen afwijking en rekent die weg.
 */
export const dynamic = 'force-dynamic'

export async function GET() {
  return Response.json(
    { now: Date.now() },
    { headers: { 'Cache-Control': 'no-store, max-age=0' } },
  )
}
