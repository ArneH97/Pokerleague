import Link from 'next/link'
import { redirect } from 'next/navigation'
import { LanguageSwitch } from '@/components/LanguageSwitch'
import { LoginForm } from '@/components/LoginForm'
import { LocaleProvider } from '@/lib/i18n/context'
import { translator } from '@/lib/i18n/dictionaries'
import { publicLocale } from '@/lib/i18n/server'
import { createClient } from '@/lib/supabase/server'

/**
 * De voorpagina van het platform.
 *
 * Dit was een verkooppagina: een hero, banden met uitleg voor spelers, banden
 * met uitleg voor clubs, een prijsblok. Mooi, en voor niemand het juiste
 * scherm. Wie hier komt is namelijk bijna altijd één van twee mensen — een
 * speler die zijn resultaten wil zien, of een speler die net een uitnodiging
 * kreeg. Allebei hebben ze hetzelfde nodig en dat is een aanmeldveld.
 *
 * En voor clubs stond er helemaal te veel. Een club komt hier niet binnen: die
 * krijgt zijn eigen adres en zijn eigen aanmeldscherm. Uitleg voor clubs op
 * het spelersplatform is uitleg op de verkeerde plek, en ze leidde spelers
 * bovendien naar knoppen waar ze niets te zoeken hadden.
 *
 * Dus: links waarom je hier een account zou willen, rechts het formulier. Wie
 * al aangemeld is hoeft dit scherm nooit te zien en gaat rechtstreeks door.
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

  const points = [
    { k: 'home.p1', b: 'home.p1b' },
    { k: 'home.p2', b: 'home.p2b' },
    { k: 'home.p3', b: 'home.p3b' },
  ] as const

  return (
    <LocaleProvider locale={locale}>
      <div data-site lang={locale} className="min-h-dvh bg-[var(--bg)] text-[var(--text)]">
        <header className="border-b border-[var(--line)]">
          <div className="mx-auto flex max-w-6xl items-center gap-3 px-5 py-4 sm:px-8">
            <span className="text-sm font-semibold uppercase tracking-[0.22em]">
              Poker<span className="text-[var(--brand)]">League</span>
            </span>
            <span className="flex-1" />
            <Link
              href="/clubs"
              className="rounded-full px-3.5 py-2 text-sm text-[var(--text-muted)] transition hover:bg-[var(--surface-hover)] hover:text-[var(--text)]"
            >
              {t('site.nav.clubsDir')}
            </Link>
            <LanguageSwitch current={locale} label={t('common.language')} />
          </div>
        </header>

        <main className="mx-auto grid max-w-6xl gap-10 px-5 py-12 sm:px-8 sm:py-16 lg:grid-cols-[1.1fr_auto] lg:gap-16 lg:py-24">
          {/* ------------------------------------------------------- waarom */}
          <section className="max-w-xl">
            <h1 className="text-balance text-4xl font-semibold leading-[1.08] tracking-tight sm:text-5xl">
              {t('home.titleA')}{' '}
              <span className="text-[var(--brand)]">{t('home.titleB')}</span>.
            </h1>
            <p className="mt-5 text-pretty text-lg leading-relaxed text-[var(--text-muted)]">
              {t('home.lede')}
            </p>

            <ul className="mt-9 space-y-6">
              {points.map((p) => (
                <li key={p.k} className="flex gap-4">
                  <span
                    aria-hidden
                    className="mt-1.5 size-1.5 shrink-0 rounded-full bg-[var(--brand)]"
                  />
                  <span>
                    <span className="block font-medium">{t(p.k)}</span>
                    <span className="mt-1 block text-sm leading-relaxed text-[var(--text-muted)]">
                      {t(p.b)}
                    </span>
                  </span>
                </li>
              ))}
            </ul>

            <p className="mt-9 text-sm text-[var(--text-faint)]">{t('home.free')}</p>
          </section>

          {/* ----------------------------------------------------- aanmelden */}
          <section className="w-full lg:w-[22rem]">
            <div className="lg:sticky lg:top-10">
              <h2 className="mb-4 text-lg font-semibold tracking-tight">{t('common.signIn')}</h2>
              <LoginForm brandName="PokerLeague" fallbackNext="/ik" bare />

              <div className="mt-6 rounded-[var(--radius)] border border-dashed border-[var(--line-strong)] p-5">
                <p className="text-sm font-medium">{t('home.newHere')}</p>
                <p className="mt-1 text-sm leading-relaxed text-[var(--text-muted)]">
                  {t('home.newHereBody')}
                </p>
                <Link
                  href="/registreren"
                  className="mt-4 inline-block rounded-full bg-[var(--brand)] px-5 py-2.5 text-sm font-medium text-[var(--on-brand)] transition hover:brightness-110"
                >
                  {t('site.nav.createAccount')}
                </Link>
              </div>
            </div>
          </section>
        </main>

        {/* Eén regel voor clubs, en verder niets. Een club die hier belandt
            weet nu waar hij moet zijn; een speler heeft er geen last van. */}
        <footer className="border-t border-[var(--line)]">
          <div className="mx-auto flex max-w-6xl flex-wrap items-center justify-between gap-3 px-5 py-6 text-xs text-[var(--text-faint)] sm:px-8">
            <span>{t('site.footer.tagline')}</span>
            <span>{t('home.forClubs')}</span>
          </div>
        </footer>
      </div>
    </LocaleProvider>
  )
}
