import { LoginForm } from '@/components/LoginForm'
import { LocaleProvider } from '@/lib/i18n/context'
import { translator } from '@/lib/i18n/dictionaries'
import { publicLocale } from '@/lib/i18n/server'

/**
 * Aanmelden als speler. Volgt de taal die de bezoeker koos op de
 * landingspagina — anders staat de knop in het Nederlands onder een Franse
 * homepagina.
 */

export async function generateMetadata() {
  return { title: translator(await publicLocale())('common.signIn') }
}

export default async function Page() {
  const locale = await publicLocale()
  return (
    <LocaleProvider locale={locale}>
      <div lang={locale} className="contents">
        <LoginForm brandName="PokerLeague" fallbackNext="/" />
      </div>
    </LocaleProvider>
  )
}
