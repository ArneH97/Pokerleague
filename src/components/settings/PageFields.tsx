import { Field, inputClass } from '@/components/ui'
import type { T } from '@/lib/i18n/dictionaries'

export interface PageRow {
  id: string
  slug: string
  season_id: string | null
  is_published: boolean
  sort_order: number
  image_url: string | null
  title_nl: string | null; body_nl: string | null
  title_fr: string | null; body_fr: string | null
  title_en: string | null; body_en: string | null
}

/**
 * De velden van één clubpagina.
 *
 * Drie talen onder elkaar en niet in tabbladen. Tabbladen verbergen dat er
 * twee talen leeg zijn, en dat is precies wat je wil zien: een reglement dat
 * alleen in het Nederlands bestaat is half af, en dan hoort het scherm dat te
 * laten merken in plaats van het weg te klikken.
 *
 * De tekstvakken zijn groot. Hier wordt een reglement in geplakt, geen
 * onderschrift, en een vakje van drie regels maakt van plakken en nalezen een
 * worsteling.
 */
export function PageFields({
  page, seasons, t,
}: {
  page: PageRow | null
  seasons: { id: string; name: string }[]
  t: T
}) {
  const talen = [
    { code: 'nl', naam: t('lang.nl'), titel: page?.title_nl ?? '', body: page?.body_nl ?? '' },
    { code: 'fr', naam: t('lang.fr'), titel: page?.title_fr ?? '', body: page?.body_fr ?? '' },
    { code: 'en', naam: t('lang.en'), titel: page?.title_en ?? '', body: page?.body_en ?? '' },
  ]

  return (
    <>
      <div className="grid gap-4 sm:grid-cols-2">
        <Field label={t('set.pageSlug')} hint={t('set.pageSlugHint')}>
          <input
            name="page_slug"
            defaultValue={page?.slug ?? ''}
            placeholder="reglement"
            className={inputClass}
            required
          />
        </Field>
        <Field label={t('set.pageSeason')} hint={t('set.pageSeasonHint')}>
          <select name="season_id" defaultValue={page?.season_id ?? ''} className={inputClass}>
            <option value="">{t('settings.assignNone')}</option>
            {seasons.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
          </select>
        </Field>
        <Field label={t('set.pageImage')} hint={t('set.pageImageHint')}>
          <input
            name="image_url"
            defaultValue={page?.image_url ?? ''}
            placeholder="https://…"
            className={inputClass}
          />
        </Field>
        <Field label={t('set.pageOrder')} hint={t('set.pageOrderHint')}>
          <input
            type="number" step="1" name="sort_order"
            defaultValue={page?.sort_order ?? 0}
            className={inputClass}
          />
        </Field>
      </div>

      <label className="flex items-center gap-2.5">
        <input
          type="checkbox"
          name="is_published"
          defaultChecked={page?.is_published ?? false}
          className="size-4"
        />
        <span className="text-sm">{t('set.pagePublished')}</span>
      </label>

      {talen.map((taal) => (
        <div key={taal.code} className="rounded-[var(--radius)] border border-[var(--line)] p-3.5">
          <p className="text-xs uppercase tracking-[0.18em] text-[var(--text-faint)]">
            {taal.naam}
          </p>
          <div className="mt-3 space-y-3">
            <Field label={t('settings.name')}>
              <input
                name={`title_${taal.code}`}
                defaultValue={taal.titel}
                className={inputClass}
              />
            </Field>
            <Field label={t('set.pageBody')} hint={t('set.pageBodyHint')}>
              <textarea
                name={`body_${taal.code}`}
                defaultValue={taal.body}
                rows={10}
                spellCheck={false}
                className={`${inputClass} font-mono text-xs leading-relaxed`}
              />
            </Field>
          </div>
        </div>
      ))}
    </>
  )
}
