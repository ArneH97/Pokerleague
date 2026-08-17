import Link from 'next/link'
import { createClient } from '@/lib/supabase/server'
import { ClockPreview } from '@/components/marketing/ClockPreview'

/**
 * De publieke voorkant van PokerLeague.
 *
 * Opgebouwd uit volle gekleurde banden in plaats van één smalle kolom op wit:
 * dat leest als een product en niet als een leeg document. Twee kleuren —
 * diepgroen als drager, goud als accent — en per band wisselt de achtergrond
 * zodat je bij het scrollen voelt dat er een nieuw onderwerp begint.
 *
 * Geen tornooilijst: wie hier voor het eerst komt weet nog niet wat dit is,
 * en een rij namen legt dat niet uit.
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

  return (
    <div data-site className="min-h-dvh bg-[var(--bg)] text-[var(--text)]">
      {/* ----------------------------------------------------------- nav */}
      <header className="sticky top-0 z-30 border-b border-[var(--line)] bg-[color-mix(in_oklab,var(--bg)_88%,transparent)] backdrop-blur">
        <div className="mx-auto flex max-w-6xl items-center justify-between px-5 py-3.5 sm:px-8">
          <Wordmark />
          <nav className="flex items-center gap-1 text-sm">
            <a href="#spelers" className="hidden rounded-full px-3.5 py-2 text-[var(--text-muted)] transition hover:bg-[var(--surface-hover)] hover:text-[var(--text)] sm:block">
              Voor spelers
            </a>
            <a href="#clubs" className="hidden rounded-full px-3.5 py-2 text-[var(--text-muted)] transition hover:bg-[var(--surface-hover)] hover:text-[var(--text)] sm:block">
              Voor clubs
            </a>
            {loggedIn ? (
              <>
                <Link href="/clubs" className="rounded-full px-3.5 py-2 text-[var(--text-muted)] transition hover:bg-[var(--surface-hover)] hover:text-[var(--text)]">
                  Mijn club
                </Link>
                <form action="/auth/signout" method="post">
                  <button className="rounded-full px-3.5 py-2 text-[var(--text-muted)] transition hover:bg-[var(--surface-hover)] hover:text-[var(--text)]">
                    Afmelden
                  </button>
                </form>
              </>
            ) : (
              <>
                <Link href="/login" className="rounded-full px-3.5 py-2 text-[var(--text-muted)] transition hover:bg-[var(--surface-hover)] hover:text-[var(--text)]">
                  Spelers
                </Link>
                <Link
                  href="/clubs"
                  className="rounded-full bg-[var(--brand)] px-4 py-2 font-medium text-[var(--on-brand)] transition hover:brightness-110"
                >
                  Clublogin
                </Link>
              </>
            )}
          </nav>
        </div>
      </header>

      <main>
        {/* --------------------------------------------------------- hero */}
        <section className="relative overflow-hidden bg-[var(--surface-2)]">
          <Felt />
          <div className="relative mx-auto grid max-w-6xl items-center gap-12 px-5 py-16 sm:px-8 sm:py-24 lg:grid-cols-[1.05fr_1fr]">
            <div>
              <p className="mb-5 inline-flex items-center gap-2 rounded-full border border-[var(--line-strong)] bg-[var(--bg)] px-3 py-1 text-xs font-medium text-[var(--text-muted)]">
                <span className="size-1.5 rounded-full bg-[var(--gold)]" />
                In opbouw met de eerste Belgische clubs
              </p>
              <h1 className="text-balance text-4xl font-semibold leading-[1.05] tracking-tight sm:text-6xl">
                Elke hand die je speelt,{' '}
                <span className="relative whitespace-nowrap text-[var(--brand)]">
                  telt mee
                  <span
                    aria-hidden
                    className="absolute inset-x-0 -bottom-1 h-2 rounded-full"
                    style={{ background: 'var(--gold-soft)' }}
                  />
                </span>
                .
              </h1>
              <p className="mt-6 max-w-lg text-pretty text-lg leading-relaxed text-[var(--text-muted)]">
                PokerLeague verzamelt de tornooien van Belgische pokerclubs op
                één plek. Schrijf je in bij je club, volg de stand terwijl er
                gespeeld wordt, en zie je resultaten van alle clubs samen.
              </p>
              <div className="mt-8 flex flex-wrap items-center gap-3">
                <Link
                  href="/login"
                  className="rounded-full bg-[var(--brand)] px-6 py-3.5 font-medium text-[var(--on-brand)] transition hover:brightness-110"
                >
                  Aanmelden als speler
                </Link>
                <a
                  href="#clubs"
                  className="rounded-full border border-[var(--line-strong)] bg-[var(--bg)] px-6 py-3.5 font-medium transition hover:bg-[var(--surface-hover)]"
                >
                  Ik ben een club
                </a>
              </div>
              <p className="mt-4 text-sm text-[var(--text-faint)]">
                Gratis voor spelers. Clubs betalen per maand.
              </p>
            </div>

            <ClockPreview />
          </div>
        </section>

        {/* ----------------------------------------------------- voor wie */}
        <section className="mx-auto max-w-6xl px-5 py-16 sm:px-8 sm:py-20">
          <Eyebrow>Voor wie</Eyebrow>
          <h2 className="mt-2 max-w-2xl text-3xl font-semibold tracking-tight sm:text-4xl">
            Twee kanten van dezelfde avond
          </h2>
          <div className="mt-10 grid gap-5 md:grid-cols-2">
            <Audience
              tag="Spelers"
              title="Je pokerjaar op één plek"
              body="Je club nodigt je uit. Vanaf dan zie je waar je speelde, waar je eindigde en hoe je ervoor staat in het klassement — ook als je bij meerdere clubs speelt."
              href="/login"
              cta="Aanmelden als speler"
            />
            <Audience
              tag="Clubs"
              title="Een avond draaien zonder Excel"
              body="Tornooiklok, ledenbestand, inschrijvingen en klassement in één omgeving met je eigen logo en kleuren, op je eigen adres."
              href="#clubs"
              cta="Bekijk wat clubs krijgen"
              gold
            />
          </div>
        </section>

        {/* --------------------------------------------------- hoe het werkt */}
        <section data-band="dark" className="bg-[var(--bg)] text-[var(--text)]">
          <div className="mx-auto max-w-6xl px-5 py-16 sm:px-8 sm:py-20">
            <Eyebrow>Hoe een avond verloopt</Eyebrow>
            <h2 className="mt-2 max-w-2xl text-3xl font-semibold tracking-tight sm:text-4xl">
              Van inschrijving tot klassement, zonder tussenstap
            </h2>
            <ol className="mt-12 grid gap-8 sm:grid-cols-2 lg:grid-cols-4">
              <Step n={1} title="Inschrijven">
                Leden schrijven zich vooraf in via de app. De floor weet hoeveel
                tafels er nodig zijn nog voor de eerste kaart valt.
              </Step>
              <Step n={2} title="Aan de deur">
                De floor vinkt aan wie er is en boekt de inkoop. Wie voor het
                eerst komt staat er in twee seconden bij, zonder account.
              </Step>
              <Step n={3} title="Spelen">
                De klok draait op de beamer, de floor bedient vanaf zijn laptop.
                Spelers volgen de stand op hun telefoon.
              </Step>
              <Step n={4} title="Afsluiten">
                Eén klik. Prijzengeld, punten en het seizoensklassement worden
                berekend en staan meteen bij de spelers.
              </Step>
            </ol>
          </div>
        </section>

        {/* ------------------------------------------------------- spelers */}
        <section id="spelers" className="mx-auto max-w-6xl px-5 py-16 sm:px-8 sm:py-24">
          <Eyebrow>Voor spelers</Eyebrow>
          <h2 className="mt-2 max-w-2xl text-3xl font-semibold tracking-tight sm:text-4xl">
            Gratis, en het onthoudt alles voor je
          </h2>
          <div className="mt-10 grid gap-x-10 gap-y-10 sm:grid-cols-3">
            <Feature title="Live meekijken">
              Zie wie er aan de leiding staat, hoeveel spelers er over zijn en op
              welk level ze spelen — ook als je er zelf niet bij bent.
            </Feature>
            <Feature title="Inschrijven vooraf">
              Eén klik voor de tornooien van je club, en afmelden als het toch
              niet lukt.
            </Feature>
            <Feature title="Al je resultaten">
              Elke plaats, elke cash, elk seizoen. Speel je bij meerdere clubs,
              dan staat alles bij elkaar in plaats van in losse bestanden.
            </Feature>
            <Feature title="Je eigen stack ingeven">
              Tijdens het spel geef je je chipcount door. Daar rolt vanzelf een
              live klassement uit voor de hele tafel.
            </Feature>
            <Feature title="Klassementen">
              Het seizoen van je club, en op termijn een ranking over alle
              aangesloten clubs heen.
            </Feature>
            <Feature title="Niets te installeren">
              Werkt in je browser, op je telefoon. Geen app store, geen updates.
            </Feature>
          </div>
        </section>

        {/* --------------------------------------------------------- clubs */}
        <section id="clubs" data-band="dark" className="bg-[var(--bg)] text-[var(--text)]">
          <div className="mx-auto max-w-6xl px-5 py-16 sm:px-8 sm:py-24">
            <Eyebrow>Voor clubs</Eyebrow>
            <h2 className="mt-2 max-w-2xl text-3xl font-semibold tracking-tight sm:text-4xl">
              Meer dan een tornooiklok
            </h2>
            <p className="mt-4 max-w-xl text-[var(--text-muted)]">
              Je eigen omgeving, met je eigen logo en kleuren, op je eigen adres.
              Nergens staat de naam van het platform.
            </p>

            <div className="mt-12 grid gap-5 md:grid-cols-3">
              <DarkCard title="Klok en floor">
                Een zaalscherm voor de beamer en een bedieningsscherm voor de
                floor die realtime gelijklopen. Geluid bij de laatste minuut en
                bij elke nieuwe blindronde, en de klok rolt vanzelf door als
                niemand doorklikt.
              </DarkCard>
              <DarkCard title="Ledenbestand">
                Wie speelde er, wat kocht hij in, waar eindigde hij. Nieuwe
                spelers voeg je aan tafel toe op naam; een account is nooit een
                voorwaarde om te spelen.
              </DarkCard>
              <DarkCard title="Klassement op maat">
                Punten volgens jouw systeem — vaste tabel, lineair of naar
                veldgrootte — met bonussen voor knock-outs en de mogelijkheid om
                enkel je beste resultaten te laten tellen.
              </DarkCard>
              <DarkCard title="Blindstructuren">
                Zelf samenstellen, of in één klik een ladder laten genereren voor
                een avond van drie tot zes uur.
              </DarkCard>
              <DarkCard title="Deals aan de finaletafel">
                ICM en chipchop naast elkaar op het zaalscherm, zodat de tafel
                het verschil ziet en zelf kiest.
              </DarkCard>
              <DarkCard title="In orde met de regels">
                Elke inzet wordt geregistreerd met tijdstip, zodat je kan
                aantonen dat niemand boven de daglimiet van het gedoogbeleid
                ging.
              </DarkCard>
            </div>
          </div>
        </section>

        {/* ------------------------------------------------------ zo starten */}
        <section className="bg-[var(--surface-2)]">
          <div className="mx-auto max-w-6xl px-5 py-16 sm:px-8 sm:py-20">
            <div className="grid gap-12 lg:grid-cols-[1fr_1.1fr] lg:items-center">
              <div>
                <Eyebrow>Zo starten we</Eyebrow>
                <h2 className="mt-2 text-3xl font-semibold tracking-tight sm:text-4xl">
                  Je eerste tornooi draait binnen een week
                </h2>
                <p className="mt-4 text-[var(--text-muted)]">
                  We zetten je omgeving op, nemen je bestaande resultaten over als
                  je die hebt, en lopen samen één avond door voor je er echt mee
                  begint.
                </p>
                <a
                  href="mailto:info@pokerleague.be?subject=Interesse%20PokerLeague"
                  className="mt-7 inline-block rounded-full bg-[var(--brand)] px-6 py-3.5 font-medium text-[var(--on-brand)] transition hover:brightness-110"
                >
                  Neem contact op
                </a>
              </div>
              <ol className="space-y-3">
                <Numbered n="01" title="Kennismaken">
                  Wat speelt je club, hoe houd je het nu bij, en wat mist er.
                </Numbered>
                <Numbered n="02" title="Opzetten">
                  Logo, kleuren, blindstructuur, puntensysteem en je ledenlijst.
                </Numbered>
                <Numbered n="03" title="Droogloop">
                  Eén avond samen doorlopen, zodat de floor het kent voor het
                  echt telt.
                </Numbered>
                <Numbered n="04" title="Spelen">
                  Vanaf dan draai je zelf, en groeit je historie vanzelf aan.
                </Numbered>
              </ol>
            </div>
          </div>
        </section>

        {/* ----------------------------------------------------------- slot */}
        <section data-band="dark" className="relative overflow-hidden bg-[var(--bg)] text-[var(--text)]">
          <div className="relative mx-auto max-w-3xl px-5 py-20 text-center sm:px-8">
            <p className="text-5xl" aria-hidden>♠</p>
            <h2 className="mt-4 text-3xl font-semibold tracking-tight sm:text-4xl">
              Interesse voor je club?
            </h2>
            <p className="mx-auto mt-4 max-w-lg text-[var(--text-muted)]">
              We starten met de eerste Belgische clubs. Laat weten wie je bent,
              dan zetten we je omgeving op.
            </p>
            <a
              href="mailto:info@pokerleague.be?subject=Interesse%20PokerLeague"
              className="mt-8 inline-block rounded-full bg-[var(--brand)] px-7 py-3.5 font-medium text-[var(--on-brand)] transition hover:brightness-110"
            >
              info@pokerleague.be
            </a>
          </div>
        </section>
      </main>

      {/* -------------------------------------------------------- footer */}
      <footer className="border-t border-[var(--line)]">
        <div className="mx-auto grid max-w-6xl gap-8 px-5 py-12 sm:grid-cols-3 sm:px-8">
          <div>
            <Wordmark />
            <p className="mt-3 max-w-xs text-sm text-[var(--text-muted)]">
              Tornooibeheer voor Belgische pokerclubs, en één plek waar spelers
              hun resultaten terugvinden.
            </p>
          </div>
          <div className="text-sm">
            <p className="font-medium">Spelers</p>
            <ul className="mt-3 space-y-2 text-[var(--text-muted)]">
              <li><Link href="/login" className="hover:text-[var(--text)]">Aanmelden</Link></li>
              <li><a href="#spelers" className="hover:text-[var(--text)]">Wat je krijgt</a></li>
            </ul>
          </div>
          <div className="text-sm">
            <p className="font-medium">Clubs</p>
            <ul className="mt-3 space-y-2 text-[var(--text-muted)]">
              <li><Link href="/clubs" className="hover:text-[var(--text)]">Clublogin</Link></li>
              <li><a href="#clubs" className="hover:text-[var(--text)]">Wat je krijgt</a></li>
              <li><a href="mailto:info@pokerleague.be" className="hover:text-[var(--text)]">info@pokerleague.be</a></li>
            </ul>
          </div>
        </div>
        <div className="border-t border-[var(--line)]">
          <p className="mx-auto max-w-6xl px-5 py-5 text-sm text-[var(--text-faint)] sm:px-8">
            PokerLeague · België
          </p>
        </div>
      </footer>
    </div>
  )
}

