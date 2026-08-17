import { notFound, redirect } from 'next/navigation'
import { ButtonLink, Card, Notice, Page, PageHeader, SectionTitle } from '@/components/ui'
import { getClub, getClubRole } from '@/lib/club'
import { isLocale, translator } from '@/lib/i18n/dictionaries'
import { createClient } from '@/lib/supabase/server'
import { formatMoney } from '@/lib/types'

/**
 * De uitslag van één tornooi.
 *
 * Dit is het scherm dat na elke avond bekeken wordt, en het rekent zelf
 * niets uit. Prijzengeld en punten staan al in tournament_results, gezet door
 * finalize_tournament op het moment van afsluiten. Dat is bewust: een uitslag
 * die je bij elk bezoek opnieuw berekent, verandert zodra iemand het
 * puntensysteem of de prijzenverdeling aanpast — en dan klopt de avond van
 * vorige maand ineens niet meer met wat er die avond is uitbetaald.
 *
 * De controle onderaan is er om dezelfde reden: uitbetaald hoort exact gelijk
 * te zijn aan de pot. Wijkt het af, dan wil je dat zien en niet ontdekken
 * wanneer er iemand aan de kassa staat.
 */

interface ResultRow {
  position: number
  prize_cents: number
  bounty_cents: number
  points: number
  knockouts: number
  entries_total: number
  players: { display_name: string; username: string | null } | null
}

interface TourRow {
  id: string
  name: string
  scheduled_at: string
  status: string
  buyin_cents: number
  fee_cents: number
  ended_at: string | null
}

