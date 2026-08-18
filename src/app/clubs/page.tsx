import Link from 'next/link'
import { LanguageSwitch } from '@/components/LanguageSwitch'
import { translator } from '@/lib/i18n/dictionaries'
import { publicLocale } from '@/lib/i18n/server'
import { createClient } from '@/lib/supabase/server'

/**
 * De clubgids.
 *
 * Dit was een personeelsscherm — "Aanmelden als club", met een knop naar de
 * beheeromgeving. Dat is de verkeerde voordeur: wie op een spelersplatform op
 * "Clubs" klikt, zoekt een club om bij te spelen, geen inlogpagina voor
 * medewerkers, en die hoort hier helemaal niet meer thuis.
 *
 * Elke kaart wijst naar de clubpagina op het platform en niet naar het
 * werkdomein van de club. Ook dat is met opzet: app.cutoff.be is sinds de
 * scheiding gereedschap voor de floor, en daar heeft een bezoeker niets te
 * zoeken. Om dezelfde reden staat er nergens nog een link naar het
 * clubbeheer — een club krijgt zijn adres van ons, niet via een knop hier.
 *
 * Dezelfde banden en dezelfde twee kleuren als de landingspagina: dit is nog
 * altijd PokerLeague, geen los inlogschermpje. Met één club in de lijst is
 * een kale pagina met één kaartje er verloren uitzien; vandaar een kop met
 * inhoud erboven en een uitnodiging eronder, zodat de pagina ook klopt
 * zolang er nog maar een paar clubs zijn.
 *
 * Volgt de taal die de bezoeker koos. Vanaf de klik neemt de taal van de
 * club het over.
 */

export async function generateMetadata() {
  return { title: translator(await publicLocale())('site.pick.metaTitle') }
}

interface Row {
  slug: string
  name: string
  city: string | null
  intro: string | null
  logo_url: string | null
  play_rhythm: string | null
  open_signup: boolean
  members: number
}

