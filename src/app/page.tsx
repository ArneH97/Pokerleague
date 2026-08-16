import Link from 'next/link'
import { createClient } from '@/lib/supabase/server'
import { formatMoney } from '@/lib/types'

interface Row {
  id: string
  name: string
  scheduled_at: string
  status: string
  buyin_cents: number
  fee_cents: number
  clubs: { name: string; slug: string; timezone: string } | null
}

export default async function Page() {
  const supabase = await createClient()
  const { data: claims } = await supabase.auth.getClaims()

  const { data, error } = await supabase
    .from('tournaments')
    .select('id,name,scheduled_at,status,buyin_cents,fee_cents,clubs(name,slug,timezone)')
    .order('scheduled_at', { ascending: false })
    .limit(25)
    .overrideTypes<Row[]>()

  const tournaments = data ?? []

  return (
    <main className="mx-auto min-h-dvh w-full max-w-3xl space-y-8 bg-neutral-950 p-6 text-white">
      <header className="flex items-start justify-between gap-4">
        <div>
          <p className="text-sm uppercase tracking-widest text-neutral-500">ClubStack</p>
          <h1 className="text-2xl font-semibold">Tornooien</h1>
        </div>
        {claims?.claims ? (
          <form action="/auth/signout" method="post">
            <button className="rounded-lg border border-neutral-700 px-3 py-1.5 text-sm hover:bg-neutral-800">
              Afmelden
            </button>
          </form>
        ) : (
          <Link
            href="/login"
            className="rounded-lg bg-emerald-600 px-3 py-1.5 text-sm hover:bg-emerald-500"
          >
            Aanmelden
          </Link>
        )}
      </header>

      {error && (
        <p className="rounded-xl border border-red-900 bg-red-950/50 p-4 text-sm text-red-300">
          {error.message}
        </p>
      )}

      {tournaments.length === 0 && !error && (
        <div className="rounded-xl border border-neutral-800 p-6 text-neutral-400">
          <p className="font-medium text-neutral-200">Nog geen tornooien zichtbaar.</p>
          <p className="mt-2 text-sm">
            {claims?.claims
              ? 'Je account is nog aan geen enkele club gekoppeld, of er staat nog niets gepland.'
              : 'Meld je aan om de tornooien van je club te zien.'}
          </p>
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
                {t.clubs?.name} ·{' '}
                {new Intl.DateTimeFormat('nl-BE', {
                  dateStyle: 'full',
                  timeStyle: 'short',
                  timeZone: t.clubs?.timezone ?? 'Europe/Brussels',
                }).format(new Date(t.scheduled_at))}
                {' · '}
                {formatMoney(t.buyin_cents + t.fee_cents)}
              </p>
            </div>
            <div className="flex shrink-0 items-center gap-2">
              <StatusBadge status={t.status} />
              <Link
                href={`/klok/${t.id}`}
                className="rounded-lg border border-neutral-700 px-3 py-1.5 text-sm hover:bg-neutral-800"
              >
                Klok
              </Link>
              <Link
                href={`/floor/${t.id}`}
                className="rounded-lg bg-neutral-100 px-3 py-1.5 text-sm font-medium text-neutral-900 hover:bg-white"
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

function StatusBadge({ status }: { status: string }) {
  const label: Record<string, string> = {
    draft: 'Concept', scheduled: 'Gepland', running: 'Bezig',
    paused: 'Gepauzeerd', finished: 'Afgelopen', cancelled: 'Geannuleerd',
  }
  const tone =
    status === 'running' ? 'bg-emerald-950 text-emerald-400'
      : status === 'finished' ? 'bg-neutral-800 text-neutral-400'
      : 'bg-neutral-800 text-neutral-300'

  return (
    <span className={`rounded-full px-2.5 py-1 text-xs ${tone}`}>
      {label[status] ?? status}
    </span>
  )
}