// ---------------------------------------------------------------------------

function Wordmark() {
  return (
    <span className="text-sm font-semibold uppercase tracking-[0.22em]">
      Poker<span className="text-[var(--brand)]">League</span>
    </span>
  )
}

function Eyebrow({ children }: { children: React.ReactNode }) {
  return (
    <p className="flex items-center gap-2 text-xs font-semibold uppercase tracking-[0.2em] text-[var(--gold)]">
      <span aria-hidden>♠</span>
      {children}
    </p>
  )
}

function Audience({
  tag, title, body, href, cta, gold,
}: {
  tag: string; title: string; body: string; href: string; cta: string; gold?: boolean
}) {
  return (
    <div
      className="flex flex-col rounded-3xl border p-7"
      style={{
        borderColor: gold ? 'var(--gold-soft)' : 'var(--line)',
        background: gold ? 'color-mix(in oklab, var(--gold-soft) 30%, white)' : 'var(--surface-2)',
      }}
    >
      <span className="text-xs font-semibold uppercase tracking-[0.2em] text-[var(--text-faint)]">
        {tag}
      </span>
      <h3 className="mt-3 text-2xl font-semibold tracking-tight">{title}</h3>
      <p className="mt-3 flex-1 text-[var(--text-muted)]">{body}</p>
      <Link
        href={href}
        className="mt-6 inline-flex items-center gap-1.5 font-medium text-[var(--brand)] hover:underline"
      >
        {cta} <span aria-hidden>→</span>
      </Link>
    </div>
  )
}

