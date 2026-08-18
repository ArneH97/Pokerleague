import Link from 'next/link'
import { redirect } from 'next/navigation'
import { LanguageSwitch } from '@/components/LanguageSwitch'
import { LoginForm } from '@/components/LoginForm'
import { LocaleProvider } from '@/lib/i18n/context'
import { translator, type T } from '@/lib/i18n/dictionaries'
import { publicLocale } from '@/lib/i18n/server'
import { createClient } from '@/lib/supabase/server'

/**
 * De voorpagina van het platform.
 *
 * Dit was eerst een verkooppagina met banden voor spelers én clubs, en daarna
 * een kaal aanmeldformulier. Allebei mis, om verschillende redenen.
 *
 * De verkooppagina praatte tegen twee publieken tegelijk, waarvan er één —
 * de clubs — hier helemaal niet binnenkomt. Het formulier loste dat op maar
 * ging te ver: het toonde wél een invoerveld en níét waar je een account voor
 * zou willen. Wie hier voor het eerst komt heeft nog geen wachtwoord; die
 * heeft een reden nodig.
 *
 * Drie secties dus, en niet meer. Wat het is, wat je krijgt, en dan pas het
 * formulier. Met daartussen één beeld van het product zelf: de klok van een
 * lopend tornooi. Dat kaartje doet meer dan drie alinea's tekst, want het is
 * het enige op deze pagina dat laat zien waar het over gaat.
 *
 * **Mobiel eerst, en hier is dat geen slogan.** De meeste pokerspelers openen
 * dit op hun telefoon, vaak in de zaal. Alles staat dus in één kolom met knoppen
 * over de volle breedte, en pas vanaf een breed scherm schuift het naast
 * elkaar. Het aanmeldformulier staat op mobiel onderaan en niet bovenaan: wie
 * al een account heeft, tikt op "Aanmelden" in de kop.
 */

export async function generateMetadata() {
  return { title: translator(await publicLocale())('home.metaTitle') }
}

