'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { Card, Field, inputClass } from '@/components/ui'
import { finishOnboarding, saveOnboardingProfile } from '@/lib/onboardingActions'
import { joinClubs } from '@/lib/joinActions'
import { useT } from '@/lib/i18n/context'
import type { JoinableClub } from '@/components/JoinClubs'

/**
 * De eerste vijf minuten.
 *
 * Wie zijn mailadres net bevestigd heeft, kwam vroeger binnen op zijn
 * profielpagina: nul avonden, nul clubs, nul prijzengeld. Technisch juist en
 * menselijk waardeloos — het ziet eruit alsof er iets misging.
 *
 * Vier stappen, en alle vier verdienen ze hun plek:
 *
 *   1. **Wat dit is.** Eén scherm dat het verschil uitlegt tussen het platform
 *      en een club. Zonder dat blijft iemand zich afvragen waarom hij een
 *      account bij "PokerLeague" heeft terwijl hij bij Cutoff speelt.
 *   2. **Waar speel je?** De enige vraag waarvan het antwoord meteen iets
 *      oplevert: zonder clubs is het platform leeg.
 *   3. **Wie ben je?** Naam en gebruikersnaam, plus de toestemming voor
 *      publieke ranglijsten. Die toestemming hoort hier en niet weggestopt in
 *      een instellingenscherm dat niemand opent — het is een keuze, en je
 *      stelt ze vóórdat er iets te tonen valt.
 *   4. **Klaar.**
 *
 * Overslaan mag bij elke stap. Wie iets niet wil invullen, hoort niet vast te
 * zitten in een scherm — hij vindt het later terug op zijn profiel.
 */

