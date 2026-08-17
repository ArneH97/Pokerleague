/**
 * Mail versturen via Resend.
 *
 * Bewust met `fetch` en niet met hun npm-pakket. De API is één POST met een
 * JSON-body; een afhankelijkheid erbij levert hier niets op behalve een
 * pakket dat kan verouderen. Wat we wél zelf moeten doen is de fouten netjes
 * teruggeven, want de verzender moet het verschil kennen tussen "probeer straks
 * opnieuw" en "dit adres bestaat niet".
 *
 * De sleutel staat alleen op de server. Ze mag nergens met NEXT_PUBLIC_ ervoor
 * en nooit in een client component belanden — dan staat ze in de browserbundel
 * en kan iedereen mail versturen in naam van het platform.
 */

const ENDPOINT = 'https://api.resend.com/emails'

export interface MailInput {
  to: string
  subject: string
  html: string
  text: string
  /** De naam die de ontvanger ziet staan. Meestal de clubnaam. */
  fromName?: string
  /** Waar een antwoord heen gaat. Zonder dit verdwijnt een antwoord. */
  replyTo?: string
}

export interface MailResult {
  ok: boolean
  id?: string
  error?: string
}

/** Is er überhaupt een sleutel ingesteld? Zo niet, dan slaan we over in plaats van te falen. */
export function mailConfigured(): boolean {
  return Boolean(process.env.RESEND_API_KEY && process.env.MAIL_FROM)
}

export async function sendMail(input: MailInput): Promise<MailResult> {
  const key = process.env.RESEND_API_KEY
  const from = process.env.MAIL_FROM

  if (!key || !from) {
    return { ok: false, error: 'RESEND_API_KEY of MAIL_FROM ontbreekt' }
  }

  // Een afzender met een naam ervoor leest als een club, niet als een systeem.
  // Aanhalingstekens omdat een clubnaam een komma kan bevatten.
  const sender = input.fromName
    ? `${JSON.stringify(input.fromName)} <${from}>`
    : from

  try {
    const res = await fetch(ENDPOINT, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${key}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: sender,
        to: [input.to],
        subject: input.subject,
        html: input.html,
        text: input.text,
        ...(input.replyTo ? { reply_to: input.replyTo } : {}),
      }),
      // Blijft Resend hangen, dan mag dat de hele wachtrij niet ophouden.
      signal: AbortSignal.timeout(15_000),
    })

    const body = (await res.json().catch(() => null)) as
      | { id?: string; message?: string; name?: string }
      | null

    if (!res.ok) {
      return {
        ok: false,
        error: body?.message ?? body?.name ?? `HTTP ${res.status}`,
      }
    }

    return { ok: true, id: body?.id }
  } catch (e) {
    return { ok: false, error: e instanceof Error ? e.message : 'onbekende fout' }
  }
}
