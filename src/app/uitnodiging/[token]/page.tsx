import Link from 'next/link'
import { redirect } from 'next/navigation'
import { RegisterForm } from '@/components/RegisterForm'
import { Card } from '@/components/ui'
import { LanguageSwitch } from '@/components/LanguageSwitch'
import { LocaleProvider } from '@/lib/i18n/context'
import { isLocale, translator, type Locale } from '@/lib/i18n/dictionaries'
import { visitorLocale } from '@/lib/i18n/server'
import { createClient } from '@/lib/supabase/server'

/**
 * Waar de uitnodigingsmail landt.
 *
 * Deze pagina moet in vijf seconden één vraag beantwoorden: *waarom krijg ik
 * dit?* Wie hier binnenkomt klikte op een link in een mail van een clubnaam
 * die hij herkent, en belandt op een domein dat hij niet kent. Dus staat de
 * club bovenaan, en pas daarna waar hij een account voor maakt.
 *
 * Het token opent hier niets. Het zegt alleen wie er uitnodigt en op welk
 * adres — de uitleg staat in migratie 0029. Het echte opeisen gebeurt zoals bij
 * iedereen: registreren, mailadres bevestigen, en dan koppelt `claim_my_player`
 * de historie op dat geverifieerde adres.
 *
 * De taal komt uit de uitnodiging (de taal van de speler, anders die van de
 * club) en niet uit het koekje van de bezoeker: hij kreeg de mail in een taal
 * en hoort hier dezelfde te zien. Kiezen mag natuurlijk wel.
 */

interface Invite {
  club_slug: string
  club_name: string
  club_city: string | null
  logo_url: string | null
  primary_color: string | null
  contact_email: string | null
  locale: string
  player_name: string
  email: string
  expires_at: string
  state: 'open' | 'expired' | 'accepted' | 'has_account'
}

async function lookup(token: string): Promise<Invite | null> {
  const supabase = await createClient()
  const { data } = await supabase.rpc('invite_lookup', { p_token: token })
  return ((data ?? []) as unknown as Invite[])[0] ?? null
}

export async function generateMetadata({ params }: PageProps<'/uitnodiging/[token]'>) {
  const { token } = await params
  const inv = await lookup(token)
  const locale = (isLocale(inv?.locale) ? inv.locale : 'nl') as Locale
  const t = translator(locale)
  return {
    title: inv ? `${t('invite.title')} — ${inv.club_name}` : t('invite.unknownTitle'),
    robots: { index: false, follow: false },
  }
}

export default async function Page({ params }: PageProps<'/uitnodiging/[token]'>) {
  const { token } = await params
  const inv = await lookup(token)

  // Wie al aangemeld is heeft niets aan een registratieformulier.
  const supabase = await createClient()
  const { data: claims } = await supabase.auth.getClaims()
  if (claims?.claims) redirect('/ik')

  // De taal van de mail wint, tenzij de bezoeker hier zelf iets koos.
  const chosen = await visitorLocale()
  const locale: Locale = chosen ?? (isLocale(inv?.locale) ? inv.locale : 'nl')
  const t = translator(locale)

  return (
    <LocaleProvider locale={locale}>
      <div data-site lang={locale} className="min-h-dvh bg-[var(--bg)] text-[var(--text)]">
        <header className="border-b border-[var(--line)]">
          <div className="mx-auto flex max-w-3xl items-center gap-3 px-5 py-4">
            <Link href="/" className="text-sm font-semibold uppercase tracking-[0.22em]">
              Poker<span className="text-[var(--brand)]">League</span>
            </Link>
            <span className="flex-1" />
            <LanguageSwitch current={locale} label={t('common.language')} />
          </div>
        </header>

        {!inv ? (
          <Dead
            title={t('invite.unknownTitle')}
            body={t('invite.unknownBody')}
            t={t}
          />
        ) : inv.state === 'expired' ? (
          <Dead
            title={t('invite.expiredTitle')}
            body={t('invite.expiredBody').replace('{club}', inv.club_name)}
            contact={inv.contact_email}
            t={t}
          />
        ) : inv.state === 'accepted' || inv.state === 'has_account' ? (
          <Dead
            title={t('invite.doneTitle')}
            body={t('invite.doneBody')}
            signIn
            t={t}
          />
        ) : (
          <>
            {/* ------------------------------------------------ wie nodigt uit */}
            <section className="border-b border-[var(--line)] bg-[var(--surface)]">
              <div className="mx-auto flex max-w-3xl items-center gap-4 px-5 py-7">
                {inv.logo_url ? (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img
                    src={inv.logo_url}
                    alt=""
                    className="size-14 shrink-0 rounded-[var(--radius)] object-contain"
                  />
                ) : null}
                <div className="min-w-0">
                  <p className="text-[0.65rem] uppercase tracking-[0.22em] text-[var(--text-faint)]">
                    {t('invite.from')}
                  </p>
                  <h1 className="mt-1 truncate text-xl font-semibold tracking-tight sm:text-2xl">
                    {inv.club_name}
                  </h1>
                  {inv.club_city && (
                    <p className="text-sm text-[var(--text-faint)]">{inv.club_city}</p>
                  )}
                </div>
              </div>
            </section>

            {/* -------------------------------------------------- wat en waarom
                Drie regels, in de volgorde waarin de vragen opkomen: wat is er
                van mij bijgehouden, waar staat dat, en wat heb ik eraan. */}
            <section className="mx-auto max-w-3xl px-5 pt-7">
              <Card>
                <p className="text-base leading-relaxed">
                  {t('invite.played').replace('{club}', inv.club_name)}
                </p>
                <p className="mt-3 text-sm leading-relaxed text-[var(--text-muted)]">
                  {t('invite.explain').replace('{club}', inv.club_name)}
                </p>
              </Card>
            </section>

            <RegisterForm invitedEmail={inv.email} clubName={inv.club_name} />
          </>
        )}
      </div>
    </LocaleProvider>
  )
}

function Dead({
  title, body, contact, signIn, t,
}: {
  title: string
  body: string
  contact?: string | null
  signIn?: boolean
  t: ReturnType<typeof translator>
}) {
  return (
    <main className="mx-auto max-w-md px-5 py-14">
      <Card>
        <h1 className="text-xl font-semibold">{title}</h1>
        <p className="mt-2 text-sm leading-relaxed text-[var(--text-muted)]">{body}</p>

        <div className="mt-5 flex flex-wrap gap-4 text-sm">
          {signIn && (
            <Link href="/login" className="text-[var(--brand)] underline-offset-4 hover:underline">
              {t('common.signIn')} →
            </Link>
          )}
          {contact && (
            <a
              href={`mailto:${contact}`}
              className="text-[var(--brand)] underline-offset-4 hover:underline"
            >
              {contact}
            </a>
          )}
          {!signIn && (
            <Link
              href="/registreren"
              className="text-[var(--text-muted)] underline-offset-4 hover:underline"
            >
              {t('invite.registerAnyway')} →
            </Link>
          )}
        </div>
      </Card>
    </main>
  )
}
