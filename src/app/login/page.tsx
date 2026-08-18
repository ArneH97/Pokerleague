import Link from 'next/link'
import { LoginForm } from '@/components/LoginForm'
import { LocaleProvider } from '@/lib/i18n/context'
import { translator } from '@/lib/i18n/dictionaries'
import { publicLocale } from '@/lib/i18n/server'

/**
 * Aanmelden als speler. Volgt de taal die de bezoeker koos op de
 * landingspagina — anders staat de knop in het Nederlands onder een Franse
 * homepagina.
 *
 * `data-site` is hier geen detail. Zonder dat kenmerk valt de pagina terug op
 * het thema van de clubomgeving: donker, met de oude groene knop. Dat viel op
 * als een scherm uit een andere applicatie — precies op het moment dat je om
 * iemands wachtwoord vraagt, en dat is het slechtste moment om er onbekend
 * uit te zien.
 */

export async function generateMetadata() {
  return { title: translator(await publicLocale())('common.signIn') }
}

export default async function Page() {
  const locale = await publicLocale()
  const t = translator(locale)
  return (
    <LocaleProvider locale={locale}>
      <div
        data-site
        lang={locale}
        className="app-glow relative min-h-dvh overflow-x-clip bg-[var(--bg)] text-[var(--text)]"
      >
        <LoginForm brandName="PokerLeague" fallbackNext="/ik" />

        {/* Wie hier staat zonder account had geen enkele uitweg: het scherm
            vroeg om een wachtwoord dat nog niet bestaat. Eén regel volstaat,
            en ze hoort onder de kaart — niet erboven, want negen van de tien
            komen hier om aan te melden. */}
        <p className="-mt-6 pb-12 text-center text-sm text-[var(--text-muted)]">
          {t('login.noAccount')}{' '}
          <Link
            href="/registreren"
            className="font-medium text-[var(--brand)] underline-offset-4 hover:underline"
          >
            {t('home.ctaMake')} →
          </Link>
        </p>
      </div>
    </LocaleProvider>
  )
}
