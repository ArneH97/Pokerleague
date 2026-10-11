import Image from 'next/image'
import { notFound } from 'next/navigation'
import { PageBody } from '@/components/public/PageBody'
import { PublicShell } from '@/components/public/PublicShell'
import { getClub } from '@/lib/club'
import { translator, type Locale } from '@/lib/i18n/dictionaries'
import { clubLocale, visitorLocale } from '@/lib/i18n/server'
import { getPublicPage } from '@/lib/publicClub'

/**
 * Een eigen pagina van de club: een reglement, huisregels, een uitleg.
 *
 * Open, zonder account. Een reglement waar je eerst voor moet aanmelden is
 * geen reglement maar een geheim, en dit is precies het soort tekst dat
 * iemand doorstuurt naar een speler die nog niet bij de club is.
 */
export async function generateMetadata({ params }: PageProps<'/c/[club]/p/[pagina]'>) {
  const { club: slug, pagina } = await params
  const club = await getClub(slug)
  if (!club) return {}
  const locale = (await visitorLocale()) ?? (await clubLocale(club.locale))
  const page = await getPublicPage(slug, pagina, locale)
  return {
    title: page ? `${page.title} · ${club.name}` : club.name,
  }
}

export default async function Page_({ params }: PageProps<'/c/[club]/p/[pagina]'>) {
  const { club: slug, pagina } = await params
  const club = await getClub(slug)
  if (!club) notFound()

  const locale: Locale = (await visitorLocale()) ?? (await clubLocale(club.locale))
  const t = translator(locale)
  const page = await getPublicPage(slug, pagina, locale)
  if (!page) notFound()

  const bijgewerkt = new Intl.DateTimeFormat(`${locale}-BE`, {
    day: 'numeric', month: 'long', year: 'numeric', timeZone: club.timezone,
  }).format(new Date(page.updated_at))

  return (
    <PublicShell club={club} locale={locale}>
      <article>
        {page.image_url && (
          // De affiche bovenaan. Begrensd en gecentreerd: een affiche is
          // staand, en op een monitor zou ze anders tot bijna tweeduizend
          // pixels hoog uitgroeien — dan scrol je drie schermen voor je bij
          // de eerste regel tekst bent.
          //
          // `unoptimized` omdat dit een adres is dat de club zelf invult:
          // Next kan geen domeinen vooraf toestaan die hij nog niet kent.
          <div className="mx-auto mb-6 max-w-[26rem] overflow-hidden rounded-3xl border border-[var(--line)]">
            <Image
              src={page.image_url}
              alt=""
              width={1200}
              height={1600}
              unoptimized
              className="h-auto w-full"
            />
          </div>
        )}

        <header>
          {page.season_name && (
            <p className="text-xs uppercase tracking-[0.2em] text-[var(--text-faint)]">
              {page.season_name}
            </p>
          )}
          <h1 className="mt-1 text-2xl font-semibold tracking-tight sm:text-3xl">
            {page.title}
          </h1>
        </header>

        {/* Krijgt de bezoeker een andere taal dan hij koos, dan hoort hij dat
            te weten. Anders lijkt het alsof de club Nederlands terugschrijft
            tegen een Franstalige. */}
        {page.locale !== locale && (
          <p className="mt-3 rounded-[var(--radius)] border border-[var(--line)] px-3 py-2 text-xs text-[var(--text-faint)]">
            {t('page.otherLocale').replace('{taal}', t(`lang.${page.locale}` as 'lang.nl'))}
          </p>
        )}

        <div className="mt-6">
          <PageBody body={page.body} />
        </div>

        <p className="mt-8 text-xs text-[var(--text-faint)]">
          {t('page.updated').replace('{datum}', bijgewerkt)}
        </p>
      </article>
    </PublicShell>
  )
}
