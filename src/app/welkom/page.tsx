import { redirect } from 'next/navigation'
import { Onboarding } from '@/components/Onboarding'
import type { JoinableClub } from '@/components/JoinClubs'
import { LanguageSwitch } from '@/components/LanguageSwitch'
import { LocaleProvider } from '@/lib/i18n/context'
import { translator } from '@/lib/i18n/dictionaries'
import { publicLocale } from '@/lib/i18n/server'
import { createClient } from '@/lib/supabase/server'

/**
 * Het welkomstscherm, één keer per speler.
 *
 * Hier komt de bevestigingsmail op uit. De uitleg over waaróm dit scherm
 * bestaat staat bij het component; hier gebeurt alleen het ophalen.
 */

interface Me {
  first_name: string | null
  last_name: string | null
  username: string | null
  public_listing: boolean
  birthdate: string | null
  stats_consent_at: string | null
  onboarded_at: string | null
}

export async function generateMetadata() {
  return { title: translator(await publicLocale())('ob.metaTitle') }
}

export default async function Page() {
  const supabase = await createClient()
  const { data: claims } = await supabase.auth.getClaims()
  if (!claims?.claims) redirect('/login?next=/welkom')

  // Het profiel bestaat mogelijk nog niet: iemand kan hier binnenkomen zonder
  // ooit op zijn eigen pagina geweest te zijn.
  await supabase.rpc('claim_my_player', {})

  const [meRes, clubsRes] = await Promise.all([
    supabase.rpc('my_player'),
    supabase.rpc('clubs_open_to_join'),
  ])

  const me = ((meRes.data ?? []) as unknown as Me[])[0] ?? null
  // Al doorlopen? Dan is dit scherm klaar met hem.
  if (me?.onboarded_at) redirect('/ik')

  const clubs = (clubsRes.data ?? []) as unknown as JoinableClub[]
  const locale = await publicLocale()
  const t = translator(locale)

  return (
    <LocaleProvider locale={locale}>
      <div data-site lang={locale} className="min-h-dvh bg-[var(--bg)] text-[var(--text)]">
        <header className="border-b border-[var(--line)]">
          <div className="mx-auto flex max-w-xl items-center gap-3 px-5 py-4">
            <span className="text-sm font-semibold uppercase tracking-[0.22em]">
              Poker<span className="text-[var(--brand)]">League</span>
            </span>
            <span className="flex-1" />
            <LanguageSwitch current={locale} label={t('common.language')} />
          </div>
        </header>

        <main className="px-5 py-10 sm:py-14">
          <Onboarding
            clubs={clubs}
            firstName={me?.first_name ?? ''}
            lastName={me?.last_name ?? ''}
            username={me?.username ?? ''}
            publicListing={me?.public_listing ?? false}
            birthdate={me?.birthdate ?? ''}
            hasConsent={Boolean(me?.stats_consent_at)}
          />
        </main>
      </div>
    </LocaleProvider>
  )
}
