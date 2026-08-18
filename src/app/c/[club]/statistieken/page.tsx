import Link from 'next/link'
import { notFound, redirect } from 'next/navigation'
import { BarChart } from '@/components/BarChart'
import { ClubNav } from '@/components/ClubNav'
import { Card, EmptyState, Notice, Page, PageHeader, SectionTitle } from '@/components/ui'
import { getClub, getClubRole } from '@/lib/club'
import { translator } from '@/lib/i18n/dictionaries'
import { clubLocale } from '@/lib/i18n/server'
import { createClient } from '@/lib/supabase/server'
import { formatMoney } from '@/lib/types'

/**
 * De cijfers van de club.
 *
 * Wat een clubeigenaar hier komt halen is niet één getal maar een richting:
 * komen er meer mensen dan vorig jaar, blijft er genoeg over voor de zaal, en
 * groeit het ledenbestand of speelt telkens dezelfde groep. Vandaar de
 * maandreeks naast de totalen — een totaal zonder verloop kan zowel groei als
 * verval zijn.
 *
 * Alleen afgesloten tornooien tellen mee. Een avond die nog loopt heeft geen
 * uitslag en zou het gemiddelde vertekenen.
 */

interface Stats {
  tournaments: number
  entries: number
  unique_players: number
  new_players: number
  avg_entries: number
  biggest_field: number
  prize_cents: number
  club_cents: number
  bounty_cents: number
  avg_minutes: number
}

interface MonthRow {
  month: string
  tournaments: number
  entries: number
  prize_cents: number
  club_cents: number
}

