'use client'

import { useState } from 'react'
import Link from 'next/link'
import { inputClass } from '@/components/ui'
import { useT } from '@/lib/i18n/context'
import { rsvp, type RsvpResult } from '@/lib/rsvpActions'

/**
 * "Ik kom." Vier velden.
 *
 * Dit formulier staat aan het eind van een affiche en aan het begin van alles
 * wat daarna komt, en het heeft maar één taak: iemand die op zijn telefoon een
 * QR-code scande binnen twintig seconden op de lijst krijgen. Elk veld dat
 * hier bij komt, kost inschrijvingen.
 *
 * Vandaar geen wachtwoord en geen bevestigingsmail. Naam, adres, geboortedatum
 * — dat laatste omdat poker in België 18+ is en de club dat aan de deur toch
 * moet vaststellen; dan liever nu dan wanneer iemand er al staat.
 *
 * **Wat er na "ingeschreven" komt is bewust een aanbod en geen stap.** Zijn
 * plaats staat al vast. Het account erbij is voor hém interessant, niet voor
 * ons, en dus staat het er als iets dat hij mag doen en niet als iets dat nog
 * moet.
 */
export function RsvpForm({
  tournamentId, clubSlug, clubName, bonusStack,
}: {
  tournamentId: string
  clubSlug: string
  clubName: string
  bonusStack: number
}) {
  const t = useT()
  const [firstName, setFirstName] = useState('')
  const [lastName, setLastName] = useState('')
  const [email, setEmail] = useState('')
  const [birthdate, setBirthdate] = useState('')
  const [busy, setBusy] = useState(false)
  const [state, setState] = useState<RsvpResult | null>(null)

  const done = state === 'ok' || state === 'already'

  async function submit(e: React.FormEvent) {
    e.preventDefault()
    setBusy(true)
    setState(null)
    const r = await rsvp(tournamentId, { firstName, lastName, email, birthdate })
    setState(r)
    setBusy(false)
  }

  if (done) {
    return (
      <div className="rounded-[var(--radius-lg)] border border-[var(--line)] bg-[var(--surface)] p-6 text-center">
        <p className="text-xs font-semibold uppercase tracking-[0.2em] text-[var(--brand)]">
          {state === 'already' ? t('rsvp.alreadyTag') : t('rsvp.doneTag')}
        </p>
        <h2 className="mt-2 text-xl font-semibold">
          {(state === 'already' ? t('rsvp.alreadyTitle') : t('rsvp.doneTitle'))
            .replace('{name}', firstName || lastName)}
        </h2>
        <p className="mx-auto mt-2 max-w-sm text-sm leading-relaxed text-[var(--text-muted)]">
          {t('rsvp.doneBody').replace('{club}', clubName)}
          {bonusStack > 0 && ` ${t('rsvp.doneBonus').replace('{n}', bonusStack.toLocaleString('nl-BE'))}`}
        </p>

        <div className="mt-6 border-t border-[var(--line)] pt-5">
          <p className="text-sm font-medium">{t('rsvp.accountTitle')}</p>
          <p className="mx-auto mt-1.5 max-w-sm text-sm leading-relaxed text-[var(--text-muted)]">
            {t('rsvp.accountBody')}
          </p>
          <Link
            href={`/registreren?club=${clubSlug}`}
            className="mt-4 inline-block rounded-full bg-[var(--brand)] px-6 py-3 font-medium text-[var(--on-brand)] transition hover:brightness-110"
          >
            {t('rsvp.accountCta')} →
          </Link>
          <p className="mt-3 text-xs text-[var(--text-faint)]">{t('rsvp.accountLater')}</p>
        </div>
      </div>
    )
  }

  return (
    <form
      onSubmit={submit}
      className="rounded-[var(--radius-lg)] border border-[var(--line)] bg-[var(--surface)] p-5 sm:p-6"
    >
      <h2 className="text-lg font-semibold">{t('rsvp.formTitle')}</h2>
      <p className="mt-1 text-sm text-[var(--text-muted)]">{t('rsvp.formLede')}</p>

      <div className="mt-4 grid gap-3 sm:grid-cols-2">
        <label className="block">
          <span className="mb-1.5 block text-sm text-[var(--text-muted)]">{t('rsvp.firstName')}</span>
          <input
            className={inputClass} value={firstName} autoComplete="given-name"
            onChange={(e) => setFirstName(e.target.value)} required
          />
        </label>
        <label className="block">
          <span className="mb-1.5 block text-sm text-[var(--text-muted)]">{t('rsvp.lastName')}</span>
          <input
            className={inputClass} value={lastName} autoComplete="family-name"
            onChange={(e) => setLastName(e.target.value)} required
          />
        </label>
      </div>

      <label className="mt-3 block">
        <span className="mb-1.5 block text-sm text-[var(--text-muted)]">{t('common.email')}</span>
        <input
          className={inputClass} type="email" value={email} autoComplete="email"
          inputMode="email" onChange={(e) => setEmail(e.target.value)} required
        />
      </label>

      <label className="mt-3 block">
        <span className="mb-1.5 block text-sm text-[var(--text-muted)]">{t('rsvp.birthdate')}</span>
        <input
          className={inputClass} type="date" value={birthdate}
          onChange={(e) => setBirthdate(e.target.value)} required
        />
        <span className="mt-1.5 block text-xs text-[var(--text-faint)]">{t('rsvp.birthdateWhy')}</span>
      </label>

      {state && !done && (
        <p className="mt-4 text-sm text-[var(--danger)]">
          {t(
            state === 'too_young' ? 'rsvp.errTooYoung'
              : state === 'bad_email' ? 'rsvp.errEmail'
                : state === 'bad_name' ? 'rsvp.errName'
                  : state === 'closed' ? 'rsvp.errClosed'
                    : state === 'full' ? 'rsvp.errFull'
                      : 'common.error',
          )}
        </p>
      )}

      <button
        disabled={busy}
        className="mt-5 w-full rounded-full bg-[var(--brand)] px-6 py-3.5 font-medium text-[var(--on-brand)] transition hover:brightness-110 disabled:opacity-50"
      >
        {busy ? t('common.busy') : t('rsvp.submit')}
      </button>

      <p className="mt-3 text-center text-xs leading-relaxed text-[var(--text-faint)]">
        {t('rsvp.privacy').replace('{club}', clubName)}
      </p>
    </form>
  )
}