export default async function Page_({ params }: PageProps<'/c/[club]/tornooien/[id]'>) {
  const { club: slug, id } = await params
  const club = await getClub(slug)
  if (!club) notFound()

  const supabase = await createClient()
  const { data: claims } = await supabase.auth.getClaims()
  if (!claims?.claims) {
    redirect(`/c/${slug}/login?next=${encodeURIComponent(`/c/${slug}/tornooien/${id}`)}`)
  }

  const role = await getClubRole(club.id)
  const t = translator(isLocale(club.locale) ? club.locale : 'nl')

  const [tourRes, resultRes, potRes] = await Promise.all([
    supabase
      .from('tournaments')
      .select('id,name,scheduled_at,status,buyin_cents,fee_cents,ended_at')
      .eq('id', id)
      .maybeSingle<TourRow>(),
    supabase
      .from('tournament_results')
      .select('position,prize_cents,bounty_cents,points,knockouts,entries_total,players(display_name,username)')
      .eq('tournament_id', id)
      .order('position')
      .overrideTypes<ResultRow[]>(),
    // Alleen staf mag het geldregister lezen; een speler krijgt hier netjes
    // een lege lijst en ziet dus geen clubinkomsten.
    supabase
      .from('buyins')
      .select('amount_cents,fee_cents')
      .eq('tournament_id', id)
      .eq('is_void', false)
      .overrideTypes<{ amount_cents: number; fee_cents: number }[]>(),
  ])

  const tour = tourRes.data
  if (!tour) notFound()

  const results = resultRes.data ?? []
  const pot = (potRes.data ?? []).reduce((n, b) => n + b.amount_cents, 0)
  const clubShare = (potRes.data ?? []).reduce((n, b) => n + b.fee_cents, 0)
  const paid = results.reduce((n, r) => n + r.prize_cents, 0)
  const inTheMoney = results.filter((r) => r.prize_cents > 0).length
  const canSeeMoney = role !== null && ['owner', 'admin', 'floor'].includes(role)

  const fmt = new Intl.DateTimeFormat(`${club.locale}-BE`, {
    weekday: 'long', day: 'numeric', month: 'long', year: 'numeric',
    hour: '2-digit', minute: '2-digit', timeZone: club.timezone,
  })

  return (
    <Page>
      <PageHeader
        backHref={`/c/${slug}`}
        backLabel={t('result.backToClub')}
        overline={t('result.title')}
        title={tour.name}
        subtitle={fmt.format(new Date(tour.ended_at ?? tour.scheduled_at))}
        logoUrl={club.logo_url}
      />

      {results.length === 0 ? (
        <Notice tone="warn">
          <span className="font-medium">{t('result.notFinished')}</span>
          <br />
          {t('result.notFinishedBody')}
        </Notice>
      ) : (
        <>
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
            <Stat label={t('result.entries')} value={String(results[0]?.entries_total ?? results.length)} />
            <Stat label={t('result.inTheMoney')} value={String(inTheMoney)} />
            {canSeeMoney && (
              <>
                <Stat label={t('result.prizePool')} value={formatMoney(pot, club.currency)} />
                <Stat label={t('result.clubShare')} value={formatMoney(clubShare, club.currency)} />
              </>
            )}
          </div>

          {canSeeMoney && paid !== pot && (
            <Notice tone="warn">{t('result.checkTotals')}</Notice>
          )}

          <section>
            <SectionTitle>{t('result.title')}</SectionTitle>
            <Card padded={false} className="overflow-hidden">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-[var(--line)] text-left text-xs uppercase tracking-widest text-[var(--text-faint)]">
                    <th className="px-4 py-2.5 font-medium">{t('result.position')}</th>
                    <th className="px-4 py-2.5 font-medium">{t('result.player')}</th>
                    <th className="px-4 py-2.5 text-right font-medium">{t('result.knockouts')}</th>
                    <th className="px-4 py-2.5 text-right font-medium">{t('result.points')}</th>
                    <th className="px-4 py-2.5 text-right font-medium">{t('result.prize')}</th>
                  </tr>
                </thead>
                <tbody>
                  {results.map((r) => (
                    <tr
                      key={r.position}
                      className="border-b border-[var(--line)] last:border-0"
                    >
                      <td className="tnum px-4 py-2.5 font-semibold text-[var(--text-faint)]">
                        {/* De top drie krijgt de clubkleur. Meer opsmuk hoeft
                            niet: wie won weet iedereen die avond nog. */}
                        <span style={r.position <= 3 ? { color: 'var(--brand)' } : undefined}>
                          {r.position}
                        </span>
                      </td>
                      <td className="px-4 py-2.5">
                        <span className="font-medium">{r.players?.display_name ?? '—'}</span>
                        {r.players?.username && (
                          <span className="ml-2 text-xs text-[var(--text-faint)]">
                            @{r.players.username}
                          </span>
                        )}
                      </td>
                      <td className="tnum px-4 py-2.5 text-right text-[var(--text-muted)]">
                        {r.knockouts > 0 ? r.knockouts : '—'}
                      </td>
                      <td className="tnum px-4 py-2.5 text-right text-[var(--text-muted)]">
                        {Number(r.points).toLocaleString('nl-BE', { maximumFractionDigits: 2 })}
                      </td>
                      <td className="tnum px-4 py-2.5 text-right font-medium">
                        {r.prize_cents > 0 ? formatMoney(r.prize_cents, club.currency) : '—'}
                      </td>
                    </tr>
                  ))}
                </tbody>
                {canSeeMoney && (
                  <tfoot>
                    <tr className="bg-[var(--surface-2)] text-[var(--text-muted)]">
                      <td className="px-4 py-2.5" colSpan={4}>{t('result.paidOut')}</td>
                      <td className="tnum px-4 py-2.5 text-right font-semibold">
                        {formatMoney(paid, club.currency)}
                      </td>
                    </tr>
                  </tfoot>
                )}
              </table>
            </Card>
          </section>
        </>
      )}

      <div className="flex flex-wrap gap-2">
        <ButtonLink href={`/c/${slug}/klassement`}>{t('standings.view')}</ButtonLink>
        {tour.status !== 'finished' && role && (
          <ButtonLink variant="brand" href={`/c/${slug}/floor/${id}`}>{t('club.floor')}</ButtonLink>
        )}
      </div>
    </Page>
  )
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-[var(--radius)] border border-[var(--line)] p-4">
      <p className="text-xs uppercase tracking-widest text-[var(--text-faint)]">{label}</p>
      <p className="tnum mt-1 text-2xl font-semibold">{value}</p>
    </div>
  )
}