function Step({ n, title, children }: { n: number; title: string; children: React.ReactNode }) {
  return (
    <li>
      <span
        className="grid size-9 place-items-center rounded-full text-sm font-bold"
        style={{ background: 'var(--brand)', color: 'var(--on-brand)' }}
      >
        {n}
      </span>
      <h3 className="mt-4 font-semibold">{title}</h3>
      <p className="mt-2 text-sm leading-relaxed text-[var(--text-muted)]">{children}</p>
    </li>
  )
}

function Feature({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="border-t-2 border-[var(--gold-soft)] pt-4">
      <h3 className="font-semibold">{title}</h3>
      <p className="mt-2 text-sm leading-relaxed text-[var(--text-muted)]">{children}</p>
    </div>
  )
}

function DarkCard({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="rounded-2xl border border-[var(--line)] bg-[var(--surface-2)] p-6">
      <h3 className="font-semibold text-[var(--brand)]">{title}</h3>
      <p className="mt-2.5 text-sm leading-relaxed text-[var(--text-muted)]">{children}</p>
    </div>
  )
}

function Numbered({ n, title, children }: { n: string; title: string; children: React.ReactNode }) {
  return (
    <li className="flex gap-4 rounded-2xl bg-[var(--bg)] p-5">
      <span className="tnum text-sm font-bold text-[var(--gold)]">{n}</span>
      <span>
        <span className="block font-semibold">{title}</span>
        <span className="mt-1 block text-sm text-[var(--text-muted)]">{children}</span>
      </span>
    </li>
  )
}

/** Nauwelijks zichtbaar viltpatroon achter de hero. */
function Felt() {
  return (
    <div
      aria-hidden
      className="pointer-events-none absolute inset-0 opacity-[0.5]"
      style={{
        backgroundImage:
          'radial-gradient(40rem 22rem at 85% -6rem, rgba(201,143,46,0.13) 0%, transparent 70%),' +
          'radial-gradient(36rem 24rem at 5% 110%, rgba(13,82,56,0.10) 0%, transparent 70%)',
      }}
    />
  )
}