export function Onboarding({
  clubs, firstName, lastName, username, publicListing, birthdate, hasConsent,
}: {
  clubs: JoinableClub[]
  firstName: string
  lastName: string
  username: string
  publicListing: boolean
  /** Leeg bij accounts van vóór deze regel. Dan vragen we het hier alsnog. */
  birthdate: string
  hasConsent: boolean
}) {
  const t = useT()
  const router = useRouter()

  const [step, setStep] = useState(0)
  const [busy, setBusy] = useState(false)
  const [picked, setPicked] = useState<Set<string>>(new Set())

  const [first, setFirst] = useState(firstName)
  const [last, setLast] = useState(lastName)
  const [user, setUser] = useState(username)
  const [listing, setListing] = useState(publicListing)
  const [birth, setBirth] = useState(birthdate)
  // Zie RegisterForm voor waarom dit er standaard in staat en het vinkje voor
  // publieke naamsvermelding niet.
  const [consent, setConsent] = useState(true)
  const [error, setError] = useState<string | null>(null)

  // Accounts van vóór 0036 hebben geen geboortedatum en geen toestemming. Die
  // vragen we hier alsnog — dit is het enige scherm dat iedereen doorloopt.
  const askBirth = birthdate === ''
  const askConsent = !hasConsent

  const steps = [t('ob.s1'), t('ob.s2'), t('ob.s3'), t('ob.s4')]

  function toggle(slug: string) {
    setPicked((prev) => {
      const next = new Set(prev)
      if (next.has(slug)) next.delete(slug)
      else next.add(slug)
      return next
    })
  }

  async function nextFrom(i: number) {
    setBusy(true)
    if (i === 1 && picked.size > 0) await joinClubs([...picked])
    if (i === 2) {
      const res = await saveOnboardingProfile({
        first, last, username: user, listing,
        birthdate: askBirth ? birth : null,
        consent: askConsent ? consent : null,
      })
      // Niet doorklikken als het niet lukte. Anders staat er straks "klaar"
      // terwijl zijn gebruikersnaam nooit opgeslagen is.
      if (!res.ok) { setError(res.error ?? null); setBusy(false); return }
    }
    setError(null)
    setBusy(false)
    setStep(i + 1)
  }

  async function done() {
    setBusy(true)
    await finishOnboarding()
    router.push('/ik')
    router.refresh()
  }

  return (
    <div className="mx-auto w-full max-w-xl">
      {/* Waar zit ik, en hoeveel komt er nog. Zonder die twee is elke stap
          onbepaalde tijd en haakt de helft af op stap twee. */}
      <ol className="mb-7 flex items-center gap-2">
        {steps.map((label, i) => (
          <li key={label} className="flex flex-1 flex-col gap-1.5">
            <span
              className={`h-1 rounded-full transition ${
                i <= step ? 'bg-[var(--brand)]' : 'bg-[var(--line)]'
              }`}
            />
            <span
              className={`text-[0.65rem] uppercase tracking-[0.14em] ${
                i === step ? 'text-[var(--text)]' : 'text-[var(--text-faint)]'
              }`}
            >
              {label}
            </span>
          </li>
        ))}
      </ol>

      {/* ------------------------------------------------------------ 1 --- */}
      {step === 0 && (
        <Card>
          <h1 className="text-2xl font-semibold tracking-tight">{t('ob.welcomeTitle')}</h1>
          <p className="mt-3 text-sm leading-relaxed text-[var(--text-muted)]">
            {t('ob.welcomeBody')}
          </p>
          <dl className="mt-5 space-y-4 border-t border-[var(--line)] pt-5">
            <div>
              <dt className="text-sm font-medium">{t('ob.whatPlatform')}</dt>
              <dd className="mt-1 text-sm leading-relaxed text-[var(--text-muted)]">
                {t('ob.whatPlatformBody')}
              </dd>
            </div>
            <div>
              <dt className="text-sm font-medium">{t('ob.whatClub')}</dt>
              <dd className="mt-1 text-sm leading-relaxed text-[var(--text-muted)]">
                {t('ob.whatClubBody')}
              </dd>
            </div>
          </dl>
          <Buttons
            busy={busy}
            onNext={() => setStep(1)}
            nextLabel={t('ob.start')}
          />
        </Card>
      )}

      {/* ------------------------------------------------------------ 2 --- */}
      {step === 1 && (
        <Card>
          <h1 className="text-2xl font-semibold tracking-tight">{t('ob.clubsTitle')}</h1>
          <p className="mt-2 text-sm leading-relaxed text-[var(--text-muted)]">
            {t('ob.clubsBody')}
          </p>

          {clubs.length === 0 ? (
            <p className="mt-5 rounded-[var(--radius)] border border-dashed border-[var(--line-strong)] p-4 text-sm text-[var(--text-muted)]">
              {t('ob.clubsNone')}
            </p>
          ) : (
            <ul className="mt-5 space-y-2">
              {clubs.map((c) => {
                const on = picked.has(c.slug)
                return (
                  <li key={c.slug}>
                    <label
                      className={`flex cursor-pointer items-center gap-3 rounded-[var(--radius)] border p-3.5 transition ${
                        on
                          ? 'border-[var(--brand)] bg-[color-mix(in_oklab,var(--brand)_10%,transparent)]'
                          : 'border-[var(--line)] hover:border-[var(--line-strong)]'
                      }`}
                    >
                      <input
                        type="checkbox"
                        checked={on}
                        onChange={() => toggle(c.slug)}
                        className="size-4 shrink-0"
                      />
                      <span className="flex size-10 shrink-0 items-center justify-center overflow-hidden rounded-lg border border-[var(--line)] bg-[var(--bg)]">
                        {c.logo_url ? (
                          // eslint-disable-next-line @next/next/no-img-element
                          <img src={c.logo_url} alt="" className="size-full object-contain" />
                        ) : (
                          <span className="text-sm font-semibold text-[var(--brand)]">
                            {c.name.slice(0, 1)}
                          </span>
                        )}
                      </span>
                      <span className="min-w-0 flex-1">
                        <span className="block truncate font-medium">{c.name}</span>
                        {c.city && (
                          <span className="block truncate text-xs text-[var(--text-faint)]">
                            {c.city}
                          </span>
                        )}
                      </span>
                    </label>
                  </li>
                )
              })}
            </ul>
          )}

          <Buttons
            busy={busy}
            onBack={() => setStep(0)}
            onNext={() => void nextFrom(1)}
            nextLabel={picked.size > 0 ? `${t('ob.joinNext')} (${picked.size})` : t('ob.skipStep')}
          />
        </Card>
      )}

      {/* ------------------------------------------------------------ 3 --- */}
      {step === 2 && (
        <Card>
          <h1 className="text-2xl font-semibold tracking-tight">{t('ob.youTitle')}</h1>
          <p className="mt-2 text-sm leading-relaxed text-[var(--text-muted)]">
            {t('ob.youBody')}
          </p>

          <div className="mt-5 space-y-4">
            <div className="grid gap-4 sm:grid-cols-2">
              <Field label={t('register.firstName')}>
                <input value={first} onChange={(e) => setFirst(e.target.value)} className={inputClass} />
              </Field>
              <Field label={t('register.lastName')}>
                <input value={last} onChange={(e) => setLast(e.target.value)} className={inputClass} />
              </Field>
            </div>

            <Field label={t('register.username')} hint={t('register.usernameHint')}>
              <input
                value={user}
                onChange={(e) => setUser(e.target.value)}
                pattern="[a-zA-Z0-9._-]{3,24}"
                className={inputClass}
              />
            </Field>

            {askBirth && (
              <Field label={t('register.birthdate')} hint={t('register.birthdateHint')}>
                <input
                  type="date" value={birth} onChange={(e) => setBirth(e.target.value)}
                  max={new Date().toISOString().slice(0, 10)}
                  className={inputClass}
                />
              </Field>
            )}

            {askConsent && (
              <label className="flex items-start gap-3 rounded-[var(--radius)] border border-[var(--line)] p-3.5">
                <input
                  type="checkbox"
                  checked={consent}
                  onChange={(e) => setConsent(e.target.checked)}
                  className="mt-0.5 size-4 shrink-0"
                />
                <span>
                  <span className="block text-sm font-medium">{t('register.consent')}</span>
                  <span className="mt-0.5 block text-xs leading-relaxed text-[var(--text-faint)]">
                    {t('register.consentHint')}
                  </span>
                </span>
              </label>
            )}

            <label className="flex items-start gap-3 rounded-[var(--radius)] border border-[var(--line)] p-3.5">
              <input
                type="checkbox"
                checked={listing}
                onChange={(e) => setListing(e.target.checked)}
                className="mt-0.5 size-4 shrink-0"
              />
              <span>
                <span className="block text-sm font-medium">{t('register.listing')}</span>
                <span className="mt-0.5 block text-xs leading-relaxed text-[var(--text-faint)]">
                  {t('register.listingHint')}
                </span>
              </span>
            </label>
          </div>

          {error && (
            <p className="mt-4 rounded-[var(--radius)] border border-[color-mix(in_oklab,var(--danger)_35%,transparent)] bg-[color-mix(in_oklab,var(--danger)_10%,transparent)] p-3 text-sm text-[var(--danger)]">
              {error}
            </p>
          )}

          <Buttons
            busy={busy}
            onBack={() => setStep(1)}
            onNext={() => void nextFrom(2)}
            nextLabel={t('ob.next')}
          />
        </Card>
      )}

      {/* ------------------------------------------------------------ 4 --- */}
      {step === 3 && (
        <Card>
          <h1 className="text-2xl font-semibold tracking-tight">{t('ob.doneTitle')}</h1>
          <p className="mt-3 text-sm leading-relaxed text-[var(--text-muted)]">
            {t('ob.doneBody')}
          </p>
          <button
            type="button"
            disabled={busy}
            onClick={() => void done()}
            className="mt-6 w-full rounded-full bg-[var(--brand)] px-5 py-3 text-sm font-medium text-[var(--on-brand)] transition hover:brightness-110 disabled:opacity-45"
          >
            {busy ? t('common.busy') : t('ob.toProfile')}
          </button>
        </Card>
      )}
    </div>
  )
}

function Buttons({
  busy, onBack, onNext, nextLabel,
}: { busy: boolean; onBack?: () => void; onNext: () => void; nextLabel: string }) {
  return (
    <div className="mt-6 flex items-center gap-3">
      {onBack && (
        <button
          type="button"
          disabled={busy}
          onClick={onBack}
          className="rounded-full px-3 py-2.5 text-sm text-[var(--text-muted)] transition hover:text-[var(--text)]"
        >
          ←
        </button>
      )}
      <button
        type="button"
        disabled={busy}
        onClick={onNext}
        className="flex-1 rounded-full bg-[var(--brand)] px-5 py-3 text-sm font-medium text-[var(--on-brand)] transition hover:brightness-110 disabled:opacity-45"
      >
        {nextLabel}
      </button>
    </div>
  )
}
