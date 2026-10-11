import Link from 'next/link'
import { notFound } from 'next/navigation'
import { PointsExplainer, weightLabel } from '@/components/public/PointsExplainer'
import { AccountWall } from '@/components/public/AccountWall'
import { PublicShell } from '@/components/public/PublicShell'
import { getClub } from '@/lib/club'
import { translator } from '@/lib/i18n/dictionaries'
import { clubLocale, visitorLocale } from '@/lib/i18n/server'
import {
  getPublicPlayerSeason, getPublicSeasonRules, getPublicSeasonStandings,
} from '@/lib/publicClub'
import { createClient } from '@/lib/supabase/server'

/**
 * Hoe één speler aan zijn punten kwam.
 *
 * Een klassement met een prijs aan het eind roept elke speelavond dezelfde
 * vraag op: waarom heeft hij er meer dan ik. Zolang het antwoord "dat rekent
 * het systeem uit" is, is het klassement iets dat gebeurt in plaats van iets
 * waar je voor speelt.
 *
 * Dus staan hier zijn avonden, van best naar slechtst, met een streep onder
 * de laatste die meetelt. Die streep wordt door de database getrokken — het
 * scherm sorteert niet zelf — zodat wat je hier ziet optelt tot exact wat er
 * in de stand staat.
 *
 * Zonder prijzengeld, net als de rest van de publieke kant: wat iemand won is
 * een zaak tussen hem en de club.
 */
