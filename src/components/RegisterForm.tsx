'use client'

import { useState } from 'react'
import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { Button, Card, Field, Notice, inputClass } from '@/components/ui'
import { useLocale, useT } from '@/lib/i18n/context'

/**
 * Registreren als speler.
 *
 * Wat hier gebeurt is niet "een profiel aanmaken". Wie al eens bij een club
 * aan tafel zat bestáát al: de floor typte zijn naam en mailadres in aan de
 * deur, en zijn punten staan in een klassement. Registreren betekent dus
 * opeisen — en dat gebeurt op mailadres, in de database, zodat er nooit een
 * tweede profiel bijkomt met de historie aan de verkeerde helft.
 *
 * Dat is meteen waarom er hier zo weinig velden staan. Voornaam, achternaam,
 * mailadres, wachtwoord. Geen geboortedatum, geen gemeente: die heeft de club
 * nodig voor het gedoogbeleid en die vraagt de club, aan de deur, waar er ook
 * een identiteitskaart tegenover kan staan. Hier vragen zou betekenen dat we
 * ze op ons woord geloven.
 *
 * De gebruikersnaam is optioneel en niet weggestopt: zonder toestemming voor
 * je echte naam is dát wat er in een landelijke ranglijst komt te staan.
 *
 * Komt iemand binnen via een uitnodiging van zijn club, dan staat het
 * mailadres vast. Niet uit koppigheid maar omdat dát adres de sleutel is naar
 * de historie die al op zijn naam staat: tikt hij hier een ander adres in, dan
 * maakt hij een leeg tweede profiel en blijven zijn punten achter bij het
 * eerste. De uitleg staat er dus bij, en het veld is te openen voor wie echt
 * een ander adres wil — dan is het een keuze en geen ongeluk.
 */
