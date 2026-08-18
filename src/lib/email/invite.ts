import type { Locale } from '@/lib/i18n/dictionaries'

/**
 * De uitnodigingsmail.
 *
 * Deze mail moet één ding doen: iemand die vanavond bij een club aan tafel zat
 * uitleggen waarom hij post krijgt van een naam die hij niet kent. Dat is de
 * hele moeilijkheid. Hij kent *Cutoff*. Hij heeft nog nooit van PokerLeague
 * gehoord, en een mail die begint met "Welkom bij PokerLeague" leest als spam.
 *
 * Vandaar de volgorde: eerst de club, dan wat er van hem bewaard is, dan pas
 * hoe dat platform heet en wat het extra doet. De club is de afzendernaam en
 * het antwoordadres, want dát is de partij met wie hij een band heeft.
 *
 * En de laatste regel staat er met opzet: waarom hij dit krijgt, en dat
 * niets doen ook mag. Wie een uitnodiging stuurt naar iemand die er niet om
 * vroeg, hoort dat er zelf bij te zeggen.
 *
 * De opmaak is bewust ouderwets — tabellen, inline stijlen, geen webfonts.
 * Outlook rendert nog altijd met Word, en een knop die daar niet klikbaar is
 * kost meer dan een lelijke rand.
 */

export interface InviteMailInput {
  playerName: string
  clubName: string
  url: string
  expiresOn: Date
  locale: Locale
}

interface Copy {
  subject: string
  preheader: string
  greeting: string
  played: string
  platform: string
  cta: string
  expires: string
  reply: string
  why: string
  fallback: string
}

function copy(i: InviteMailInput): Copy {
  const { playerName, clubName } = i
  const naam = playerName.trim() || ''
  const date = new Intl.DateTimeFormat(`${i.locale}-BE`, {
    day: 'numeric', month: 'long', year: 'numeric', timeZone: 'Europe/Brussels',
  }).format(i.expiresOn)

  if (i.locale === 'fr') {
    return {
      subject: `Vos résultats au ${clubName} vous attendent`,
      preheader: 'Finalisez votre compte et consultez-les vous-même.',
      greeting: naam ? `Bonjour ${naam},` : 'Bonjour,',
      played: `Vous avez joué au ${clubName}. Vos résultats sont enregistrés à votre nom : points, places et gains.`,
      platform: `${clubName} les tient à jour sur PokerLeague, la plateforme où les clubs belges gèrent leurs tournois. Finalisez votre compte et vous les verrez vous-même, sur votre téléphone, après chaque session. Si vous jouez plus tard dans un autre club sur PokerLeague, tout se retrouve au même endroit.`,
      cta: 'Finaliser mon compte',
      expires: `Ce lien est valable jusqu’au ${date}.`,
      reply: 'Une question sur le club ? Répondez simplement à cet e-mail.',
      why: `Vous recevez ceci parce que vous avez donné votre adresse à l’entrée du ${clubName}. Si vous ne faites rien, il ne se passe rien.`,
      fallback: 'Le bouton ne fonctionne pas ? Copiez ce lien dans votre navigateur :',
    }
  }

  if (i.locale === 'en') {
    return {
      subject: `Your results at ${clubName} are waiting`,
      preheader: 'Finish your account and see them for yourself.',
      greeting: naam ? `Hi ${naam},` : 'Hi,',
      played: `You played at ${clubName}. Your results are recorded under your name — points, finishes and winnings.`,
      platform: `${clubName} keeps them on PokerLeague, the platform Belgian clubs use to run their tournaments. Finish your account and you can see them yourself, on your phone, after every session. Play at another club on PokerLeague later and it all lands in the same place.`,
      cta: 'Finish my account',
      expires: `This link works until ${date}.`,
      reply: 'A question about the club? Just reply to this email.',
      why: `You are getting this because you gave your address at the door at ${clubName}. If you do nothing, nothing happens.`,
      fallback: 'Button not working? Copy this link into your browser:',
    }
  }

  return {
    subject: `Je resultaten bij ${clubName} staan klaar`,
    preheader: 'Maak je account af, dan zie je ze zelf.',
    greeting: naam ? `Dag ${naam},` : 'Dag,',
    played: `Je speelde bij ${clubName}. Je resultaten staan genoteerd op je naam — punten, plaatsen en prijzengeld.`,
    platform: `${clubName} houdt die bij op PokerLeague, het platform waar Belgische clubs hun tornooien draaien. Maak je account af en je ziet ze zelf, op je gsm, na elke sessie. Speel je later bij een andere club op PokerLeague, dan komt dat er gewoon bij.`,
    cta: 'Account afmaken',
    expires: `Deze link werkt tot ${date}.`,
    reply: 'Een vraag over de club? Antwoord gewoon op deze mail.',
    why: `Je krijgt dit omdat je je mailadres gaf aan de deur bij ${clubName}. Doe je niets, dan gebeurt er niets.`,
    fallback: 'Werkt de knop niet? Plak deze link in je browser:',
  }
}

