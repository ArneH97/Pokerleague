import Link from 'next/link'
import { LanguageSwitch } from '@/components/LanguageSwitch'
import { RsvpToggle } from '@/components/RsvpToggle'
import { SignupChoice } from '@/components/public/SignupChoice'
import { LocaleProvider } from '@/lib/i18n/context'
import { translator, type Locale, type T } from '@/lib/i18n/dictionaries'
import { themeVars, type Club } from '@/lib/club'
import { playerUrl } from '@/lib/site'
import { createClient } from '@/lib/supabase/server'
import { formatMoney } from '@/lib/types'

/**
 * De pagina waar een affiche naartoe wijst.
 *
 * Eén avond, in de kleuren van de club, en één ding om te doen. Wie hier
 * binnenkomt heeft net een QR-code gescand op een affiche in een café of een
 * beeld op Instagram voorbij zien komen; hij weet niet wat PokerLeague is en
 * dat hoeft ook niet. Wat hij moet weten staat boven de vouw: welke avond,
 * hoe laat, waar, wat het kost, en wat hij eraan heeft om nu in te schrijven.
 *
 * **De bonuschips zijn de kop en niet een voetnoot.** Dat is de hele reden dat
 * iemand vandaag iets doet in plaats van zondag te beslissen. Staat er geen
 * bonus op de avond, dan verdwijnt dat blok volledig — een lege belofte is
 * erger dan geen belofte.
 *
 * Geen PokerLeague-merk in de kop. Dit is de avond van de club; dat het
 * platform eronder ligt, merkt hij pas als hij zijn account afmaakt.
 */

export interface SignupCard {
  tournament_id: string
  name: string
  scheduled_at: string
  status: string
  buyin_cents: number
  fee_cents: number
  starting_stack: number
  bonus_stack: number
  registered: number
  is_open: boolean
  club_slug: string
  club_name: string
  city: string | null
  address_line: string | null
  maps_url: string | null
  logo_url: string | null
  primary_color: string | null
  currency: string
  timezone: string
  locale: string
}

export async function SignupPage({
  card, club, locale,
}: {
  card: SignupCard | null
  club: Club
  locale: Locale
}) {
  const t = translator(locale)
  const logoUrl = club.logo_url

  // Absolute adressen naar het platform. Op een clubdomein schrijft de proxy
  // elk pad door naar /c/<club>/…, dus `/registreren` liep daar op een 404 —
  // precies waar `playerUrl` voor bestaat. De taal reist mee, zodat iemand die
  // via de Franse affiche binnenkwam ook een Frans registratieformulier krijgt.
  const registerHref = await playerUrl(`/registreren?club=${club.slug}&l=${locale}`)

  // Terug naar déze avond na het aanmelden, niet naar een algemeen scherm.
  // Wie hier weggaat om zich aan te melden, wil hierna één ding: zeggen dat
  // hij komt. Hem op /ik afzetten betekent dat hij zelf de weg terug moet
  // zoeken, en dat doet niet iedereen.
  const terug = card
    ? `/c/${club.slug}/inschrijven/${card.tournament_id}?l=${locale}`
    : `/c/${club.slug}/inschrijven?l=${locale}`
  const loginHref = await playerUrl(
    `/login?next=${encodeURIComponent(terug)}&l=${locale}`)

  // Is hij al aangemeld? Op het clubdomein nooit — daar woont de sessie van de
  // floor en niet die van de speler. Op het platform wél, en dat is precies
  // waar de aanmeldknop hierboven hem naartoe stuurt. Dan slaan we het
  // formulier over en staat er één knop.
  const supabase = await createClient()
  const { data: claims } = await supabase.auth.getClaims()
  let alIn: boolean | null = null
  if (claims?.claims && card) {
    const { data: mij } = await supabase
      .from('players')
      .select('id')
      .eq('auth_user_id', String(claims.claims.sub))
      .is('merged_into_id', null)
      .maybeSingle<{ id: string }>()
    if (mij) {
      const { data: insch } = await supabase
        .from('tournament_registrations')
        .select('id')
        .eq('tournament_id', card.tournament_id)
        .eq('player_id', mij.id)
        .is('cancelled_at', null)
        .maybeSingle<{ id: string }>()
      alIn = insch !== null
    }
  }

  return (
    <LocaleProvider locale={locale}>
      <div
        lang={locale}
        className="min-h-dvh bg-[var(--bg)] text-[var(--text)]"
        style={themeVars(club)}
      >
        <header className="border-b border-[var(--line)]">
          <div className="mx-auto flex max-w-2xl items-center gap-3 px-5 py-4">
            <Link href={`/c/${club.slug}`} className="min-w-0 truncate text-sm font-semibold uppercase tracking-[0.18em]">
              {club.name}
            </Link>
            <span className="flex-1" />
            <LanguageSwitch current={locale} label={t('common.language')} />
          </div>
        </header>

        <main className="mx-auto max-w-2xl px-5 py-8 sm:py-12">
          {card === null ? (
            <Nothing t={t} clubName={club.name} />
          ) : (
            <>
              <Head card={card} t={t} locale={locale} logoUrl={logoUrl} />

              {card.is_open ? (
                <div className="mt-7">
                  {alIn === null ? (
                    <SignupChoice
                      tournamentId={card.tournament_id}
                      clubName={card.club_name}
                      bonusStack={card.bonus_stack}
                      registerHref={registerHref}
                      loginHref={loginHref}
                    />
                  ) : (
                    <div className="rounded-[var(--radius-lg)] border border-[var(--line)] bg-[var(--surface)] p-6 text-center">
                      <p className="text-sm text-[var(--text-muted)]">
                        {alIn ? t('choice.youAreIn') : t('choice.oneTap')}
                      </p>
                      <div className="mt-4 flex justify-center">
                        <RsvpToggle tournamentId={card.tournament_id} isIn={alIn} />
                      </div>
                    </div>
                  )}
                </div>
              ) : (
                <div className="mt-7 rounded-[var(--radius-lg)] border border-[var(--line)] bg-[var(--surface)] p-6 text-center">
                  <p className="font-medium">{t('rsvp.closedTitle')}</p>
                  <p className="mt-2 text-sm text-[var(--text-muted)]">{t('rsvp.closedBody')}</p>
                </div>
              )}
            </>
          )}
        </main>

        <footer className="mx-auto max-w-2xl px-5 pb-10 text-center text-xs text-[var(--text-faint)]">
          {t('rsvp.footer')}
        </footer>
      </div>
    </LocaleProvider>
  )
}

