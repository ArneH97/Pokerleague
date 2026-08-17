import { redirect } from 'next/navigation'
import { RegisterForm } from '@/components/RegisterForm'
import { LocaleProvider } from '@/lib/i18n/context'
import { translator } from '@/lib/i18n/dictionaries'
import { publicLocale } from '@/lib/i18n/server'
import { createClient } from '@/lib/supabase/server'

/** Registreren als speler. Wie al aangemeld is hoort hier niet te zijn. */
export async function generateMetadata() {
  return { title: translator(await publicLocale())('register.title') }
}

export default async function Page() {
  const supabase = await createClient()
  const { data: claims } = await supabase.auth.getClaims()
  if (claims?.claims) redirect('/ik')

  const locale = await publicLocale()
  return (
    <LocaleProvider locale={locale}>
      <div data-site lang={locale} className="min-h-dvh bg-[var(--bg)] text-[var(--text)]">
        <RegisterForm />
      </div>
    </LocaleProvider>
  )
}