export function RegisterForm({
  invitedEmail,
  clubName,
  joinSlug,
}: {
  invitedEmail?: string
  clubName?: string
  /**
   * De club waar hij zich wil aansluiten. Reist mee tot ná de bevestigingsmail
   * — anders is die keuze weg tegen de tijd dat hij terug is, en moet hij hem
   * zelf opnieuw zoeken op een platform dat hij nog niet kent.
   */
  joinSlug?: string
} = {}) {
  const router = useRouter()
  const t = useT()
  // De taal waarin hij dit formulier leest. Dat is een sterkere aanwijzing dan
  // wat de floor ooit gokte, en we hoeven er niets voor te vragen.
  const locale = useLocale()

  const [firstName, setFirstName] = useState('')
  const [lastName, setLastName] = useState('')
  const [username, setUsername] = useState('')
  const [email, setEmail] = useState(invitedEmail ?? '')
  const [unlocked, setUnlocked] = useState(false)
  const [password, setPassword] = useState('')
  const [listing, setListing] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [confirm, setConfirm] = useState(false)

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault()
    setBusy(true)
    setError(null)

    const supabase = createClient()
    const { data, error: err } = await supabase.auth.signUp({
      email,
      password,
      options: {
        // Deze gegevens reizen mee in het token en worden pas gebruikt zodra
        // het profiel opgeeist wordt. Zo hoeven ze nergens tussentijds in een
        // tabel te blijven hangen — en overleven ze de omweg langs de mailbox,
        // want op dat moment is het formulier allang weg.
        data: {
          first_name: firstName, last_name: lastName, username,
          public_listing: listing, locale,
        },
        // Zonder dit landt de bevestigingslink op de voorpagina en mag hij
        // zelf zoeken waar zijn profiel staat.
        emailRedirectTo: `${window.location.origin}/auth/callback?next=${
          joinSlug ? `/aansluiten/${joinSlug}` : '/ik'
        }`,
      },
    })

    if (err) {
      setError(
        err.message.includes('already registered')
          ? t('register.exists')
          : err.message,
      )
      setBusy(false)
      return
    }

    // Staat bevestiging per mail aan, dan is er nog geen sessie en moet hij
    // eerst op de link klikken. Anders is hij meteen binnen.
    if (!data.session) {
      setConfirm(true)
      setBusy(false)
      return
    }

    await supabase.rpc('claim_my_player', {
      p_first_name: firstName,
      p_last_name: lastName,
      p_username: username || null,
      p_listing: listing,
      p_locale: locale,
    })

    router.push(joinSlug ? `/aansluiten/${joinSlug}` : '/ik')
    router.refresh()
  }

  const locked = Boolean(invitedEmail) && !unlocked

  if (confirm) {
    return (
      <main className="flex min-h-dvh items-center justify-center px-5 py-10">
        <div className="w-full max-w-sm">
          <Card>
            <h1 className="text-xl font-semibold">{t('register.checkMail')}</h1>
            <p className="mt-2 text-sm leading-relaxed text-[var(--text-muted)]">
              {t('register.checkMailBody')} <span className="text-[var(--text)]">{email}</span>
            </p>
            <p className="mt-4 text-sm">
              <Link href="/login" className="text-[var(--brand)] underline-offset-4 hover:underline">
                {t('common.signIn')} →
              </Link>
            </p>
          </Card>
        </div>
      </main>
    )
  }

  return (
    <main className="flex min-h-dvh items-center justify-center px-5 py-10">
      <div className="w-full max-w-sm">
        <div className="mb-7 text-center">
          <h1 className="text-2xl font-semibold">
            {clubName ? t('invite.formTitle') : t('register.title')}
          </h1>
          <p className="mt-2 text-sm leading-relaxed text-[var(--text-muted)]">
            {clubName ? t('invite.formBody').replace('{club}', clubName) : t('register.body')}
          </p>
        </div>

        <Card>
          <form onSubmit={onSubmit} className="space-y-4">
            <div className="grid grid-cols-2 gap-3">
              <Field label={t('register.firstName')}>
                <input
                  value={firstName} onChange={(e) => setFirstName(e.target.value)}
                  autoComplete="given-name" required className={inputClass}
                />
              </Field>
              <Field label={t('register.lastName')}>
                <input
                  value={lastName} onChange={(e) => setLastName(e.target.value)}
                  autoComplete="family-name" required className={inputClass}
                />
              </Field>
            </div>

            <Field
              label={t('common.email')}
              hint={locked ? t('invite.emailLocked') : t('register.emailHint')}
            >
              <input
                type="email" value={email} onChange={(e) => setEmail(e.target.value)}
                autoComplete="email" required readOnly={locked}
                className={`${inputClass}${locked ? ' cursor-default text-[var(--text-muted)]' : ''}`}
              />
              {locked && (
                <button
                  type="button"
                  onClick={() => setUnlocked(true)}
                  className="mt-1.5 text-xs text-[var(--text-faint)] underline underline-offset-4 hover:text-[var(--text-muted)]"
                >
                  {t('invite.emailChange')}
                </button>
              )}
            </Field>

            <Field label={t('register.password')} hint={t('register.passwordHint')}>
              <input
                type="password" value={password} onChange={(e) => setPassword(e.target.value)}
                autoComplete="new-password" minLength={8} required className={inputClass}
              />
            </Field>

            <Field label={t('register.username')} hint={t('register.usernameHint')}>
              <input
                value={username} onChange={(e) => setUsername(e.target.value)}
                pattern="[a-zA-Z0-9._-]{3,24}" autoComplete="off" className={inputClass}
              />
            </Field>

            <label className="flex items-start gap-3 rounded-[var(--radius)] border border-[var(--line)] p-3.5">
              <input
                type="checkbox" checked={listing}
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

            {error && <Notice tone="error">{error}</Notice>}

            <Button type="submit" disabled={busy} className="w-full">
              {busy ? t('common.busy') : t('register.submit')}
            </Button>
          </form>
        </Card>

        <p className="mt-5 text-center text-sm text-[var(--text-muted)]">
          {t('register.haveAccount')}{' '}
          <Link href="/login" className="text-[var(--brand)] underline-offset-4 hover:underline">
            {t('common.signIn')}
          </Link>
        </p>
      </div>
    </main>
  )
}
