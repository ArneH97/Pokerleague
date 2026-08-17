import Link from 'next/link'
import { createClient } from '@/lib/supabase/server'
import { formatMoney } from '@/lib/types'

/**
 * De spelerskant: PokerLeague.
 *
 * Hier staat wél de platformnaam, want dit is het platform waar spelers zich
 * op aanmelden. De clubomgevingen onder /c/<slug> dragen alleen de naam van
 * de club zelf.
 */
export const metadata = { title: 'PokerLeague' }

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
  const loggedIn = Boolean(claims?.claims)

  const { data: tournamentData } = await supabase
    .from('tournaments')
    .select('id,name,scheduled_at,status,buyin_cents,fee_cents,clubs(name,slug,timezone)')
    .order('scheduled_at', { ascending: false })
    .limit(25)
    .overrideTypes<Row[]>()

  // Clubs waar deze gebruiker staf is: dan hoort hij eigenlijk in de
  // clubomgeving thuis, niet hier.
  const { data: memberships } = loggedIn
    ? await supabase
        .from('club_members')
        .select('role, clubs(slug, name)')
        .overrideTypes<{ role: string; clubs: { slug: string; name: string } | null }[]>()
    : { data: null }

  const tournaments = tournamentData ?? []
  const staffClubs = (memberships ?? []).filter((m) => m.clubs)

  return (
    <main className="mx-auto min-h-dvh w-full max-w-3xl space-y-8 bg-[var(--bg)] p-6 text-white">
      <header className="flex items-start justify-between gap-4">
        <div>
          <p className="text-sm uppercase tracking-widest text-[var(--text-faint)]">PokerLeague</p>
          <h1 className="text-2xl font-semibold">Tornooien in België</h1>
        </div>
        {loggedIn ? (
          <form action="/auth/signout" method="post">
            <button className="rounded-lg border border-[var(--line-strong)] px-3 py-1.5 text-sm hover:bg-[var(--surface-hover)]">
              Afmelden
            </button>
          </form>
        ) : (
          <Link
            href="/login"
            className="rounded-lg bg-[var(--brand)] px-3 py-1.5 text-sm hover:brightness-110"
          >
            Aanmelden
          </Link>
        )}
      </header>

      {staffClubs.length > 0 && (
        <section className="rounded-xl border border-[var(--line)] p-4">
          <p className="text-sm text-[var(--text-muted)]">Je beheert:</p>
          <ul className="mt-2 flex flex-wrap gap-2">
            {staffClubs.map((m) => (
              <li key={m.clubs!.slug}>
                <Link
                  href={`/c/${m.clubs!.slug}`}
                  className="inline-block rounded-lg bg-[var(--text)] px-3 py-1.5 text-sm font-medium text-[var(--bg)] hover:bg-white"
                >
                  {m.clubs!.name} →
                </Link>
              </li>
            ))}
          </ul>
        </section>
      )}

      {tournaments.length === 0 && (
        <div className="rounded-xl border border-[var(--line)] p-6 text-[var(--text-muted)]">
          <p className="font-medium text-[var(--text)]">Nog geen tornooien zichtbaar.</p>
          <p className="mt-2 text-sm">
            {loggedIn
              ? 'Je bent nog geen lid van een club, of er staat nog niets gepland.'
              : 'Meld je aan om de tornooien van je club te zien.'}
          </p>
        </div>
      )}

      <ul className="space-y-3">
        {tournaments.map((t) => (
          <li key={t.id} className="rounded-xl border border-[var(--line)] p-4">
            <p className="font-medium">{t.name}</p>
            <p className="text-sm text-[var(--text-faint)]">
              {t.clubs?.name} ·{' '}
              {new Intl.DateTimeFormat('nl-BE', {
                dateStyle: 'full',
                timeStyle: 'short',
                timeZone: t.clubs?.timezone ?? 'Europe/Brussels',
              }).format(new Date(t.scheduled_at))}
              {' · '}
              {formatMoney(t.buyin_cents + t.fee_cents)}
            </p>
          </li>
        ))}
      </ul>
    </main>
  )
}
