import { redirect } from 'next/navigation'
import { LanguageSwitch } from '@/components/LanguageSwitch'
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
 *
 * Hier staat ook de uitleg over clubbeheer. Die stond op het overzicht, waar
 * ze bij elke speler in beeld kwam terwijl ze voor bijna niemand geldt. Weg
 * kan ze niet: dat clubbeheer aan een ánder account kan hangen dan waarmee je
 * speelt, is precies het misverstand waar we een avond aan verloren hebben.
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
      <div data-app lang={locale} className="min-h-dvh bg-[var(--bg)] text-[var(--text)]">
        <PlayerNav locale={locale} t={t} active="settings" />

        <main className="mx-auto max-w-3xl space-y-6 px-4 pb-28 pt-5 sm:px-5 sm:pb-12 sm:pt-7">
          <h1 className="text-2xl font-semibold tracking-tight">{t('me.navSettings')}</h1>

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

          {/* De taalkiezer staat op een telefoon niet in de balk bovenaan —
              daar paste hij niet naast de rest. Hier wel, want dit is de plek
              waar je je instellingen komt zoeken. */}
          <section className="rounded-[var(--radius)] border border-[var(--line)] bg-[var(--surface)] p-4 sm:hidden">
            <h2 className="mb-2 text-xs uppercase tracking-[0.22em] text-[var(--text-faint)]">
              {t('common.language')}
            </h2>
            <LanguageSwitch current={locale} label={t('common.language')} />
          </section>

          <p className="text-xs leading-relaxed text-[var(--text-faint)]">
            {t('me.staffElsewhere')}
          </p>
        </main>
      </div>
    </LocaleProvider>
  )
}