export default async function Page_({ params }: PageProps<'/c/[club]/klassement/[speler]'>) {
  const { club: slug, speler } = await params
  const club = await getClub(slug)
  if (!club) notFound()

  // Dezelfde deur als het klassement zelf: een lijst van wie wanneer speelde
  // hoort achter een account.
  const supabase = await createClient()
  const { data: claims } = await supabase.auth.getClaims()
  const locale = (await visitorLocale()) ?? (await clubLocale(club.locale))
  const t = translator(locale)

  if (!claims?.claims) {
    return (
      <PublicShell club={club} locale={locale} active="standings" signedIn={false}>
        <AccountWall t={t} next={`/c/${club.slug}/klassement/${speler}`} />
      </PublicShell>
    )
  }

  const [rijen, rules, stand] = await Promise.all([
    getPublicPlayerSeason(slug, speler),
    getPublicSeasonRules(slug),
    getPublicSeasonStandings(slug),
  ])

  const naam = rijen[0]?.player_name ?? null
  const mij = stand.find((r) => r.player_id === speler) ?? null
  const plaats = stand.findIndex((r) => r.player_id === speler) + 1

  const tellend = rijen.filter((r) => r.counted)
  const totaal = tellend.reduce((s, r) => s + Number(r.points), 0)

  const getal = (n: number) => n.toLocaleString(`${locale}-BE`)
  const datum = new Intl.DateTimeFormat(`${locale}-BE`, {
    day: 'numeric', month: 'short', year: '2-digit', timeZone: club.timezone,
  })
  const geld = (cents: number) =>
    new Intl.NumberFormat(`${locale}-BE`, {
      style: 'currency', currency: club.currency, maximumFractionDigits: 0,
    }).format(cents / 100)

  const base = `/c/${slug}/klassement`

  return (
    <PublicShell club={club} locale={locale} active="standings">
      <Link
        href={base}
        className="inline-block text-sm text-[var(--text-muted)] underline-offset-4 hover:text-[var(--text)] hover:underline"
      >
        ← {t('bd.back')}
      </Link>

      <header className="mt-4">
        <h1 className="text-2xl font-semibold tracking-tight">{naam ?? '—'}</h1>
        {rules && (
          <p className="text-sm text-[var(--text-faint)]">{rules.season_name}</p>
        )}
      </header>

      {rijen.length === 0 ? (
        <p className="mt-6 rounded-3xl border border-[var(--line)] bg-[var(--surface)] p-6 text-[var(--text-muted)]">
          {t('bd.empty')}
        </p>
      ) : (
        <>
          {/* De samenvatting bovenaan: het getal waar hij voor kwam kijken,
              met eronder wat het betekent. */}
          <section className="mt-5 flex flex-wrap items-end gap-x-8 gap-y-3 rounded-[var(--radius-lg,1rem)] border border-[var(--line)] bg-[var(--surface)] p-4 sm:p-5">
            <div>
              <p className="text-xs uppercase tracking-[0.18em] text-[var(--text-faint)]">
                {t('bd.total')}
              </p>
              <p className="tnum text-3xl font-semibold">
                {getal(Math.round(totaal))}
                <span className="ml-1.5 text-sm font-normal text-[var(--text-faint)]">
                  {t('pub.pts')}
                </span>
              </p>
            </div>

            {plaats > 0 && (
              <p className="tnum text-base font-medium text-[var(--brand)]">
                {t('bd.rank').replace('{n}', String(plaats))}
              </p>
            )}

            <p className="text-sm leading-relaxed text-[var(--text-muted)]">
              {rules?.count_best_n && rijen.length > tellend.length
                ? t('bd.summary')
                  .replace('{n}', String(tellend.length))
                  .replace('{m}', String(rijen.length))
                : t('bd.allCount').replace('{m}', String(rijen.length))}
              {mij && mij.qualified === false && mij.min_required > 0 && (
                <>
                  {' '}
                  {t('standings.toGo').replace(
                    '{n}', String(mij.min_required - mij.tournaments),
                  )}
                  .
                </>
              )}
            </p>
          </section>

          {/* De avonden zelf. Links de plaats, in het midden welke avond en
              waar het getal vandaan komt, rechts de punten. Wat afvalt staat
              er gewoon bij, gedempt: weten wát je laat vallen hoort bij het
              begrijpen van een beste-N-regel. */}
          <ul className="mt-4 overflow-hidden rounded-[var(--radius-lg,1rem)] border border-[var(--line)] bg-[var(--surface)]">
            {rijen.map((r, i) => {
              const weging = rules ? weightLabel(rules, r.stake_cents, locale) : null
              const eersteAfgestreepte = r.counted === false && rijen[i - 1]?.counted === true
              return (
                <li
                  key={r.tournament_id}
                  className={`flex items-center gap-3 border-b border-[var(--line)] px-3 py-3 last:border-0 sm:px-4 ${
                    r.counted ? '' : 'opacity-55'
                  } ${eersteAfgestreepte ? 'border-t-2 border-t-[var(--line-strong)]' : ''}`}
                >
                  <span
                    aria-hidden
                    className={`tnum flex size-9 shrink-0 items-center justify-center rounded-full text-sm font-semibold ${
                      r.place === 1
                        ? 'bg-[color-mix(in_oklab,var(--brand)_18%,transparent)] text-[var(--brand)]'
                        : 'bg-[var(--surface-2)] text-[var(--text-muted)]'
                    }`}
                  >
                    {r.place}
                  </span>

                  <span className="min-w-0 flex-1">
                    <span className="block truncate font-medium">{r.tournament}</span>
                    <span className="tnum block truncate text-xs text-[var(--text-faint)]">
                      {datum.format(new Date(r.played_on))}
                      {' · '}
                      {t('bd.field').replace('{n}', String(r.entries))}
                      {weging && <> · {t('bd.stake').replace('{n}', geld(r.stake_cents))} {weging}</>}
                      {r.knockouts > 0 && rules && rules.bonus_per_ko > 0 && (
                        <> · {r.knockouts} {t('standings.knockouts')}</>
                      )}
                    </span>
                  </span>

                  <span className="shrink-0 text-right">
                    <span className="tnum block text-base font-semibold">
                      {getal(Math.round(Number(r.points)))}
                    </span>
                    {!r.counted && (
                      <span className="block text-[0.65rem] text-[var(--text-faint)]">
                        {t('bd.dropped')}
                      </span>
                    )}
                  </span>
                </li>
              )
            })}
          </ul>
        </>
      )}

      {rules && (
        <PointsExplainer rules={rules} locale={locale} t={t} currency={club.currency} />
      )}
    </PublicShell>
  )
}