function Head({
  card, t, locale, logoUrl,
}: { card: SignupCard; t: T; locale: Locale; logoUrl: string | null }) {
  const at = new Date(card.scheduled_at)
  const day = new Intl.DateTimeFormat(`${locale}-BE`, {
    weekday: 'long', day: 'numeric', month: 'long', timeZone: card.timezone,
  }).format(at)
  const time = new Intl.DateTimeFormat(`${locale}-BE`, {
    hour: '2-digit', minute: '2-digit', timeZone: card.timezone,
  }).format(at)
  const cost = Number(card.buyin_cents) + Number(card.fee_cents)
  const nf = new Intl.NumberFormat('nl-BE')

  return (
    <div className="text-center">
      {logoUrl && (
        // eslint-disable-next-line @next/next/no-img-element
        <img src={logoUrl} alt="" className="mx-auto size-20 rounded-2xl object-contain" />
      )}

      <p className="mt-5 text-xs font-semibold uppercase tracking-[0.22em] text-[var(--brand)]">
        {day} · {time}
      </p>
      <h1 className="mt-2 text-balance text-[2rem] font-semibold leading-tight tracking-tight sm:text-4xl">
        {card.name}
      </h1>
      {(card.address_line || card.city) && (
        <p className="mt-2 text-sm text-[var(--text-muted)]">
          {card.maps_url ? (
            <a href={card.maps_url} target="_blank" rel="noreferrer" className="underline-offset-4 hover:underline">
              {card.address_line ?? card.city}
            </a>
          ) : (
            card.address_line ?? card.city
          )}
        </p>
      )}

      {/* ------------------------------------------------------------ bonus
          Het enige blok met kleur, want het is de enige reden om nú te
          klikken in plaats van er zondag nog eens aan te denken. */}
      {card.bonus_stack > 0 && card.is_open && (
        <div className="mt-6 rounded-[var(--radius-lg)] border border-[var(--brand)] bg-[color-mix(in_oklab,var(--brand)_12%,transparent)] px-5 py-4">
          <p className="tnum text-2xl font-semibold text-[var(--brand)] sm:text-3xl">
            +{nf.format(card.bonus_stack)} {t('rsvp.chips')}
          </p>
          <p className="mt-1 text-sm text-[var(--text-muted)]">{t('rsvp.bonusWhy')}</p>
        </div>
      )}

      <dl className="mt-6 grid grid-cols-3 gap-2 text-center">
        <Cell label={t('rsvp.buyin')} value={cost > 0 ? formatMoney(cost, card.currency) : '—'} />
        <Cell label={t('rsvp.stack')} value={nf.format(card.starting_stack + card.bonus_stack)} />
        <Cell label={t('rsvp.signedUp')} value={String(card.registered)} />
      </dl>
    </div>
  )
}

function Cell({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-[var(--radius)] border border-[var(--line)] bg-[var(--surface)] px-2 py-3">
      <dt className="text-[0.6rem] font-medium uppercase tracking-[0.14em] text-[var(--text-faint)]">
        {label}
      </dt>
      <dd className="tnum mt-1 text-base font-semibold sm:text-lg">{value}</dd>
    </div>
  )
}

function Nothing({ t, clubName }: { t: T; clubName: string }) {
  return (
    <div className="rounded-[var(--radius-lg)] border border-[var(--line)] bg-[var(--surface)] px-6 py-14 text-center">
      <p className="text-base font-medium">{t('rsvp.noneTitle')}</p>
      <p className="mx-auto mt-2 max-w-sm text-sm leading-relaxed text-[var(--text-muted)]">
        {t('rsvp.noneBody').replace('{club}', clubName)}
      </p>
    </div>
  )
}