/** Tekst die in HTML terechtkomt eerst ontsmetten. Een clubnaam met een & erin mag niets breken. */
function esc(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
}

export function inviteMail(input: InviteMailInput): {
  subject: string
  html: string
  text: string
} {
  const c = copy(input)
  const url = input.url

  const text = [
    c.greeting,
    '',
    c.played,
    '',
    c.platform,
    '',
    `${c.cta}: ${url}`,
    '',
    c.expires,
    c.reply,
    '',
    '—',
    c.why,
  ].join('\n')

  const html = `<!doctype html>
<html lang="${input.locale}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${esc(c.subject)}</title>
</head>
<body style="margin:0;padding:0;background:#f4f4f2;">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;">${esc(c.preheader)}</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#f4f4f2;">
<tr><td align="center" style="padding:32px 16px;">

  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"
         style="max-width:520px;background:#ffffff;border-radius:14px;border:1px solid #e4e4e0;">
    <tr><td style="padding:32px 28px 8px 28px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;">
      <p style="margin:0 0 18px 0;font-size:12px;letter-spacing:.16em;text-transform:uppercase;color:#8a8a82;">
        ${esc(input.clubName)}
      </p>
      <p style="margin:0 0 16px 0;font-size:16px;line-height:1.6;color:#1a1a18;">${esc(c.greeting)}</p>
      <p style="margin:0 0 16px 0;font-size:16px;line-height:1.6;color:#1a1a18;">${esc(c.played)}</p>
      <p style="margin:0 0 26px 0;font-size:16px;line-height:1.6;color:#4a4a44;">${esc(c.platform)}</p>
    </td></tr>

    <tr><td align="left" style="padding:0 28px 26px 28px;">
      <table role="presentation" cellpadding="0" cellspacing="0" border="0">
        <tr><td align="center" bgcolor="#1a1a18" style="border-radius:999px;">
          <a href="${esc(url)}"
             style="display:inline-block;padding:14px 28px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:15px;font-weight:600;color:#ffffff;text-decoration:none;border-radius:999px;">
            ${esc(c.cta)}
          </a>
        </td></tr>
      </table>
    </td></tr>

    <tr><td style="padding:0 28px 30px 28px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;">
      <p style="margin:0 0 6px 0;font-size:14px;line-height:1.6;color:#6a6a62;">${esc(c.expires)}</p>
      <p style="margin:0 0 20px 0;font-size:14px;line-height:1.6;color:#6a6a62;">${esc(c.reply)}</p>
      <p style="margin:0;font-size:12px;line-height:1.6;color:#9a9a92;word-break:break-all;">
        ${esc(c.fallback)}<br><a href="${esc(url)}" style="color:#9a9a92;">${esc(url)}</a>
      </p>
    </td></tr>
  </table>

  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:520px;">
    <tr><td style="padding:18px 28px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;">
      <p style="margin:0;font-size:12px;line-height:1.6;color:#9a9a92;">${esc(c.why)}</p>
    </td></tr>
  </table>

</td></tr>
</table>
</body>
</html>`

  return { subject: c.subject, html, text }
}
