import Link from 'next/link'
import { notFound, redirect } from 'next/navigation'
import { getClub, getClubRole } from '@/lib/club'
import { createClient } from '@/lib/supabase/server'
import { formatMoney } from '@/lib/types'

interface Row {
  id: string
  name: string
  scheduled_at: string
  status: string
  buyin_cents: number
  fee_cents: number
}

const STATUS: Record<string, string> = {
  draft: 'Concept', scheduled: 'Gepland', running: 'Bezig',
  paused: 'Gepauzeerd', finished: 'Afgelopen', cancelled: 'Geannuleerd',
}

export default async function Page({ params }: PageProps<'/c/[club]'>) {
  const { club: slug } = await params
  const club = await getClub(slug)
  if (!club) notFound()

  const supabase = await createClient()
  const { data: claims } = await supabase.auth.getClaims()
  if (!claims?.claims) redirect(`/c/${slug}/login`)

  const role = await getClubRole(club.id)

  const { data } = await supabase
    .from('tournaments')
    .select('id,name,scheduled_at,status,buyin_cents,fee_cents')
    .eq('club_id', club.id)
    .order('scheduled_at', { ascending: false })
    .limit(50)
    .overrideTypes<Row[]>()

  const tournaments = data ?? []
  const fmt = new Intl.DateTimeFormat('nl-BE', {
    dateStyle: 'full', timeStyle: 'short', timeZone: club.timezone,
  })

  return (
    <main className="mx-auto min-h-dvh w-full max-w-3xl space-y-8 bg-neutral-950 p-6 text-white">
      <header className="flex items-start justify-between gap-4">
        <div className="flex items-center gap-3">
          {club.logo_url && (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={club.logo_url} alt="" className="size-11 rounded object-contain" />
          )}
          <div>
            <h1 className="text-2xl font-semibold">{club.name}</h1>
            <p className="text-sm text-neutral-500">
              {club.city ? `${club.city} · ` : ''}Tornooibeheer
            </p>
          </div>
        </div>
        <form action="/auth/signout" method="post">
          <button className="rounded-lg border border-neutral-700 px-3 py-1.5 text-sm hover:bg-neutral-800">
            Afmelden
          </button>
        </form>
      </header>

      {!role && (
        <p className="rounded-xl border border-amber-900 bg-amber-950/50 p-4 text-sm text-amber-300">
          Je account is niet gekoppeld aan deze club, dus je ziet hier niets.
          Vraag een beheerder om je toe te voegen.
        </p>
      )}

      {role && tournaments.length === 0 && (
        <div className="rounded-xl border border-neutral-800 p-6 text-neutral-400">
          <p className="font-medium text-neutral-200">Nog geen tornooien.</p>
          <p className="mt-2 text-sm">Maak er een aan om de klok te kunnen gebruiken.</p>
        </div>
      )}

      <ul className="space-y-3">
        {tournaments.map((t) => (
          <li
            key={t.id}
            className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-neutral-800 p-4"
          >
            <div className="min-w-0">
              <p className="truncate font-medium">{t.name}</p>
              <p className="text-sm text-neutral-500">
                {fmt.format(new Date(t.scheduled_at))}
                {' · '}
                {formatMoney(t.buyin_cents + t.fee_cents, club.currency)}
              </p>
            </div>
            <div className="flex shrink-0 items-center gap-2">
              <span
                className={`rounded-full px-2.5 py-1 text-xs ${
                  t.status === 'running'
                    ? 'bg-emerald-950 text-emerald-400'
                    : 'bg-neutral-800 text-neutral-300'
                }`}
              >
                {STATUS[t.status] ?? t.status}
              </span>
              <Link
                href={`/c/${club.slug}/klok/${t.id}`}
                className="rounded-lg border border-neutral-700 px-3 py-1.5 text-sm hover:bg-neutral-800"
              >
                Klok
              </Link>
              <Link
                href={`/c/${club.slug}/floor/${t.id}`}
                className="rounded-lg px-3 py-1.5 text-sm font-medium"
                style={{ background: 'var(--club-brand)', color: 'var(--club-on-brand)' }}
              >
                Floor
              </Link>
            </div>
          </li>
        ))}
      </ul>
    </main>
  )
}