export default async function Page() {
  const supabase = await createClient()
  const { data: claims } = await supabase.auth.getClaims()
  if (claims?.claims) redirect('/ik')

  const locale = await publicLocale()
  const t = translator(locale)

  return (
    <LocaleProvider locale={locale}>
      <div data-site lang={locale} className="min-h-dvh bg-[var(--bg)] text-[var(--text)]">
        {/* ------------------------------------------------------------ kop */}
        <header className="border-b border-[var(--line)]">
          <div className="mx-auto flex max-w-6xl items-center gap-2 px-5 py-3.5 sm:gap-3 sm:px-8">
            <span className="text-sm font-semibold uppercase tracking-[0.2em]">
              Poker<span className="text-[var(--brand)]">League</span>
            </span>
            <span className="flex-1" />
            {/* Geen "Clubs" in de navigatie. Er valt voor wie niet aangemeld
                is niets te bladeren: de agenda en het klassement van een club
                vragen een account. Wat hij wél mag weten is welke clubs
                meedoen, en dat staat als strook onderaan de eerste sectie —
                als informatie, niet als een deur die op een muur uitkomt. */}
            <a
              href="#aanmelden"
              className="rounded-full px-3 py-2 text-sm text-[var(--text-muted)] transition hover:bg-[var(--surface-hover)] hover:text-[var(--text)]"
            >
              {t('common.signIn')}
            </a>
            <LanguageSwitch current={locale} label={t('common.language')} />
          </div>
        </header>

        {/* ----------------------------------------------------------- hero */}
        <section className="relative overflow-hidden">
          <Glow />
          <div className="relative mx-auto grid max-w-6xl gap-10 px-5 py-12 sm:px-8 sm:py-16 lg:grid-cols-[1.05fr_.95fr] lg:items-center lg:gap-14 lg:py-24">
            <div>
              <p className="text-[0.7rem] font-semibold uppercase tracking-[0.2em] text-[var(--gold)]">
                ◆ {t('site.nav.players')}
              </p>
              <h1 className="mt-3 text-balance text-[2.1rem] font-semibold leading-[1.06] tracking-tight sm:text-5xl lg:text-[3.4rem]">
                {t('home.titleA')}{' '}
                <span className="text-[var(--brand)]">{t('home.titleB')}</span>.
              </h1>
              <p className="mt-5 max-w-lg text-pretty text-base leading-relaxed text-[var(--text-muted)] sm:text-lg">
                {t('home.lede')}
              </p>

              <div className="mt-8 flex flex-col gap-3 sm:flex-row sm:items-center">
                <Link
                  href="/registreren"
                  className="rounded-full bg-[var(--brand)] px-6 py-3.5 text-center font-medium text-[var(--on-brand)] transition hover:brightness-110"
                >
                  {t('home.ctaMake')} →
                </Link>
                <a
                  href="#aanmelden"
                  className="rounded-full border border-[var(--line-strong)] px-6 py-3.5 text-center font-medium transition hover:bg-[var(--surface-hover)]"
                >
                  {t('home.ctaHave')}
                </a>
              </div>
              <p className="mt-4 text-sm text-[var(--text-faint)]">{t('home.free')}</p>
            </div>

            <ClockCard t={t} />
          </div>

          <div className="relative mx-auto max-w-6xl px-5 pb-12 sm:px-8 sm:pb-16">
            <Clubs t={t} />
          </div>
        </section>

        {/* -------------------------------------------------------- wat krijg je */}
        <section className="border-t border-[var(--line)] bg-[var(--surface-2)]">
          <div className="mx-auto max-w-6xl px-5 py-14 sm:px-8 sm:py-20">
            <p className="text-[0.7rem] font-semibold uppercase tracking-[0.2em] text-[var(--gold)]">
              {t('home.getEyebrow')}
            </p>
            <h2 className="mt-3 max-w-[16em] text-balance text-2xl font-semibold leading-tight tracking-tight sm:text-4xl">
              {t('home.getTitle')}
            </h2>

            <div className="mt-8 grid gap-4 sm:mt-11 sm:grid-cols-3">
              <Card figure="37" title={t('home.p1')} body={t('home.p1b')} />
              <Card
                figure={<>2<span className="align-super text-base">e</span> <span className="text-[var(--text-faint)]">/ 47</span></>}
                title={t('home.p2')}
                body={t('home.p2b')}
              />
              <Card figure={t('home.liveWord')} title={t('home.p3')} body={t('home.p3b')} />
            </div>
          </div>
        </section>

        {/* ------------------------------------------------------- aanmelden */}
        <section id="aanmelden" className="scroll-mt-4 border-t border-[var(--line)]">
          <div className="mx-auto max-w-6xl px-5 py-14 sm:px-8 sm:py-20">
            <div className="grid gap-8 rounded-3xl border border-[var(--line)] bg-[var(--surface-2)] p-6 sm:p-10 lg:grid-cols-[1fr_22rem] lg:items-center lg:gap-14">
              <div>
                <h2 className="text-balance text-2xl font-semibold leading-tight tracking-tight sm:text-3xl">
                  {t('home.joinTitle')}
                </h2>
                <p className="mt-3 max-w-md text-pretty leading-relaxed text-[var(--text-muted)]">
                  {t('home.newHereBody')}
                </p>
                <Link
                  href="/registreren"
                  className="mt-6 inline-block rounded-full bg-[var(--brand)] px-6 py-3.5 font-medium text-[var(--on-brand)] transition hover:brightness-110"
                >
                  {t('site.nav.createAccount')}
                </Link>
              </div>

              <div className="rounded-2xl border border-[var(--line)] bg-[var(--bg)] p-5 sm:p-6">
                <h3 className="mb-4 text-sm font-semibold uppercase tracking-[0.16em] text-[var(--text-faint)]">
                  {t('common.signIn')}
                </h3>
                <LoginForm brandName="PokerLeague" fallbackNext="/ik" bare />
              </div>
            </div>
          </div>
        </section>

        <footer className="border-t border-[var(--line)]">
          <div className="mx-auto flex max-w-6xl flex-wrap items-center justify-between gap-3 px-5 py-6 text-xs text-[var(--text-faint)] sm:px-8">
            <span>{t('home.clubsStrip')}</span>
            <span>{t('home.forClubs')}</span>
          </div>
        </footer>
      </div>
    </LocaleProvider>
  )
}

/**
 * Welke clubs meedoen.
 *
 * Geen links. Achter een clubpagina zit de agenda en het klassement, en die
 * vragen een account — een naam die je kan aanklikken en die dan op een muur
 * uitkomt, is erger dan een naam die gewoon een naam is. Wat hier staat is het
 * antwoord op één vraag: speelt mijn club hier mee?
 */
