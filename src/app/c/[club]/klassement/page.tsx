import { notFound, redirect } from 'next/navigation'
import { Card, EmptyState, Notice, Page, PageHeader, SectionTitle } from '@/components/ui'
import { getClub, getClubRole } from '@/lib/club'
import { isLocale, translator } from '@/lib/i18n/dictionaries'
import { createClient } from '@/lib/supabase/server'
import { formatMoney } from '@/lib/types'

/**
 * Seizoensklassement van de club.
 *
 * Het rekenwerk zit in season_standings() in de database en niet hier. Dat is
 * geen detail: "tel alleen je beste tien resultaten" en "minstens drie
 * tornooien gespeeld" zijn regels per club, en die hoor je op één plek te
 * hebben staan. Zou de browser het uitrekenen, dan moet elk scherm — en
 * straks ook de spelersapp — diezelfde regels opnieuw kennen.
 */

interface Standing {
  player_id: string
  display_name: string
  tournaments: number
  counted: number
  points: number
  best_position: number
  cashes: number
  total_prize: number
  knockouts: number
}

interface Season {
  id: string
  name: string
  starts_on: string
  ends_on: string | null
}

export default async function Page_({ params }: PageProps<'/c/[club]/klassement'>) {
  const { club: slug } = await params
  const club = await getClub(slug)
  if (!club) notFound()

  const supabase = await createClient()
  const { data: claims } = await supabase.auth.getClaims()
  if (!claims?.claims) redirect(`/c/${slug}/login?next=/c/${slug}/klassement`)

  await getClubRole(club.id)
  const t = translator(isLocale(club.locale) ? club.locale : 'nl')

  const { data: seasons } = await supabase
    .from('seasons')
    .select('id,name,starts_on,ends_on')
    .eq('club_id', club.id)
    .eq('is_active', true)
    .order('starts_on', { ascending: false })
    .overrideTypes<Season[]>()

  const season = seasons?.[0]

  if (!season) {
    return (
      <Page>
        <PageHeader
          backHref={`/c/${slug}`}
          backLabel={t('result.backToClub')}
          title={t('standings.title')}
          subtitle={club.name}
          logoUrl={club.logo_url}
        />
        <Notice tone="warn">{t('standings.noSeason')}</Notice>
      </Page>
    )
  }

  // overrideTypes weigert hier: de typegenerator kent de vorm van een
  // functie die een tabel teruggeeft niet. Een gewone cast is hier eerlijker
  // dan de generator om de tuin leiden.
  const { data, error } = await supabase.rpc('season_standings', { p_season_id: season.id })
  const rows = (data ?? []) as unknown as Standing[]

  return (
    <Page>
      <PageHeader
        backHref={`/c/${slug}`}
        backLabel={t('result.backToClub')}
        overline={`${t('standings.season')} · ${season.name}`}
        title={t('standings.title')}
        subtitle={club.name}
        logoUrl={club.logo_url}
      />

      {error && <Notice tone="error">{error.message}</Notice>}

      {rows.length === 0 && !error ? (
        <EmptyState title={t('standings.none')}>{t('standings.noneBody')}</EmptyState>
      ) : (
        <section>
          <SectionTitle>{season.name}</SectionTitle>
          <Card padded={false} className="overflow-x-auto">
            <table className="w-full min-w-[40rem] text-sm">
              <thead>
                <tr className="border-b border-[var(--line)] text-left text-xs uppercase tracking-widest text-[var(--text-faint)]">
                  <th className="px-4 py-2.5 font-medium">{t('standings.rank')}</th>
                  <th className="px-4 py-2.5 font-medium">{t('standings.player')}</th>
                  <th className="px-4 py-2.5 text-right font-medium">{t('standings.points')}</th>
                  <th className="px-4 py-2.5 text-right font-medium">{t('standings.played')}</th>
                  <th className="px-4 py-2.5 text-right font-medium">{t('standings.counted')}</th>
                  <th className="px-4 py-2.5 text-right font-medium">{t('standings.best')}</th>
                  <th className="px-4 py-2.5 text-right font-medium">{t('standings.cashes')}</th>
                  <th className="px-4 py-2.5 text-right font-medium">{t('standings.knockouts')}</th>
                  <th className="px-4 py-2.5 text-right font-medium">{t('standings.prize')}</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((r, i) => (
                  <tr key={r.player_id} className="border-b border-[var(--line)] last:border-0">
                    <td className="tnum px-4 py-2.5 font-semibold text-[var(--text-faint)]">
                      <span style={i < 3 ? { color: 'var(--brand)' } : undefined}>{i + 1}</span>
                    </td>
                    <td className="px-4 py-2.5 font-medium">{r.display_name}</td>
                    <td className="tnum px-4 py-2.5 text-right font-semibold">
                      {Number(r.points).toLocaleString('nl-BE', { maximumFractionDigits: 2 })}
                    </td>
                    <td className="tnum px-4 py-2.5 text-right text-[var(--text-muted)]">{r.tournaments}</td>
                    {/* "Telt mee" is alleen interessant als de club niet alle
                        resultaten laat meetellen; anders staat er twee keer
                        hetzelfde getal en dat leest als een fout. */}
                    <td className="tnum px-4 py-2.5 text-right text-[var(--text-faint)]">
                      {r.counted === r.tournaments ? '—' : r.counted}
                    </td>
                    <td className="tnum px-4 py-2.5 text-right text-[var(--text-muted)]">{r.best_position}</td>
                    <td className="tnum px-4 py-2.5 text-right text-[var(--text-muted)]">{r.cashes}</td>
                    <td className="tnum px-4 py-2.5 text-right text-[var(--text-muted)]">
                      {r.knockouts > 0 ? r.knockouts : '—'}
                    </td>
                    <td className="tnum px-4 py-2.5 text-right">
                      {r.total_prize > 0 ? formatMoney(r.total_prize, club.currency) : '—'}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </Card>
        </section>
      )}
    </Page>
  )
}
