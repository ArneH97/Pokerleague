import { redirect } from 'next/navigation'
import { RegisterForm } from '@/components/RegisterForm'
import { getClub } from '@/lib/club'
import { LocaleProvider } from '@/lib/i18n/context'
import { translator } from '@/lib/i18n/dictionaries'
import { publicLocale } from '@/lib/i18n/server'
import { createClient } from '@/lib/supabase/server'

/** Registreren als speler. Wie al aangemeld is hoort hier niet te zijn. */
export async function generateMetadata() {
  return { title: translator(await publicLocale())('register.title') }
}

export default async function Page({ searchParams }: PageProps<'/registreren'>) {
  const supabase = await createClient()
  const { data: claims } = await supabase.auth.getClaims()

  const q = await searchParams
  const raw = typeof q.club === 'string' ? q.club : undefined
  // Alleen een vorm die een slug kán zijn. Wat hier binnenkomt gaat straks in
  // een pad en in een redirect, en dat is geen plek voor vrije tekst.
  const joinSlug = raw && /^[a-z0-9-]{1,40}$/.test(raw) ? raw : undefined

  // Al aangemeld? Dan hoeft hij niets aan te maken — hooguit nog aan te sluiten.
  if (claims?.claims) redirect(joinSlug ? `/aansluiten/${joinSlug}` : '/ik')

  const club = joinSlug ? await getClub(joinSlug) : null
  const locale = await publicLocale()

  return (
    <LocaleProvider locale={locale}>
      <div data-site lang={locale} className="min-h-dvh bg-[var(--bg)] text-[var(--text)]">
        <RegisterForm clubName={club?.name} joinSlug={club ? joinSlug : undefined} />
      </div>
    </LocaleProvider>
  )
}