async function Clubs({ t }: { t: T }) {
  const supabase = await createClient()
  const { data } = await supabase.rpc('club_cards')
  const clubs = (data ?? []) as unknown as { slug: string; name: string; city: string | null }[]
  if (clubs.length === 0) return null

  return (
    <div className="flex flex-wrap items-center gap-x-3 gap-y-2 border-t border-[var(--line)] pt-6">
      <span className="text-[0.7rem] font-semibold uppercase tracking-[0.16em] text-[var(--text-faint)]">
        {t('home.clubsStrip')}
      </span>
      {clubs.map((c) => (
        <span
          key={c.slug}
          className="rounded-full border border-[var(--line)] bg-[var(--surface-2)] px-3.5 py-1.5 text-sm"
        >
          {c.name}
          {c.city && <span className="text-[var(--text-faint)]"> · {c.city}</span>}
        </span>
      ))}
    </div>
  )
}

/**
 * Het enige beeld op deze pagina, en het draagt de hele hero.
 *
 * Geen schermafdruk maar het echte ding nagebouwd: een schermafdruk verouderd
 * bij de eerste wijziging en schaalt niet naar een telefoon. Dit wel.
 */
function ClockCard({ t }: { t: T }) {
  return (
    <div
      data-band="dark"
      className="rounded-3xl bg-[var(--bg)] p-5 text-[var(--text)] shadow-[0_24px_60px_-24px_rgba(14,23,41,.5)] sm:p-7"
    >
      <div className="flex items-baseline justify-between text-[0.65rem] uppercase tracking-[0.16em] text-[var(--text-faint)]">
        <span>Cutoff Cardroom</span>
        <span>Level 7 / 20</span>
      </div>

      <p className="tnum mt-3 text-center text-6xl font-semibold leading-none tracking-tight sm:text-7xl">
        12:47
      </p>

      <div className="mt-4 flex justify-center gap-8 text-center">
        <span>
          <span className="block text-[0.6rem] uppercase tracking-[0.14em] text-[var(--text-faint)]">
            {t('clock.smallBlind')}
          </span>
          <span className="tnum block text-xl font-semibold">300</span>
        </span>
        <span>
          <span className="block text-[0.6rem] uppercase tracking-[0.14em] text-[var(--text-faint)]">
            {t('clock.bigBlind')}
          </span>
          <span className="tnum block text-xl font-semibold text-[var(--brand)]">600</span>
        </span>
        <span>
          <span className="block text-[0.6rem] uppercase tracking-[0.14em] text-[var(--text-faint)]">
            Ante
          </span>
          <span className="tnum block text-xl font-semibold">600</span>
        </span>
      </div>

      <div className="mt-5 grid grid-cols-3 gap-2">
        <Cell label={t('clock.playersLeft')} value="14" />
        <Cell label={t('home.avgStack')} value="38.500" />
        <Cell label={t('clock.prizePool')} value="€ 540" />
      </div>
    </div>
  )
}

function Cell({ label, value }: { label: string; value: string }) {
  return (
    <span className="block rounded-xl bg-[var(--surface-2)] px-2 py-2.5 text-center">
      <span className="block text-[0.55rem] uppercase tracking-[0.12em] text-[var(--text-faint)]">
        {label}
      </span>
      <span className="tnum mt-0.5 block text-base font-semibold sm:text-lg">{value}</span>
    </span>
  )
}

function Card({
  figure, title, body,
}: { figure: React.ReactNode; title: string; body: string }) {
  return (
    <div className="rounded-2xl border border-[var(--line)] bg-[var(--bg)] p-6">
      <p className="tnum text-3xl font-semibold tracking-tight text-[var(--brand)] sm:text-4xl">
        {figure}
      </p>
      <h3 className="mt-4 font-semibold">{title}</h3>
      <p className="mt-2 text-sm leading-relaxed text-[var(--text-muted)]">{body}</p>
    </div>
  )
}

/** Nauwelijks zichtbaar: amber rechtsboven, blauw linksonder. Geeft de witte pagina diepte. */
function Glow() {
  return (
    <div
      aria-hidden
      className="pointer-events-none absolute inset-0"
      style={{
        backgroundImage:
          'radial-gradient(38rem 20rem at 92% -6rem, rgba(245,158,11,0.16) 0%, transparent 70%),' +
          'radial-gradient(34rem 22rem at -4% 110%, rgba(29,78,216,0.10) 0%, transparent 70%)',
      }}
    />
  )
}
