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
  return (
    <LocaleProvider locale={locale}>
      <div data-site lang={locale} className="min-h-dvh bg-[var(--bg)] text-[var(--text)]">
        <LoginForm brandName="PokerLeague" fallbackNext="/ik" />
      </div>
    </LocaleProvider>
  )
}
