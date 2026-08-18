import { redirect } from 'next/navigation'
import { PlayerNav } from '@/components/PlayerNav'
import { PlayerProfileForm } from '@/components/PlayerProfileForm'
import { Notice } from '@/components/ui'
import { LocaleProvider } from '@/lib/i18n/context'
import { translator } from '@/lib/i18n/dictionaries'
import { publicLocale } from '@/lib/i18n/server'
import { createClient } from '@/lib/supabase/server'

/**
 * Mijn gegevens, op een eigen pagina.
 *
 * Stond onderaan het overzicht, onder de resultaten. Dat is de verkeerde plek
 * om twee redenen: je scrolt eroverheen bij elk bezoek terwijl je er hooguit
 * twee keer per jaar iets wijzigt, en het duwt precies wat je wél komt halen —
 * je cijfers — naar boven weg tot een aanhangsel.
 */

interface Me {
  first_name: string | null
  last_name: string | null
  username: string | null
  email: string | null
  locale: string
  public_listing: boolean
  public_profile: boolean
}

export async function generateMetadata() {
  return { title: translator(await publicLocale())('me.navSettings') }
}

export default async function Page() {
  const supabase = await createClient()
  const { data: claims } = await supabase.auth.getClaims()
  if (!claims?.claims) redirect('/login?next=/ik/gegevens')

  const locale = await publicLocale()
  const t = translator(locale)

  const { data } = await supabase.rpc('my_player')
  const me = ((data ?? []) as unknown as Me[])[0] ?? null

  return (
    <LocaleProvider locale={locale}>
      <div data-site lang={locale} className="min-h-dvh bg-[var(--bg)] text-[var(--text)]">
        <PlayerNav locale={locale} t={t} active="settings" />

        <main className="mx-auto max-w-3xl px-5 py-7">
          <h1 className="mb-5 text-2xl font-semibold tracking-tight">{t('me.navSettings')}</h1>
          {me ? (
            <PlayerProfileForm
              me={{
                first_name: me.first_name,
                last_name: me.last_name,
                username: me.username,
                email: me.email,
                locale: me.locale,
                public_listing: me.public_listing,
                public_profile: me.public_profile,
              }}
            />
          ) : (
            <Notice tone="error">{t('me.noProfile')}</Notice>
          )}
        </main>
      </div>
    </LocaleProvider>
  )
}