export default async function Page() {
  const locale = await publicLocale()
  const t = translator(locale)

  const supabase = await createClient()
  const { data } = await supabase.rpc('club_cards')
  const clubs = (data ?? []) as unknown as Row[]

  const { data: claims } = await supabase.auth.getClaims()
  const signedIn = Boolean(claims?.claims)

  return (
    <div data-site lang={locale} className="flex min-h-dvh flex-col bg-[var(--bg)] text-[var(--text)]">
      {/* ------------------------------------------------------------- nav */}
      <header className="border-b border-[var(--line)]">
        <div className="mx-auto flex max-w-5xl items-center justify-between gap-3 px-5 py-3.5 sm:px-8">
          <Link href="/" className="text-sm font-semibold uppercase tracking-[0.22em]">
            Poker<span className="text-[var(--brand)]">League</span>
          </Link>
          <div className="flex items-center gap-2">
            <LanguageSwitch current={locale} label={t('common.language')} />
            <Link
              href="/login"
              className="rounded-full px-3.5 py-2 text-sm text-[var(--text-muted)] transition hover:bg-[var(--surface-hover)] hover:text-[var(--text)]"
            >
              {t('site.nav.playerLogin')}
            </Link>
          </div>
        </div>
      </header>

      <main className="flex-1">
        {/* ------------------------------------------------------------ kop */}
        <section className="relative overflow-hidden border-b border-[var(--line)] bg-[var(--surface-2)]">
          <Felt />
          <div className="relative mx-auto max-w-5xl px-5 py-14 sm:px-8 sm:py-20">
            <p className="flex items-center gap-2 text-xs font-semibold uppercase tracking-[0.2em] text-[var(--gold)]">
              <span aria-hidden>♠</span>
              {t('site.clubs.eyebrow')}
            </p>
            <h1 className="mt-3 text-balance text-4xl font-semibold leading-[1.05] tracking-tight sm:text-5xl">
              {t('site.pick.title')}
            </h1>
            <p className="mt-4 max-w-xl text-pretty text-lg leading-relaxed text-[var(--text-muted)]">
              {t('site.pick.body')}
            </p>
          </div>
        </section>

        {/* ---------------------------------------------------------- lijst */}
        <section className="mx-auto max-w-5xl px-5 py-12 sm:px-8 sm:py-16">
          {clubs.length === 0 ? (
            <div className="rounded-[1.5rem] border border-dashed border-[var(--line-strong)] p-10 text-center">
              <p className="text-5xl" aria-hidden>♠</p>
              <p className="mt-4 text-lg font-medium">{t('site.pick.none')}</p>
              <p className="mx-auto mt-2 max-w-sm text-sm text-[var(--text-muted)]">
                {t('site.pick.beFirst')}
              </p>
              <a
                href="mailto:arne@halcoservices.be?subject=Interesse%20PokerLeague"
                className="mt-6 inline-block rounded-full bg-[var(--brand)] px-6 py-3 font-medium text-[var(--on-brand)] transition hover:brightness-110"
              >
                arne@halcoservices.be
              </a>
            </div>
          ) : (
            <ul className="grid gap-4 sm:grid-cols-2">
              {clubs.map((c) => (
                <li key={c.slug}>
                  <Link
                    href={`/c/${c.slug}`}
                    className="group flex h-full flex-col rounded-[1.5rem] border border-[var(--line)] bg-[var(--surface-2)] p-6 transition hover:-translate-y-0.5 hover:border-[var(--gold-soft)] hover:shadow-lg"
                  >
                    <div className="flex items-center gap-4">
                      {/* Het logo van een club draagt meestal zijn eigen
                          achtergrond mee; een vierkant met een rand eromheen
                          laat dat er eerder als een kaart uitzien dan als een
                          plakker op de pagina. */}
                      <span className="flex size-16 shrink-0 items-center justify-center overflow-hidden rounded-2xl border border-[var(--line)] bg-[var(--bg)]">
                        {c.logo_url ? (
                          // eslint-disable-next-line @next/next/no-img-element
                          <img src={c.logo_url} alt="" className="size-full object-contain" />
                        ) : (
                          <span className="text-2xl font-semibold text-[var(--gold)]">
                            {c.name.slice(0, 1)}
                          </span>
                        )}
                      </span>
                      <span className="min-w-0 flex-1">
                        <span className="block truncate text-xl font-semibold tracking-tight">
                          {c.name}
                        </span>
                        {c.city && (
                          <span className="mt-0.5 block truncate text-sm text-[var(--text-muted)]">
                            {c.city}
                          </span>
                        )}
                      </span>
                    </div>

                    {c.intro && (
                      <p className="mt-4 line-clamp-2 text-sm leading-relaxed text-[var(--text-muted)]">
                        {c.intro}
                      </p>
                    )}

                    <div className="mt-4 flex flex-wrap items-center gap-2">
                      {c.play_rhythm && (
                        <span className="rounded-full border border-[var(--line)] bg-[var(--bg)] px-3 py-1 text-xs text-[var(--text-muted)]">
                          {c.play_rhythm}
                        </span>
                      )}
                      <span className="rounded-full border border-[var(--line)] bg-[var(--bg)] px-3 py-1 text-xs text-[var(--text-muted)]">
                        {c.members} {t('join.members')}
                      </span>
                    </div>

                    <span className="mt-5 inline-flex items-center gap-1.5 font-medium text-[var(--brand)]">
                      {t('site.pick.enter')}
                      <span aria-hidden className="transition-transform group-hover:translate-x-0.5">→</span>
                    </span>
                  </Link>

                  {c.open_signup && (
                    <Link
                      href={signedIn ? `/aansluiten/${c.slug}` : `/registreren?club=${c.slug}`}
                      className="mt-2 block rounded-full border border-[var(--line-strong)] px-4 py-2.5 text-center text-sm font-medium transition hover:bg-[var(--surface-hover)]"
                    >
                      {t('join.cta').replace('{club}', c.name)}
                    </Link>
                  )}
                </li>
              ))}

              {/* Even breed als een club, zodat de rij niet halfleeg oogt
                  zolang er nog maar een paar clubs zijn. */}
              <li>
                <div className="flex h-full flex-col justify-center rounded-[1.5rem] border border-dashed border-[var(--line-strong)] p-6">
                  <p className="text-lg font-semibold tracking-tight">{t('site.pick.joinTitle')}</p>
                  <p className="mt-2 text-sm leading-relaxed text-[var(--text-muted)]">
                    {t('site.cta.body')}
                  </p>
                  <a
                    href="mailto:arne@halcoservices.be?subject=Interesse%20PokerLeague"
                    className="mt-4 inline-flex w-fit items-center gap-1.5 font-medium text-[var(--gold)] hover:underline"
                  >
                    arne@halcoservices.be <span aria-hidden>→</span>
                  </a>
                </div>
              </li>
            </ul>
          )}
        </section>
      </main>

      <footer className="border-t border-[var(--line)]">
        <div className="mx-auto flex max-w-5xl flex-wrap items-center justify-between gap-3 px-5 py-6 text-sm sm:px-8">
          <Link href="/" className="text-[var(--text-faint)] transition-colors hover:text-[var(--text)]">
            ← {t('site.pick.backHome')}
          </Link>
          {/* Geen deur naar het clubbeheer meer. Een club komt hier niet
              binnen: die heeft zijn eigen adres en zijn eigen aanmeldscherm.
              Een knop ernaar toe op het spelersplatform leidde alleen maar
              spelers naar een scherm waar ze niets te zoeken hadden. */}
          <p className="text-[var(--text-faint)]">{t('home.forClubs')}</p>
        </div>
      </footer>
    </div>
  )
}

/** Hetzelfde nauwelijks zichtbare viltpatroon als op de landingspagina. */
function Felt() {
  return (
    <div
      aria-hidden
      className="pointer-events-none absolute inset-0 opacity-[0.5]"
      style={{
        backgroundImage:
          'radial-gradient(40rem 22rem at 88% -8rem, rgba(201,143,46,0.13) 0%, transparent 70%),' +
          'radial-gradient(36rem 24rem at 0% 115%, rgba(13,82,56,0.12) 0%, transparent 70%)',
      }}
    />
  )
}
