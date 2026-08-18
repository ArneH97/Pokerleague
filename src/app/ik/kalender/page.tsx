import Link from 'next/link'
import { redirect } from 'next/navigation'
import { PlayerNav } from '@/components/PlayerNav'
import { LocaleProvider } from '@/lib/i18n/context'
import { translator, type Locale, type T } from '@/lib/i18n/dictionaries'
import { publicLocale } from '@/lib/i18n/server'
import { createClient } from '@/lib/supabase/server'
import { formatMoney } from '@/lib/types'

/**
 * Waar er gespeeld wordt, bij al zijn clubs tegelijk.
 *
 * Dit is de vraag die een speler wekelijks heeft en die het product tot nu
 * alleen per club beantwoordde. Bij één club valt dat mee; vanaf twee is het
 * rondklikken, en twee clubs is precies waar dit platform voor bestaat.
 *
 * **Gegroepeerd per dag, niet als één lange lijst.** Een rij van vijftien
 * regels met telkens een datum ervoor dwingt je de datums te lézen. Met een
 * kop per dag zie je de vorm van je maand in één blik: waar het druk is en
 * waar er niets staat.
 *
 * **De clubkleur draagt de herkenning.** Een streep links in de huisstijl van
 * de club, en de naam erbij — geen van beide alleen. Wie kleuren minder goed
 * onderscheidt heeft de naam; wie snel scrolt heeft de kleur.
 *
 * **Geen inschrijfknop.** Die bestaat nog niet in het product, en een knop die
 * niets doet is erger dan geen knop. Wat er wél staat is of je al ingeschreven
 * bent, want dat weet de database wel.
 */

interface Row {
  tournament_id: string
  name: string
  scheduled_at: string
  status: string
  club_slug: string
  club_name: string
  logo_url: string | null
  primary_color: string | null
  currency: string
  timezone: string
  buyin_cents: number
  fee_cents: number
  entries: number
  i_play: boolean
}

export async function generateMetadata() {
  return { title: translator(await publicLocale())('me.navCalendar') }
}

export default async function Page() {
  const supabase = await createClient()
  const { data: claims } = await supabase.auth.getClaims()
  if (!claims?.claims) redirect('/login?next=/ik/kalender')

  const locale = await publicLocale()
  const t = translator(locale)

  const [calRes, clubsRes] = await Promise.all([
    supabase.rpc('my_calendar', { p_days: 120 }),
    supabase.rpc('my_clubs'),
  ])

  const rows = (calRes.data ?? []) as unknown as Row[]
  const clubCount = ((clubsRes.data ?? []) as unknown as unknown[]).length

  // Groeperen op de kalenderdag in Brussel. Niet op de tijdzone van de club:
  // die staan allemaal op Brussel, en zou dat ooit veranderen, dan nog kijkt
  // de speler naar zijn eigen week en niet naar die van de zaal.
  const dayKey = new Intl.DateTimeFormat('en-CA', {
    year: 'numeric', month: '2-digit', day: '2-digit', timeZone: 'Europe/Brussels',
  })
  const days = rows.reduce<{ key: string; at: Date; rows: Row[] }[]>((acc, r) => {
    const at = new Date(r.scheduled_at)
    const key = dayKey.format(at)
    const last = acc[acc.length - 1]
    if (last && last.key === key) last.rows.push(r)
    else acc.push({ key, at, rows: [r] })
    return acc
  }, [])

  // "Morgen" wordt afgeleid van "vandaag" en niet van de klok: middaguur als
  // ankerpunt, zodat het overspringen van de zomertijd er geen dag naast zit.
  const today = dayKey.format(new Date())
  const tomorrow = dayKey.format(new Date(Date.parse(`${today}T12:00:00Z`) + 86_400_000))

  return (
    <LocaleProvider locale={locale}>
      <div data-app lang={locale} className="min-h-dvh bg-[var(--bg)] text-[var(--text)]">
        <PlayerNav locale={locale} t={t} active="calendar" />

        <main className="mx-auto max-w-3xl space-y-6 px-4 pb-28 pt-5 sm:px-5 sm:pb-12 sm:pt-7">
          <header>
            <h1 className="text-2xl font-semibold tracking-tight">{t('me.navCalendar')}</h1>
            <p className="mt-1 text-sm text-[var(--text-muted)]">
              {clubCount > 0 ? t('cal.lede') : t('cal.noClubsLede')}
            </p>
          </header>

          {rows.length === 0 ? (
            <Empty t={t} hasClubs={clubCount > 0} />
          ) : (
            <div className="space-y-6">
              {days.map((d) => (
                <section key={d.key}>
                  <h2 className="mb-2 flex items-baseline gap-2 text-[0.7rem] font-medium uppercase tracking-[0.18em] text-[var(--text-faint)]">
                    <span className={d.key === today ? 'text-[var(--brand)]' : ''}>
                      {d.key === today
                        ? t('cal.today')
                        : d.key === tomorrow
                          ? t('cal.tomorrow')
                          : new Intl.DateTimeFormat(`${locale}-BE`, {
                              weekday: 'long', day: 'numeric', month: 'long',
                              timeZone: 'Europe/Brussels',
                            }).format(d.at)}
                    </span>
                  </h2>

                  <ul className="space-y-2">
                    {d.rows.map((r) => (
                      <Event key={r.tournament_id} row={r} t={t} locale={locale} />
                    ))}
                  </ul>
                </section>
              ))}
            </div>
          )}
        </main>
      </div>
    </LocaleProvider>
  )
}

