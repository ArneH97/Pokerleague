import Link from 'next/link'
import { createClient } from '@/lib/supabase/server'

/**
 * Clubkiezer.
 *
 * Elke club heeft zijn eigen omgeving op zijn eigen adres. Wie via
 * pokerleague.be binnenkomt weet dat adres niet altijd uit het hoofd, dus
 * hier staat de lijst. Vanaf hun eigen domein komt niemand hier ooit terecht.
 */
export const metadata = { title: 'Clubs — PokerLeague' }

interface Row {
  slug: string
  name: string
  city: string | null
  logo_url: string | null
  custom_domain: string | null
}

export default async function Page() {
  const supabase = await createClient()
  const { data } = await supabase
    .from('clubs')
    .select('slug,name,city,logo_url,custom_domain')
    .eq('is_active', true)
    .order('name')
    .overrideTypes<Row[]>()

  const clubs = data ?? []

  return (
    <div data-light className="min-h-dvh bg-[var(--bg)] text-[var(--text)]">
      <header className="mx-auto flex max-w-3xl items-center justify-between px-5 py-5 sm:px-8">
        <Link href="/" className="text-sm font-semibold uppercase tracking-[0.22em]">
          Poker<span className="text-[var(--brand)]">League</span>
        </Link>
        <Link
          href="/login"
          className="rounded-full px-3.5 py-2 text-sm text-[var(--text-muted)] transition hover:bg-[var(--surface-hover)] hover:text-[var(--text)]"
        >
          Spelers
        </Link>
      </header>

      <main className="mx-auto max-w-3xl px-5 pb-20 pt-8 sm:px-8">
        <h1 className="text-3xl font-semibold tracking-tight">Aanmelden als club</h1>
        <p className="mt-3 max-w-xl text-[var(--text-muted)]">
          Kies je club om naar de beheeromgeving te gaan. Heeft je club een eigen
          adres, dan kan je daar rechtstreeks naartoe.
        </p>

        {clubs.length === 0 ? (
          <div className="mt-10 rounded-[var(--radius-lg)] border border-[var(--line)] p-8 text-center">
            <p className="font-medium">Nog geen clubs aangesloten.</p>
            <p className="mt-2 text-sm text-[var(--text-muted)]">
              Wil je de eerste zijn?{' '}
              <a className="text-[var(--brand)] underline underline-offset-4" href="mailto:info@pokerleague.be">
                info@pokerleague.be
              </a>
            </p>
          </div>
        ) : (
          <ul className="mt-9 space-y-3">
            {clubs.map((c) => (
              <li key={c.slug}>
                <Link
                  href={`/c/${c.slug}/login`}
                  className="flex items-center gap-4 rounded-[var(--radius-lg)] border border-[var(--line)] p-4 transition hover:border-[var(--line-strong)] hover:bg-[var(--surface-hover)]"
                >
                  <span className="flex size-12 shrink-0 items-center justify-center overflow-hidden rounded-[var(--radius)] border border-[var(--line)] bg-[var(--surface-2)]">
                    {c.logo_url ? (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img src={c.logo_url} alt="" className="size-full object-contain p-1" />
                    ) : (
                      <span className="text-lg font-semibold text-[var(--text-faint)]">
                        {c.name.slice(0, 1)}
                      </span>
                    )}
                  </span>
                  <span className="min-w-0 flex-1">
                    <span className="block truncate font-medium">{c.name}</span>
                    <span className="block truncate text-sm text-[var(--text-muted)]">
                      {[c.city, c.custom_domain].filter(Boolean).join(' · ') || 'Beheeromgeving'}
                    </span>
                  </span>
                  <span aria-hidden className="text-[var(--text-faint)]">→</span>
                </Link>
              </li>
            ))}
          </ul>
        )}
      </main>
    </div>
  )
}
