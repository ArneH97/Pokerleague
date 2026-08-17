import Link from 'next/link'
import { createClient } from '@/lib/supabase/server'
import { ClockPreview } from '@/components/marketing/ClockPreview'
import { LanguageGate } from '@/components/LanguageGate'
import { LanguageSwitch } from '@/components/LanguageSwitch'
import { translator } from '@/lib/i18n/dictionaries'
import { publicLocale, visitorLocale } from '@/lib/i18n/server'

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
 *
 * Drietalig. Wie nog nooit koos krijgt eerst de taalkeuze te zien; daarna
 * onthoudt een koekje het en staat er in de kop een schakelaar.
 */

export async function generateMetadata() {
  const t = translator(await publicLocale())
  return { title: t('site.meta.title'), description: t('site.meta.description') }
}

export default async function Page() {
  const supabase = await createClient()
  const { data: claims } = await supabase.auth.getClaims()
  const loggedIn = Boolean(claims?.claims)

  const chosen = await visitorLocale()
  const locale = chosen ?? 'nl'
  const t = translator(locale)

  return (
    <div data-site lang={locale} className="min-h-dvh bg-[var(--bg)] text-[var(--text)]">
      {/* ----------------------------------------------------------- nav */}
      <header className="sticky top-0 z-30 border-b border-[var(--line)] bg-[color-mix(in_oklab,var(--bg)_88%,transparent)] backdrop-blur">
        <div className="mx-auto flex max-w-6xl items-center justify-between gap-3 px-5 py-3.5 sm:px-8">
          <Wordmark />
          <nav className="flex items-center gap-1 text-sm">
            <a href="#spelers" className="hidden rounded-full px-3.5 py-2 text-[var(--text-muted)] transition hover:bg-[var(--surface-hover)] hover:text-[var(--text)] sm:block">
              {t('site.nav.players')}
            </a>
            <a href="#clubs" className="hidden rounded-full px-3.5 py-2 text-[var(--text-muted)] transition hover:bg-[var(--surface-hover)] hover:text-[var(--text)] sm:block">
              {t('site.nav.clubs')}
            </a>
            {loggedIn ? (
              <>
                <Link href="/clubs" className="rounded-full px-3.5 py-2 text-[var(--text-muted)] transition hover:bg-[var(--surface-hover)] hover:text-[var(--text)]">
                  {t('site.nav.myClub')}
                </Link>
                <form action="/auth/signout" method="post">
                  <button className="rounded-full px-3.5 py-2 text-[var(--text-muted)] transition hover:bg-[var(--surface-hover)] hover:text-[var(--text)]">
                    {t('common.signOut')}
                  </button>
                </form>
              </>
            ) : (
              <>
                <Link href="/login" className="rounded-full px-3.5 py-2 text-[var(--text-muted)] transition hover:bg-[var(--surface-hover)] hover:text-[var(--text)]">
                  {t('site.nav.playerLogin')}
                </Link>
                <Link
                  href="/clubs"
                  className="rounded-full bg-[var(--brand)] px-4 py-2 font-medium text-[var(--on-brand)] transition hover:brightness-110"
                >
                  {t('site.nav.clubLogin')}
                </Link>
              </>
            )}
            <span className="ml-1 hidden sm:block">
              <LanguageSwitch current={locale} label={t('common.language')} />
            </span>
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
                {t('site.hero.badge')}
              </p>
              <h1 className="text-balance text-4xl font-semibold leading-[1.05] tracking-tight sm:text-6xl">
                {t('site.hero.titleA')}{' '}
                <span className="relative whitespace-nowrap text-[var(--brand)]">
                  {t('site.hero.titleHighlight')}
                  <span
                    aria-hidden
                    className="absolute inset-x-0 -bottom-1 h-2 rounded-full"
                    style={{ background: 'var(--gold-soft)' }}
                  />
                </span>
                .
              </h1>
              <p className="mt-6 max-w-lg text-pretty text-lg leading-relaxed text-[var(--text-muted)]">
                {t('site.hero.body')}
              </p>
              <div className="mt-8 flex flex-wrap items-center gap-3">
                <Link
                  href="/login"
                  className="rounded-full bg-[var(--brand)] px-6 py-3.5 font-medium text-[var(--on-brand)] transition hover:brightness-110"
                >
                  {t('site.hero.ctaPlayer')}
                </Link>
                <a
                  href="#clubs"
                  className="rounded-full border border-[var(--line-strong)] bg-[var(--bg)] px-6 py-3.5 font-medium transition hover:bg-[var(--surface-hover)]"
                >
                  {t('site.hero.ctaClub')}
                </a>
              </div>
              <p className="mt-4 text-sm text-[var(--text-faint)]">{t('site.hero.note')}</p>
            </div>

            <ClockPreview />
          </div>
        </section>

        {/* ----------------------------------------------------- voor wie */}
        <section className="mx-auto max-w-6xl px-5 py-16 sm:px-8 sm:py-20">
          <Eyebrow>{t('site.who.eyebrow')}</Eyebrow>
          <h2 className="mt-2 max-w-2xl text-3xl font-semibold tracking-tight sm:text-4xl">
            {t('site.who.title')}
          </h2>
          <div className="mt-10 grid gap-5 md:grid-cols-2">
            <Audience
              tag={t('site.who.playersTag')}
              title={t('site.who.playersTitle')}
              body={t('site.who.playersBody')}
              href="/login"
              cta={t('site.hero.ctaPlayer')}
            />
            <Audience
              tag={t('site.who.clubsTag')}
              title={t('site.who.clubsTitle')}
              body={t('site.who.clubsBody')}
              href="#clubs"
              cta={t('site.who.clubsCta')}
              gold
            />
          </div>
        </section>

        {/* --------------------------------------------------- hoe het werkt */}
        <section data-band="dark" className="bg-[var(--bg)] text-[var(--text)]">
          <div className="mx-auto max-w-6xl px-5 py-16 sm:px-8 sm:py-20">
            <Eyebrow>{t('site.how.eyebrow')}</Eyebrow>
            <h2 className="mt-2 max-w-2xl text-3xl font-semibold tracking-tight sm:text-4xl">
              {t('site.how.title')}
            </h2>
            <ol className="mt-12 grid gap-8 sm:grid-cols-2 lg:grid-cols-4">
              <Step n={1} title={t('site.how.s1t')}>{t('site.how.s1b')}</Step>
              <Step n={2} title={t('site.how.s2t')}>{t('site.how.s2b')}</Step>
              <Step n={3} title={t('site.how.s3t')}>{t('site.how.s3b')}</Step>
              <Step n={4} title={t('site.how.s4t')}>{t('site.how.s4b')}</Step>
            </ol>
          </div>
        </section>

        {/* ------------------------------------------------------- spelers */}
        <section id="spelers" className="mx-auto max-w-6xl px-5 py-16 sm:px-8 sm:py-24">
          <Eyebrow>{t('site.players.eyebrow')}</Eyebrow>
          <h2 className="mt-2 max-w-2xl text-3xl font-semibold tracking-tight sm:text-4xl">
            {t('site.players.title')}
          </h2>
          <div className="mt-10 grid gap-x-10 gap-y-10 sm:grid-cols-3">
            <Feature title={t('site.players.f1t')}>{t('site.players.f1b')}</Feature>
            <Feature title={t('site.players.f2t')}>{t('site.players.f2b')}</Feature>
            <Feature title={t('site.players.f3t')}>{t('site.players.f3b')}</Feature>
            <Feature title={t('site.players.f4t')}>{t('site.players.f4b')}</Feature>
            <Feature title={t('site.players.f5t')}>{t('site.players.f5b')}</Feature>
            <Feature title={t('site.players.f6t')}>{t('site.players.f6b')}</Feature>
          </div>
        </section>

        {/* --------------------------------------------------------- clubs */}
        <section id="clubs" data-band="dark" className="bg-[var(--bg)] text-[var(--text)]">
          <div className="mx-auto max-w-6xl px-5 py-16 sm:px-8 sm:py-24">
            <Eyebrow>{t('site.clubs.eyebrow')}</Eyebrow>
            <h2 className="mt-2 max-w-2xl text-3xl font-semibold tracking-tight sm:text-4xl">
              {t('site.clubs.title')}
            </h2>
            <p className="mt-4 max-w-xl text-[var(--text-muted)]">{t('site.clubs.body')}</p>

            <div className="mt-12 grid gap-5 md:grid-cols-3">
              <DarkCard title={t('site.clubs.c1t')}>{t('site.clubs.c1b')}</DarkCard>
              <DarkCard title={t('site.clubs.c2t')}>{t('site.clubs.c2b')}</DarkCard>
              <DarkCard title={t('site.clubs.c3t')}>{t('site.clubs.c3b')}</DarkCard>
              <DarkCard title={t('site.clubs.c4t')}>{t('site.clubs.c4b')}</DarkCard>
              <DarkCard title={t('site.clubs.c5t')}>{t('site.clubs.c5b')}</DarkCard>
              <DarkCard title={t('site.clubs.c6t')}>{t('site.clubs.c6b')}</DarkCard>
            </div>
          </div>
        </section>

        {/* ------------------------------------------------------ zo starten */}
        <section className="bg-[var(--surface-2)]">
          <div className="mx-auto max-w-6xl px-5 py-16 sm:px-8 sm:py-20">
            <div className="grid gap-12 lg:grid-cols-[1fr_1.1fr] lg:items-center">
              <div>
                <Eyebrow>{t('site.start.eyebrow')}</Eyebrow>
                <h2 className="mt-2 text-3xl font-semibold tracking-tight sm:text-4xl">
                  {t('site.start.title')}
                </h2>
                <p className="mt-4 text-[var(--text-muted)]">{t('site.start.body')}</p>
                <a
                  href="mailto:arne@halcoservices.be?subject=Interesse%20PokerLeague"
                  className="mt-7 inline-block rounded-full bg-[var(--brand)] px-6 py-3.5 font-medium text-[var(--on-brand)] transition hover:brightness-110"
                >
                  {t('site.start.cta')}
                </a>
              </div>
              <ol className="space-y-3">
                <Numbered n="01" title={t('site.start.n1t')}>{t('site.start.n1b')}</Numbered>
                <Numbered n="02" title={t('site.start.n2t')}>{t('site.start.n2b')}</Numbered>
                <Numbered n="03" title={t('site.start.n3t')}>{t('site.start.n3b')}</Numbered>
                <Numbered n="04" title={t('site.start.n4t')}>{t('site.start.n4b')}</Numbered>
              </ol>
            </div>
          </div>
        </section>

        {/* ----------------------------------------------------------- slot */}
        <section data-band="dark" className="relative overflow-hidden bg-[var(--bg)] text-[var(--text)]">
          <div className="relative mx-auto max-w-3xl px-5 py-20 text-center sm:px-8">
            <p className="text-5xl" aria-hidden>♠</p>
            <h2 className="mt-4 text-3xl font-semibold tracking-tight sm:text-4xl">
              {t('site.cta.title')}
            </h2>
            <p className="mx-auto mt-4 max-w-lg text-[var(--text-muted)]">{t('site.cta.body')}</p>
            <a
              href="mailto:arne@halcoservices.be?subject=Interesse%20PokerLeague"
              className="mt-8 inline-block rounded-full bg-[var(--brand)] px-7 py-3.5 font-medium text-[var(--on-brand)] transition hover:brightness-110"
            >
              arne@halcoservices.be
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
              {t('site.footer.about')}
            </p>
            {/* Ook onderaan, want op een telefoon staat de schakelaar in de
                kop niet altijd binnen bereik. */}
            <div className="mt-5 w-fit">
              <LanguageSwitch current={locale} label={t('common.language')} />
            </div>
          </div>
          <div className="text-sm">
            <p className="font-medium">{t('site.who.playersTag')}</p>
            <ul className="mt-3 space-y-2 text-[var(--text-muted)]">
              <li><Link href="/login" className="hover:text-[var(--text)]">{t('common.signIn')}</Link></li>
              <li><a href="#spelers" className="hover:text-[var(--text)]">{t('site.footer.whatYouGet')}</a></li>
            </ul>
          </div>
          <div className="text-sm">
            <p className="font-medium">{t('site.who.clubsTag')}</p>
            <ul className="mt-3 space-y-2 text-[var(--text-muted)]">
              <li><Link href="/clubs" className="hover:text-[var(--text)]">{t('site.nav.clubLogin')}</Link></li>
              <li><a href="#clubs" className="hover:text-[var(--text)]">{t('site.footer.whatYouGet')}</a></li>
              <li><a href="mailto:arne@halcoservices.be" className="hover:text-[var(--text)]">arne@halcoservices.be</a></li>
            </ul>
          </div>
        </div>
        <div className="border-t border-[var(--line)]">
          <p className="mx-auto max-w-6xl px-5 py-5 text-sm text-[var(--text-faint)] sm:px-8">
            {t('site.footer.tagline')}
          </p>
        </div>
      </footer>

      {/* De taalkeuze ligt over de pagina heen, niet ervoor in de plaats: wie
          hem wegscrollt heeft de pagina er al achter staan in het Nederlands,
          en wie kiest krijgt hem meteen in zijn eigen taal terug. */}
      {chosen === null && <LanguageGate />}
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