export default async function Page_({ params, searchParams }: PageProps<'/c/[club]/statistieken'>) {
  const { club: slug } = await params
  const q = await searchParams
  const club = await getClub(slug)
  if (!club) notFound()

  const supabase = await createClient()
  const { data: claims } = await supabase.auth.getClaims()
  const accountEmail = (claims?.claims?.email as string | undefined) ?? null
  if (!claims?.claims) redirect(`/c/${slug}/login?next=/c/${slug}/statistieken`)

  const role = await getClubRole(club.id)
  const locale = await clubLocale(club.locale)
  const t = translator(locale)

  if (!role || !['owner', 'admin', 'floor'].includes(role)) {
    return (
      <Page>
        <PageHeader
          backHref={`/c/${slug}`}
          backLabel={t('result.backToClub')}
          title={t('stats.title')}
          subtitle={club.name}
          logoUrl={club.logo_url}
        />
        <Notice tone="warn">{t('members.onlyStaff')}</Notice>
      </Page>
    )
  }

  const one = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v)

  // Vier vensters, en het seizoen zit er bewust niet meer bij. Een seizoen is
  // een begrip van het klassement — daar bepaalt het wie er meedingt. Voor de
  // cijfers wil je kalendertijd: dit jaar tegenover vorig jaar, deze maand
  // tegenover vorige maand. Wie iets anders nodig heeft, bijvoorbeeld een
  // boekjaar of één toernooireeks, geeft zelf twee data in.
  const wanted = one(q.p)
  const mode: 'year' | 'month' | 'all' | 'custom' =
    wanted === 'month' ? 'month'
      : wanted === 'all' ? 'all'
        : wanted === 'custom' ? 'custom'
          : 'year'

  const now = new Date()
  const year = now.getFullYear()
  const month = now.getMonth() + 1
  const pad = (n: number) => String(n).padStart(2, '0')
  const lastDay = new Date(year, month, 0).getDate()

  // Een datum die niet klopt hoort de pagina niet stuk te maken; dan valt hij
  // terug op het hele jaar.
  const isDate = (v: string | undefined): v is string => !!v && /^\d{4}-\d{2}-\d{2}$/.test(v)
  const rawFrom = one(q.from)
  const rawTo = one(q.to)
  const customFrom = isDate(rawFrom) ? rawFrom : `${year}-01-01`
  const customTo = isDate(rawTo) ? rawTo : `${year}-${pad(month)}-${pad(lastDay)}`

  const monthLabelLong = new Intl.DateTimeFormat(`${locale}-BE`, { month: 'long', year: 'numeric' })

  const [from, to, label] =
    mode === 'month'
      ? [`${year}-${pad(month)}-01`, `${year}-${pad(month)}-${pad(lastDay)}`,
         monthLabelLong.format(now)]
      : mode === 'all'
        ? ['1900-01-01', '2999-12-31', t('stats.allTime')]
        : mode === 'custom'
          ? [customFrom, customTo, `${customFrom} — ${customTo}`]
          : [`${year}-01-01`, `${year}-12-31`, String(year)]

  const [statRes, monthRes] = await Promise.all([
    supabase.rpc('club_stats', { p_club_id: club.id, p_from: from, p_to: to }),
    supabase.rpc('club_month_series', { p_club_id: club.id, p_months: 12 }),
  ])

  const s = ((statRes.data ?? []) as unknown as Stats[])[0]
  const months = (monthRes.data ?? []) as unknown as MonthRow[]
  const error = statRes.error?.message ?? monthRes.error?.message ?? null

  const monthLabel = new Intl.DateTimeFormat(`${locale}-BE`, { month: 'short' })
  const series = months.map((m) => ({
    label: monthLabel.format(new Date(m.month)).replace('.', ''),
    entries: m.entries,
    tournaments: m.tournaments,
    club: m.club_cents,
  }))

  const base = `/c/${slug}/statistieken`
  const nothing = !s || s.tournaments === 0

  return (
    <Page width="xl">
      <PageHeader overline={`${club.name} · ${label}`} title={t('stats.title')} logoUrl={club.logo_url} />
      <ClubNav slug={slug} active="stats" canManage t={t} locale={locale} account={accountEmail} />

      <div className="flex flex-wrap items-center gap-0.5 self-start rounded-[var(--radius)] border border-[var(--line)] p-0.5">
        {[
          { href: `${base}?p=year`, label: t('stats.thisYear'), on: mode === 'year' },
          { href: `${base}?p=month`, label: t('stats.thisMonth'), on: mode === 'month' },
          { href: `${base}?p=all`, label: t('stats.allTime'), on: mode === 'all' },
          {
            href: `${base}?p=custom&from=${customFrom}&to=${customTo}`,
            label: t('stats.custom'),
            on: mode === 'custom',
          },
        ].map((i) => (
          <Link
            key={i.href}
            href={i.href}
            className={`rounded-[calc(var(--radius)-2px)] px-3 py-1.5 text-sm transition ${
              i.on
                ? 'bg-[var(--brand)] font-medium text-[var(--on-brand)]'
                : 'text-[var(--text-muted)] hover:bg-[var(--surface-hover)] hover:text-[var(--text)]'
            }`}
          >
            {i.label}
          </Link>
        ))}
      </div>

      {/* Een gewoon GET-formulier: geen JavaScript nodig, en de periode staat
          daarna in de URL zodat je hem kan bewaren of doorsturen. */}
      {mode === 'custom' && (
        <form method="get" action={base} className="flex flex-wrap items-end gap-3">
          <input type="hidden" name="p" value="custom" />
          <label className="flex flex-col gap-1 text-sm">
            <span className="text-[var(--text-faint)]">{t('stats.from')}</span>
            <input
              type="date"
              name="from"
              defaultValue={customFrom}
              className="rounded-[var(--radius)] border border-[var(--line)] bg-[var(--surface)] px-3 py-2 text-sm outline-none focus:border-[var(--brand)]"
            />
          </label>
          <label className="flex flex-col gap-1 text-sm">
            <span className="text-[var(--text-faint)]">{t('stats.to')}</span>
            <input
              type="date"
              name="to"
              defaultValue={customTo}
              className="rounded-[var(--radius)] border border-[var(--line)] bg-[var(--surface)] px-3 py-2 text-sm outline-none focus:border-[var(--brand)]"
            />
          </label>
          <button
            type="submit"
            className="rounded-[var(--radius)] bg-[var(--brand)] px-4 py-2 text-sm font-medium text-[var(--on-brand)] transition hover:brightness-110"
          >
            {t('stats.apply')}
          </button>
        </form>
      )}

      {error && <Notice tone="error">{error}</Notice>}

      {nothing ? (
        <EmptyState title={t('stats.nothing')}>{t('stats.nothingBody')}</EmptyState>
      ) : (
        <>
          {/* ----------------------------------------------------- de zaal */}
          <section>
            <SectionTitle>{t('stats.tournaments')}</SectionTitle>
            <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-5">
              <Big label={t('stats.tournaments')} value={String(s.tournaments)} accent />
              <Big label={t('stats.entries')} value={String(s.entries)} />
              <Big label={t('stats.avgEntries')} value={String(s.avg_entries)} />
              <Big label={t('stats.biggestField')} value={String(s.biggest_field)} />
              <Big
                label={t('stats.avgDuration')}
                value={s.avg_minutes > 0
                  ? `${Math.floor(s.avg_minutes / 60)}u${String(s.avg_minutes % 60).padStart(2, '0')}`
                  : '—'}
              />
            </div>
          </section>

          {/* ---------------------------------------------------- de mensen */}
          <section>
            <SectionTitle>{t('members.title')}</SectionTitle>
            <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
              <Big label={t('stats.uniquePlayers')} value={String(s.unique_players)} accent />
              <Big label={t('stats.newPlayers')} value={String(s.new_players)} />
              <Big
                label={t('stats.prizePool')}
                value={formatMoney(s.prize_cents, club.currency)}
              />
              <Big
                label={t('stats.clubIncome')}
                value={formatMoney(s.club_cents, club.currency)}
                accent
              />
            </div>
            {s.bounty_cents > 0 && (
              <p className="mt-2 text-xs text-[var(--text-faint)]">
                {t('stats.bounties')}: {formatMoney(s.bounty_cents, club.currency)}
              </p>
            )}
          </section>

          {/* ------------------------------------------------------ verloop */}
          <section>
            <SectionTitle>{t('stats.perMonth')} · {t('stats.last12')}</SectionTitle>
            <div className="grid gap-4 lg:grid-cols-2">
              <Card>
                <p className="mb-3 text-xs uppercase tracking-widest text-[var(--text-faint)]">
                  {t('stats.entries')}
                </p>
                <BarChart data={series.map((m) => ({ label: m.label, value: m.entries }))} />
              </Card>
              <Card>
                <p className="mb-3 text-xs uppercase tracking-widest text-[var(--text-faint)]">
                  {t('stats.clubIncome')}
                </p>
                <BarChart
                  data={series.map((m) => ({ label: m.label, value: m.club }))}
                  format={(v) => formatMoney(v, club.currency)}
                  accent="var(--gold, var(--brand))"
                />
              </Card>
            </div>
            <p className="mt-2 text-xs text-[var(--text-faint)]">{t('stats.onlyFinished')}</p>
          </section>

        </>
      )}
    </Page>
  )
}

function Big({ label, value, accent }: { label: string; value: string; accent?: boolean }) {
  return (
    <div
      className="rounded-[var(--radius-lg)] border p-4"
      style={{
        borderColor: accent ? 'color-mix(in oklab, var(--brand) 35%, transparent)' : 'var(--line)',
        background: accent ? 'color-mix(in oklab, var(--brand) 7%, transparent)' : undefined,
      }}
    >
      <p className="truncate text-xs uppercase tracking-widest text-[var(--text-faint)]">{label}</p>
      <p
        className="tnum mt-1 text-2xl font-semibold"
        style={accent ? { color: 'var(--brand)' } : undefined}
      >
        {value}
      </p>
    </div>
  )
}
