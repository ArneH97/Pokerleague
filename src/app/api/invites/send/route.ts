import { type NextRequest } from 'next/server'
import { inviteMail } from '@/lib/email/invite'
import { isLocale } from '@/lib/i18n/dictionaries'
import { mailConfigured, sendMail } from '@/lib/mail'
import { createClient } from '@/lib/supabase/server'
import { createServiceClient } from '@/lib/supabase/service'

/**
 * De wachtrij met uitnodigingen leeghalen.
 *
 * `floor_add_entry` zet een rij in `player_invites` zodra de floor iemand
 * intikt die nog niet bestond. Hier gaan die effectief de deur uit.
 *
 * **Waarom niet meteen versturen aan de deur?** Omdat de floor daar staat met
 * een rij mensen achter zich. Een HTTP-aanroep naar een mailprovider midden in
 * dat scherm maakt het inschrijven trager en, erger, kan mislukken — en dan
 * staat de floor met een foutmelding waar hij niets mee kan terwijl de volgende
 * al zijn geld boven haalt. Inschrijven mag nooit afhangen van of er ergens
 * anders een mail vertrekt. Vandaar een wachtrij: het inschrijven slaagt
 * altijd, en het versturen is een apart probleem dat opnieuw geprobeerd mag
 * worden.
 *
 * **Twee manieren om hier binnen te komen.**
 *
 * 1. Met het geheim uit `CRON_SECRET`. Zo roept Vercel Cron dit aan, en dan
 *    gaat de verzender over alle clubs. Dat is de enige plek waar de
 *    service-sleutel bovengehaald wordt.
 * 2. Met een gewone sessie. Dan draait alles op de sessieclient, en filtert
 *    de RLS-policy op `player_invites` vanzelf op wat dit bestuurslid mag
 *    zien — namelijk de uitnodigingen van zijn eigen clubs. Het scherm hoeft
 *    dus niets af te schermen: doet iemand dit zonder rechten, dan is de lijst
 *    gewoon leeg. Dezelfde poort als overal, en niet een tweede.
 */

export const dynamic = 'force-dynamic'
export const maxDuration = 60

/** Hoeveel per keer. Genoeg voor een clubavond, kort genoeg om binnen de tijd te blijven. */
const BATCH = 25

/** Resend laat een paar aanvragen per seconde toe. Rustig aan is hier gratis. */
const PACE_MS = 150

interface Row {
  id: string
  email: string
  token: string
  expires_at: string
  attempts: number
  club: { name: string; locale: string; contact_email: string | null } | null
  player: { display_name: string; locale: string; auth_user_id: string | null } | null
}

function baseUrl(req: NextRequest): string {
  const set = process.env.NEXT_PUBLIC_SITE_URL
  if (set) return set.replace(/\/+$/, '')
  // Valt terug op waar dit verzoek binnenkwam. Bij een cronjob is dat het
  // Vercel-adres van de deployment, wat werkt maar lelijk staat in een mail —
  // vandaar dat NEXT_PUBLIC_SITE_URL in productie hoort te staan.
  return req.nextUrl.origin
}

async function drain(req: NextRequest) {
  const secret = process.env.CRON_SECRET
  const asCron = Boolean(secret && req.headers.get('authorization') === `Bearer ${secret}`)

  if (!mailConfigured()) {
    return Response.json(
      { ok: false, error: 'Er is geen mailsleutel ingesteld (RESEND_API_KEY, MAIL_FROM).' },
      { status: 503 },
    )
  }

  // De service-sleutel komt er alleen aan te pas als het geheim klopte.
  const supabase = asCron ? createServiceClient() : await createClient()

  if (!asCron) {
    const { data: claims } = await supabase.auth.getClaims()
    if (!claims?.claims) {
      return Response.json({ ok: false, error: 'Niet aangemeld' }, { status: 401 })
    }
  }

  const { data, error } = await supabase
    .from('player_invites')
    .select(
      'id,email,token,expires_at,attempts,' +
        'club:clubs(name,locale,contact_email),' +
        'player:players(display_name,locale,auth_user_id)',
    )
    .is('sent_at', null)
    .is('accepted_at', null)
    .lt('attempts', 3)
    .gt('expires_at', new Date().toISOString())
    .order('created_at', { ascending: true })
    .limit(BATCH)
    .overrideTypes<Row[]>()

  if (error) {
    return Response.json({ ok: false, error: error.message }, { status: 500 })
  }

  const rows = data ?? []
  const origin = baseUrl(req)
  let sent = 0
  let failed = 0
  let skipped = 0

  for (const row of rows) {
    // Geen speler achter de uitnodiging. Dat hoort niet te kunnen — er staat
    // een verplichte verwijzing op — dus als het tóch gebeurt komt het van de
    // leesrechten: op de sessieweg filtert RLS ook `players` mee, en ziet dit
    // bestuurslid de persoon niet. Dan is de veilige zet niets doen. Een mail
    // zonder naam versturen is erg genoeg, maar het echte gevaar is dat we
    // hieronder niet kunnen zien of hij intussen al een account heeft.
    if (!row.player) {
      await supabase
        .from('player_invites')
        .update({
          last_try_at: new Date().toISOString(),
          last_error: 'speler niet leesbaar met deze rechten',
        })
        .eq('id', row.id)
      failed++
      continue
    }

    // Intussen zelf geregistreerd. Dan is de uitnodiging achterhaald en zou
    // ze alleen maar verwarren: hij hééft zijn account al.
    if (row.player?.auth_user_id) {
      await supabase
        .from('player_invites')
        .update({ accepted_at: new Date().toISOString() })
        .eq('id', row.id)
      skipped++
      continue
    }

    const clubName = row.club?.name ?? 'PokerLeague'
    const raw = row.player?.locale ?? row.club?.locale ?? 'nl'
    const locale = isLocale(raw) ? raw : 'nl'

    const mail = inviteMail({
      playerName: row.player?.display_name ?? '',
      clubName,
      url: `${origin}/uitnodiging/${row.token}`,
      expiresOn: new Date(row.expires_at),
      locale,
    })

    const res = await sendMail({
      to: row.email,
      subject: mail.subject,
      html: mail.html,
      text: mail.text,
      // De club is de afzender en het antwoordadres. De speler kent de club,
      // niet ons — een antwoord hoort daar terecht te komen.
      fromName: clubName,
      replyTo: row.club?.contact_email ?? undefined,
    })

    const now = new Date().toISOString()
    if (res.ok) {
      await supabase
        .from('player_invites')
        .update({ sent_at: now, last_try_at: now, last_error: null, attempts: row.attempts + 1 })
        .eq('id', row.id)
      sent++
    } else {
      await supabase
        .from('player_invites')
        .update({ last_try_at: now, last_error: res.error ?? 'onbekend', attempts: row.attempts + 1 })
        .eq('id', row.id)
      failed++
    }

    if (PACE_MS) await new Promise((r) => setTimeout(r, PACE_MS))
  }

  return Response.json({
    ok: true,
    scope: asCron ? 'alle clubs' : 'eigen clubs',
    found: rows.length,
    sent,
    failed,
    skipped,
    // Er stonden er meer klaar dan er in één ronde passen.
    more: rows.length === BATCH,
    // Niets gevonden is geen antwoord. Zie de uitleg bij diagnose().
    ...(rows.length === 0 && !asCron ? { diagnose: await diagnose(supabase) } : {}),
  })
}

