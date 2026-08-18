'use client'

import { useActionState } from 'react'
import { Field, inputClass } from '@/components/ui'
import { savePlayerProfile } from '@/lib/playerActions'
import { useT } from '@/lib/i18n/context'
import { LOCALES, LOCALE_NAMES } from '@/lib/i18n/dictionaries'

/**
 * Wat een speler zelf over zichzelf mag wijzigen.
 *
 * Kort lijstje, en dat is het punt. Zijn naam en gebruikersnaam, en twee
 * vinkjes over wat er publiek van hem te zien is. Geen geboortedatum en geen
 * gemeente: die staan in het profiel omdat de club ze nodig heeft voor het
 * gedoogbeleid, en die hoort ze aan de deur te controleren en niet hier te
 * laten intikken.
 *
 * Het mailadres staat er wel, maar grijs. Dat is de sleutel waarmee zijn
 * profiel aan zijn account hangt en waarmee de floor hem terugvindt; dat laat
 * je niet in een formulierveld veranderen zonder bevestiging via de nieuwe
 * mailbox. Dat komt later, samen met de rest van de accountinstellingen.
 */
export function PlayerProfileForm({
  me,
}: {
  me: {
    first_name: string | null
    last_name: string | null
    username: string | null
    email: string | null
    locale: string
    public_listing: boolean
    public_profile: boolean
  }
}) {
  const t = useT()
  const [state, action, pending] = useActionState(savePlayerProfile, null)

  return (
    <form
      action={action}
      className="rounded-[var(--radius)] border border-[var(--line)] bg-[var(--surface)] p-5 sm:p-6"
    >
      <h2 className="text-lg font-semibold">{t('me.settings')}</h2>

      <div className="mt-5 space-y-4">
        <div className="grid gap-4 sm:grid-cols-2">
          <Field label={t('register.firstName')}>
            <input name="first_name" defaultValue={me.first_name ?? ''} className={inputClass} />
          </Field>
          <Field label={t('register.lastName')}>
            <input name="last_name" defaultValue={me.last_name ?? ''} className={inputClass} />
          </Field>
        </div>

        <Field label={t('register.username')} hint={t('register.usernameHint')}>
          <input
            name="username" defaultValue={me.username ?? ''}
            pattern="[a-zA-Z0-9._-]{3,24}" className={inputClass}
          />
        </Field>

        <Field label={t('common.email')} hint={t('me.emailFixed')}>
          <input value={me.email ?? ''} readOnly disabled className={`${inputClass} opacity-60`} />
        </Field>

        {/* De taal waarin je post krijgt, niet de taal van dit scherm — die
            kies je bovenaan en die geldt alleen voor dit bezoek. Twee
            verschillende dingen die makkelijk door elkaar lopen, vandaar dat
            het er letterlijk bij staat. */}
        <Field label={t('me.mailLanguage')} hint={t('me.mailLanguageHint')}>
          <select name="locale" defaultValue={me.locale} className={inputClass}>
            {LOCALES.map((l) => (
              <option key={l} value={l}>{LOCALE_NAMES[l]}</option>
            ))}
          </select>
        </Field>

        <label className="flex items-start gap-3 rounded-[var(--radius)] border border-[var(--line)] p-3.5">
          <input
            type="checkbox" name="public_listing"
            defaultChecked={me.public_listing} className="mt-0.5 size-4 shrink-0"
          />
          <span>
            <span className="block text-sm font-medium">{t('register.listing')}</span>
            <span className="mt-0.5 block text-xs leading-relaxed text-[var(--text-faint)]">
              {t('register.listingHint')}
            </span>
          </span>
        </label>

        <label className="flex items-start gap-3 rounded-[var(--radius)] border border-[var(--line)] p-3.5">
          <input
            type="checkbox" name="public_profile"
            defaultChecked={me.public_profile} className="mt-0.5 size-4 shrink-0"
          />
          <span>
            <span className="block text-sm font-medium">{t('me.realName')}</span>
            <span className="mt-0.5 block text-xs leading-relaxed text-[var(--text-faint)]">
              {t('me.realNameHint')}
            </span>
          </span>
        </label>
      </div>

      <div className="mt-6 flex flex-wrap items-center gap-3">
        <button
          type="submit"
          disabled={pending}
          className="rounded-[var(--radius)] bg-[var(--brand)] px-4 py-2.5 text-sm font-medium text-[var(--on-brand)] transition hover:brightness-110 disabled:opacity-45"
        >
          {pending ? t('common.saving') : t('common.save')}
        </button>
        {state?.ok === true && <span className="text-sm text-[var(--ok)]">{t('common.saved')}</span>}
        {state?.ok === false && (
          <span className="text-sm text-[var(--danger)]">
            {t(state.error)}
            {state.detail && <span className="opacity-80"> — {state.detail}</span>}
          </span>
        )}
      </div>
    </form>
  )
}
