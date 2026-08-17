import { NextResponse, type NextRequest } from 'next/server'
import { createClient } from '@/lib/supabase/server'

/**
 * Waar de link uit een bevestigingsmail landt.
 *
 * Zonder deze route komt iemand die op "bevestig je adres" klikt uit op de
 * voorpagina, en mag hij zelf uitzoeken waar zijn profiel staat. Dat is
 * precies het moment waarop je hem kwijt bent: hij deed wat er gevraagd werd
 * en kreeg er niets voor terug.
 *
 * Twee vormen worden afgehandeld, want Supabase gebruikt er twee naast elkaar:
 * `code` (de nieuwere uitwisseling) en `token_hash` met een `type`. Welke van
 * de twee je krijgt hangt af van de sjabloonversie in het dashboard, dus
 * behandelen we ze allebei in plaats van te gokken.
 *
 * Waar hij daarna heen gaat staat in `next`, met de spelerspagina als
 * standaard. Alleen paden binnen deze site, anders is dit een open doorgeefluik
 * naar eender welk adres.
 */
export async function GET(request: NextRequest) {
  const url = new URL(request.url)
  const code = url.searchParams.get('code')
  const tokenHash = url.searchParams.get('token_hash')
  const type = url.searchParams.get('type')

  const raw = url.searchParams.get('next') ?? '/ik'
  const next = raw.startsWith('/') && !raw.startsWith('//') ? raw : '/ik'

  const supabase = await createClient()
  let failed: string | null = null

  if (code) {
    const { error } = await supabase.auth.exchangeCodeForSession(code)
    failed = error?.message ?? null
  } else if (tokenHash && type) {
    const { error } = await supabase.auth.verifyOtp({
      type: type as 'signup' | 'email' | 'recovery' | 'invite' | 'email_change',
      token_hash: tokenHash,
    })
    failed = error?.message ?? null
  } else {
    failed = 'geen code'
  }

  if (failed) {
    // Een verlopen of al gebruikte link. Naar het aanmeldscherm met een
    // begrijpelijke boodschap, niet naar een lege pagina.
    return NextResponse.redirect(new URL('/login?verified=failed', url.origin))
  }

  return NextResponse.redirect(new URL(next, url.origin))
}
