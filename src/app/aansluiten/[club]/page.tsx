import Link from 'next/link'
import { notFound, redirect } from 'next/navigation'
import { JoinClubs, type JoinableClub } from '@/components/JoinClubs'
import { LanguageSwitch } from '@/components/LanguageSwitch'
import { Card, Notice } from '@/components/ui'
import { getClub } from '@/lib/club'
import { LocaleProvider } from '@/lib/i18n/context'
import { translator } from '@/lib/i18n/dictionaries'
import { publicLocale } from '@/lib/i18n/server'
import { createClient } from '@/lib/supabase/server'

/**
 * Je aansluiten bij een club, van buitenaf.
 *
 * Tot nu kon dat maar op één manier: aan de deur, door de floor. Wie de
 * clubpagina vond en zondag wilde komen spelen, kon nergens op klikken.
 *
 * Drie wegen komen hier samen en ze eindigen alle drie op hetzelfde punt:
 *
 *   * je bent aangemeld → je bent nu lid, klaar
 *   * je hebt een account maar bent niet aangemeld → eerst aanmelden
 *   * je hebt niets → registreren, en daarna kom je hier vanzelf terug via
 *     de bevestigingsmail (zie `emailRedirectTo` in RegisterForm)
 *
 * En daarna komt de vraag die alleen op dit moment past: bij welke clubs nog?
 * Wie net besloten heeft ergens bij te horen, staat open voor die vraag. Een
 * week later op een willekeurig scherm zou dezelfde lijst reclame zijn.
 *
 * Wat "lid" hier betekent staat in migratie 0033, en het staat ook op het
 * scherm: dit is een koppeling op het platform, geen toelating. De club
 * controleert nog altijd wie er binnenkomt.
 */

export async function generateMetadata({ params }: PageProps<'/aansluiten/[club]'>) {
  const { club: slug } = await params
  const club = await getClub(slug)
  const t = translator(await publicLocale())
  return { title: club ? `${t('join.title')} — ${club.name}` : t('join.title') }
}

export default async function Page({ params }: PageProps<'/aansluiten/[club]'>) {
  const { club: slug } = await params
  const club = await getClub(slug)
  if (!club) notFound()

  const supabase = await createClient()
  const { data: claims } = await supabase.auth.getClaims()

  // Niet aangemeld? Dan eerst een account, met de club in de hand zodat we
  // hier na de bevestigingsmail weer uitkomen.
  if (!claims?.claims) redirect(`/login?next=/aansluiten/${slug}&club=${slug}`)

  const locale = await publicLocale()
  const t = translator(locale)

  const { data: result, error } = await supabase.rpc('join_club', { p_club_slug: slug })
  const state = (result as unknown as string) ?? 'error'

  const { data: others } = await supabase.rpc('clubs_open_to_join')
  const rest = (others ?? []) as unknown as JoinableClub[]

  return (
    <LocaleProvider locale={locale}>
      <div data-site lang={locale} className="min-h-dvh bg-[var(--bg)] text-[var(--text)]">
        <header className="border-b border-[var(--line)]">
          <div className="mx-auto flex max-w-2xl items-center gap-3 px-5 py-4">
            <Link href="/" className="text-sm font-semibold uppercase tracking-[0.22em]">
              Poker<span className="text-[var(--brand)]">League</span>
            </Link>
            <span className="flex-1" />
            <LanguageSwitch current={locale} label={t('common.language')} />
          </div>
        </header>

        <main className="mx-auto max-w-2xl px-5 py-10">
          {error || state === 'error' ? (
            <Notice tone="error">{error?.message ?? t('join.failed')}</Notice>
          ) : state === 'closed' ? (
            <Card>
              <h1 className="text-xl font-semibold">{t('join.closedTitle')}</h1>
              <p className="mt-2 text-sm leading-relaxed text-[var(--text-muted)]">
                {t('join.closedBody').replace('{club}', club.name)}
              </p>
              {club.contact_email && (
                <a
                  href={`mailto:${club.contact_email}`}
                  className="mt-4 inline-block text-sm text-[var(--brand)] underline-offset-4 hover:underline"
                >
                  {club.contact_email}
                </a>
              )}
            </Card>
          ) : (
            <>
              <div className="flex items-center gap-4">
                {club.logo_url && (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img
                    src={club.logo_url}
                    alt=""
                    className="size-16 shrink-0 rounded-2xl object-contain"
                  />
                )}
                <div className="min-w-0">
                  <p className="text-xs uppercase tracking-[0.22em] text-[var(--brand)]">
                    {state === 'already' ? t('join.alreadyTag') : t('join.doneTag')}
                  </p>
                  <h1 className="mt-1 text-2xl font-semibold tracking-tight">{club.name}</h1>
                  {club.city && (
                    <p className="text-sm text-[var(--text-faint)]">{club.city}</p>
                  )}
                </div>
              </div>

              <Card className="mt-5">
                <p className="text-sm leading-relaxed">
                  {(state === 'already' ? t('join.alreadyBody') : t('join.doneBody'))
                    .replace('{club}', club.name)}
                </p>
                {/* Eerlijk zijn over wat dit niet is. Lid op het platform is
                    geen toelating tot de zaal — daar hoort nog altijd een
                    identiteitskaart bij. */}
                <p className="mt-3 text-xs leading-relaxed text-[var(--text-faint)]">
                  {t('join.notEntry')}
                </p>
                <div className="mt-4 flex flex-wrap gap-4 text-sm">
                  <Link
                    href={`/c/${club.slug}`}
                    className="text-[var(--brand)] underline-offset-4 hover:underline"
                  >
                    {t('join.toClub')} →
                  </Link>
                  <Link
                    href="/ik"
                    className="text-[var(--text-muted)] underline-offset-4 hover:underline"
                  >
                    {t('join.toProfile')} →
                  </Link>
                </div>
              </Card>

              <JoinClubs clubs={rest} />
            </>
          )}
        </main>
      </div>
    </LocaleProvider>
  )
}
