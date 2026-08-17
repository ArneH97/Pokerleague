import Link from 'next/link'
import { createClient } from '@/lib/supabase/server'

/**
 * De publieke voorkant van PokerLeague.
 *
 * Bewust geen tornooilijst meer: iemand die hier voor het eerst komt weet nog
 * niet wat dit is, en een lijst met namen van tornooien waar hij niets mee
 * kan legt dat niet uit. Eerst vertellen wat het is, dan pas aanmelden.
 *
 * Licht van opzet, in tegenstelling tot de app zelf. Die is donker omdat hij
 * 's avonds in een zaal draait; deze pagina opent iemand overdag op zijn
 * telefoon.
 */
export const metadata = {
  title: 'PokerLeague — pokertornooien in België',
  description:
    'Alle tornooien van je club op één plek. Live standen, inschrijven, en al je resultaten over clubs heen.',
}

export default async function Page() {
  const supabase = await createClient()
  const { data: claims } = await supabase.auth.getClaims()
  const loggedIn = Boolean(claims?.claims)

  const { count } = await supabase
    .from('clubs')
    .select('id', { count: 'exact', head: true })
    .eq('is_active', true)

  return (
    <div data-light className="min-h-dvh bg-[var(--bg)] text-[var(--text)]">
      <header className="mx-auto flex max-w-5xl items-center justify-between px-5 py-5 sm:px-8">
        <span className="text-sm font-semibold uppercase tracking-[0.22em]">
          Poker<span className="text-[var(--brand)]">League</span>
        </span>

        {/* Bewust klein en in de hoek: wie hier voor het eerst komt moet
            eerst lezen, niet meteen een inlogscherm zien. */}
        <nav className="flex items-center gap-1 text-sm">
          {loggedIn ? (
            <>
              <Link
                href="/clubs"
                className="rounded-full px-3.5 py-2 text-[var(--text-muted)] transition hover:bg-[var(--surface-hover)] hover:text-[var(--text)]"
              >
                Clubs
              </Link>
              <form action="/auth/signout" method="post">
                <button className="rounded-full px-3.5 py-2 text-[var(--text-muted)] transition hover:bg-[var(--surface-hover)] hover:text-[var(--text)]">
                  Afmelden
                </button>
              </form>
            </>
          ) : (
            <>
              <Link
                href="/login"
                className="rounded-full px-3.5 py-2 text-[var(--text-muted)] transition hover:bg-[var(--surface-hover)] hover:text-[var(--text)]"
              >
                Spelers
              </Link>
              <Link
                href="/clubs"
                className="rounded-full px-3.5 py-2 text-[var(--text-muted)] transition hover:bg-[var(--surface-hover)] hover:text-[var(--text)]"
              >
                Clubs
              </Link>
            </>
          )}
        </nav>
      </header>

      <main>
        {/* ------------------------------------------------------------ hero */}
        <section className="relative overflow-hidden">
          <div
            aria-hidden
            className="pointer-events-none absolute inset-0 -z-10"
            style={{
              background:
                'radial-gradient(60rem 30rem at 50% -8rem, rgba(4,120,87,0.10) 0%, transparent 70%)',
            }}
          />
          <div className="mx-auto max-w-3xl px-5 pb-16 pt-16 text-center sm:px-8 sm:pb-24 sm:pt-24">
            <p className="mb-4 inline-flex items-center gap-2 rounded-full border border-[var(--line)] px-3 py-1 text-xs font-medium text-[var(--text-muted)]">
              <span className="size-1.5 rounded-full bg-[var(--brand)]" />
              In opbouw met de eerste Belgische clubs
            </p>
            <h1 className="text-balance text-4xl font-semibold leading-[1.1] tracking-tight sm:text-6xl">
              Elke hand die je speelt,{' '}
              <span className="text-[var(--brand)]">telt mee</span>.
            </h1>
            <p className="mx-auto mt-5 max-w-xl text-pretty text-lg leading-relaxed text-[var(--text-muted)]">
              PokerLeague verzamelt de tornooien van Belgische pokerclubs op één
              plek. Schrijf je in bij je club, volg de stand terwijl er gespeeld
              wordt, en zie je resultaten van alle clubs samen.
            </p>
            <div className="mt-9 flex flex-wrap items-center justify-center gap-3">
              <Link
                href="/login"
                className="rounded-full bg-[var(--brand)] px-6 py-3 font-medium text-[var(--on-brand)] transition hover:brightness-110"
              >
                Aanmelden als speler
              </Link>
              <Link
                href="/clubs"
                className="rounded-full border border-[var(--line-strong)] px-6 py-3 font-medium transition hover:bg-[var(--surface-hover)]"
              >
                Ik ben een club
              </Link>
            </div>
          </div>
        </section>

        {/* ------------------------------------------------------- voor spelers */}
        <Section
          overline="Voor spelers"
          title="Je pokerjaar op één plek"
          intro="Gratis. Je club nodigt je uit, of je meldt je aan bij de club waar je speelt."
        >
          <Feature title="Live meekijken">
            Zie tijdens een tornooi wie er aan de leiding staat, hoeveel spelers
            er over zijn en op welk level ze spelen — ook als je er zelf niet bij
            bent.
          </Feature>
          <Feature title="Inschrijven vooraf">
            Eén klik voor de tornooien van je club. De floor weet zo op voorhand
            hoeveel tafels er nodig zijn.
          </Feature>
          <Feature title="Al je resultaten">
            Elke plaats, elke cash, elk seizoen. Speel je bij meerdere clubs, dan
            staat alles bij elkaar in plaats van in losse Excel-bestanden.
          </Feature>
        </Section>

        {/* --------------------------------------------------------- voor clubs */}
        <Section
          overline="Voor clubs"
          title="Meer dan een tornooiklok"
          intro="Je eigen omgeving, met je eigen logo en kleuren, op je eigen adres."
          tinted
        >
          <Feature title="Klok en floor">
            Een zaalscherm voor de beamer en een bedieningsscherm voor de floor,
            die realtime gelijklopen. Met geluid bij de laatste minuut en bij
            elke nieuwe blindronde.
          </Feature>
          <Feature title="Ledenbestand en klassement">
            Wie speelde er, wat kocht hij in, waar eindigde hij. Punten en
            seizoensranking worden vanzelf bijgehouden, met jouw eigen
            puntensysteem.
          </Feature>
          <Feature title="In orde met de regels">
            Elke inzet wordt geregistreerd, zodat je kan aantonen dat niemand
            boven de daglimiet van het gedoogbeleid ging.
          </Feature>
        </Section>

        {/* ------------------------------------------------------------ slot */}
        <section className="mx-auto max-w-3xl px-5 py-20 text-center sm:px-8">
          <h2 className="text-2xl font-semibold tracking-tight sm:text-3xl">
            Interesse voor je club?
          </h2>
          <p className="mx-auto mt-3 max-w-lg text-[var(--text-muted)]">
            {count && count > 1
              ? `Er zijn al ${count} clubs aangesloten.`
              : 'We starten met de eerste clubs.'}{' '}
            Laat weten wie je bent, dan zetten we je omgeving op.
          </p>
          <a
            href="mailto:info@pokerleague.be?subject=Interesse%20PokerLeague"
            className="mt-7 inline-block rounded-full bg-[var(--brand)] px-6 py-3 font-medium text-[var(--on-brand)] transition hover:brightness-110"
          >
            info@pokerleague.be
          </a>
        </section>
      </main>

      <footer className="border-t border-[var(--line)]">
        <div className="mx-auto flex max-w-5xl flex-wrap items-center justify-between gap-3 px-5 py-7 text-sm text-[var(--text-faint)] sm:px-8">
          <span>PokerLeague · België</span>
          <span className="flex gap-4">
            <Link href="/login" className="transition hover:text-[var(--text-muted)]">
              Spelerslogin
            </Link>
            <Link href="/clubs" className="transition hover:text-[var(--text-muted)]">
              Clublogin
            </Link>
          </span>
        </div>
      </footer>
    </div>
  )
}

function Section({
  overline, title, intro, tinted, children,
}: {
  overline: string
  title: string
  intro: string
  tinted?: boolean
  children: React.ReactNode
}) {
  return (
    <section className={tinted ? 'border-y border-[var(--line)] bg-[var(--surface-2)]' : ''}>
      <div className="mx-auto max-w-5xl px-5 py-16 sm:px-8 sm:py-20">
        <p className="text-xs font-medium uppercase tracking-[0.2em] text-[var(--brand)]">
          {overline}
        </p>
        <h2 className="mt-2 max-w-xl text-3xl font-semibold tracking-tight">{title}</h2>
        <p className="mt-3 max-w-xl text-[var(--text-muted)]">{intro}</p>
        <div className="mt-10 grid gap-x-8 gap-y-9 sm:grid-cols-3">{children}</div>
      </div>
    </section>
  )
}

function Feature({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div>
      <h3 className="flex items-center gap-2 font-semibold">
        <span aria-hidden className="text-[var(--brand)]">♠</span>
        {title}
      </h3>
      <p className="mt-2 text-sm leading-relaxed text-[var(--text-muted)]">{children}</p>
    </div>
  )
}