/**
 * Waarom stond er niets klaar?
 *
 * `found: 0` is een slecht antwoord. Het kan drie totaal verschillende dingen
 * betekenen — er bestaat geen uitnodiging, ze bestaat wel maar is al verstuurd
 * of afgevinkt, of jouw account mag ze niet zien — en die drie los je elk
 * anders op. Dit heeft me drie rondes kosten om uit te zoeken met de gebruiker
 * ertussen; dat hoort de route zelf te vertellen.
 *
 * Loopt bewust via `club_invites`, niet via de tabel: die functie is
 * security definer en laat staf van een club álles zien, ook wat al verstuurd
 * of afgevinkt is. Precies wat je wil weten als er niets vertrok.
 */
interface StaffClub { slug: string; name: string; role: string }
interface InviteRow {
  email: string
  player_name: string
  sent_at: string | null
  accepted_at: string | null
  attempts: number
  last_error: string | null
}

async function diagnose(
  supabase: Awaited<ReturnType<typeof createClient>>,
): Promise<Record<string, unknown>> {
  const { data: staffData } = await supabase.rpc('my_staff_clubs')
  const staff = (staffData ?? []) as unknown as StaffClub[]

  if (staff.length === 0) {
    return {
      reden: 'Dit account is bij geen enkele club owner of admin, dus het ziet geen enkele wachtrij.',
      staf_bij: [],
    }
  }

  const perClub: Record<string, unknown> = {}

  for (const c of staff) {
    const { data: clubRow } = await supabase
      .from('clubs').select('id').eq('slug', c.slug).maybeSingle<{ id: string }>()
    if (!clubRow) continue

    const { data: invData, error } = await supabase.rpc('club_invites', { p_club_id: clubRow.id })
    if (error) { perClub[c.slug] = { fout: error.message }; continue }

    const rows = (invData ?? []) as unknown as InviteRow[]
    perClub[c.slug] = {
      totaal: rows.length,
      al_verstuurd: rows.filter((r) => r.sent_at).length,
      afgevinkt: rows.filter((r) => !r.sent_at && r.accepted_at).length,
      opgegeven: rows.filter((r) => !r.sent_at && !r.accepted_at && r.attempts >= 3).length,
      laatste: rows.slice(0, 5).map((r) => ({
        email: r.email,
        naam: r.player_name,
        verstuurd: r.sent_at,
        afgevinkt: r.accepted_at,
        pogingen: r.attempts,
        fout: r.last_error,
      })),
    }
  }

  const totaal = Object.values(perClub).reduce<number>(
    (n, v) => n + (typeof v === 'object' && v !== null && 'totaal' in v ? Number(v.totaal) : 0),
    0,
  )

  return {
    reden: totaal === 0
      ? 'Er bestaat geen enkele uitnodiging bij je clubs. Ze wordt dus niet aangemaakt — draai migratie 0032.'
      : 'Er bestaan wel uitnodigingen, maar geen enkele staat nog open. Zie per_club waarom.',
    staf_bij: staff.map((c) => `${c.slug} (${c.role})`),
    per_club: perClub,
  }
}

/** Vercel Cron roept met GET aan. */
export async function GET(req: NextRequest) {
  return drain(req)
}

/** Het scherm met POST, zodat een browser dit niet per ongeluk voorlaadt. */
export async function POST(req: NextRequest) {
  return drain(req)
}