function Event({ row, t, locale }: { row: Row; t: T; locale: Locale }) {
  const live = row.status === 'running' || row.status === 'paused'
  const color = row.primary_color || 'var(--accent)'
  const time = new Intl.DateTimeFormat(`${locale}-BE`, {
    hour: '2-digit', minute: '2-digit', timeZone: 'Europe/Brussels',
  }).format(new Date(row.scheduled_at))
  const cost = Number(row.buyin_cents) + Number(row.fee_cents)

  return (
    <li>
      <Link
        href={live ? `/c/${row.club_slug}/live/${row.tournament_id}` : `/c/${row.club_slug}/kalender`}
        className="flex items-stretch gap-3 overflow-hidden rounded-[var(--radius)] border border-[var(--line)] bg-[var(--surface)] transition-colors hover:bg-[var(--surface-hover)]"
      >
        {/* De kleurstreep van de club. Vier pixels, en het is het enige waar je
            op scrolt naar kijkt. */}
        <span aria-hidden className="w-1 shrink-0" style={{ background: color }} />

        <span className="flex min-w-0 flex-1 items-center gap-3 py-3 pr-3.5">
          {/* Alleen het uur in deze kolom. Het aantal ingeschrevenen stond er
              eerst onder, en dat brak in het Frans over twee regels
              ("12 inscrits" past niet in de breedte van "20:00"). Zo'n kolom
              die per taal een andere hoogte krijgt, maakt de hele lijst
              onrustig. */}
          <span className="tnum w-12 shrink-0 text-center text-base font-semibold leading-none">
            {time}
          </span>

          {/* De naam krijgt de hele regel. Stond het "bezig"-plaatje er eerst
              naast, dan bleef er op een telefoon "Dinsdagavond …" van over —
              en de naam is nu net waaraan je de avond herkent. Alles wat erbij
              hoort staat op de tweede regel, waar het mag aflopen. */}
          <span className="min-w-0 flex-1">
            <span className="block truncate font-medium">{row.name}</span>
            <span className="mt-0.5 flex flex-wrap items-center gap-x-2 gap-y-1 text-xs text-[var(--text-faint)]">
              <span className="truncate" style={{ color }}>{row.club_name}</span>
              {cost > 0 && <span className="tnum">{formatMoney(cost, row.currency)}</span>}
              {row.entries > 0 && (
                <span className="tnum">{t('cal.entriesShort').replace('{n}', String(row.entries))}</span>
              )}
              {live && (
                <span className="flex shrink-0 items-center gap-1 rounded-full bg-[color-mix(in_oklab,var(--ok)_18%,transparent)] px-2 py-0.5 text-[0.6rem] font-semibold uppercase tracking-wide text-[var(--ok)]">
                  <span aria-hidden className="size-1.5 rounded-full bg-[var(--ok)]" />
                  {t('cal.live')}
                </span>
              )}
            </span>
          </span>

          {row.i_play && (
            <span className="shrink-0 rounded-full border border-[var(--line-strong)] px-2.5 py-1 text-[0.65rem] font-medium text-[var(--text-muted)]">
              {t('cal.youIn')}
            </span>
          )}
        </span>
      </Link>
    </li>
  )
}

function Empty({ t, hasClubs }: { t: T; hasClubs: boolean }) {
  return (
    <div className="rounded-[var(--radius-lg)] border border-[var(--line)] bg-[var(--surface)] px-6 py-12 text-center">
      <p className="text-base font-medium">{hasClubs ? t('cal.empty') : t('cal.noClubs')}</p>
      <p className="mx-auto mt-2 max-w-sm text-sm leading-relaxed text-[var(--text-muted)]">
        {hasClubs ? t('cal.emptyBody') : t('cal.noClubsBody')}
      </p>
      <Link
        href="/clubs"
        className="mt-5 inline-block rounded-full border border-[var(--line-strong)] px-5 py-2.5 text-sm transition hover:bg-[var(--surface-hover)]"
      >
        {t('me.discover')} →
      </Link>
    </div>
  )
}
