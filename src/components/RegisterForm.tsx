'use client'

import { useEffect, useState } from 'react'
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
  const [password2, setPassword2] = useState('')
  const [birthdate, setBirthdate] = useState('')
  // Standaard aangevinkt. Dit is geen extraatje maar waar de dienst voor
  // dient: zonder je resultaten mee te tellen valt er niets te tonen. Het
  // vinkje eronder — je naam publiek in een ranglijst — blijft wél leeg, want
  // dat is een echte keuze en een vooraf aangevinkt hokje is daar geen geldige
  // toestemming voor.
  const [consent, setConsent] = useState(true)
  const [listing, setListing] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [confirm, setConfirm] = useState(false)

  /** Vrij, bezet, of nog niet nagekeken. */
  const [nameFree, setNameFree] = useState<boolean | null>(null)

  // Meteen zeggen of de naam bezet is, niet pas nadat hij het hele formulier
  // invulde en zijn wachtwoord kwijt is.
  const clean = username.trim()
  useEffect(() => {
    if (!/^[a-zA-Z0-9._-]{3,24}$/.test(clean)) {
      // eslint-disable-next-line react-hooks/set-state-in-effect
      setNameFree(null)
      return
    }
    let cancelled = false
    const id = setTimeout(async () => {
      const { data } = await createClient().rpc('username_available', { p_username: clean })
      if (!cancelled) setNameFree(data === true)
    }, 350)
    return () => { cancelled = true; clearTimeout(id) }
  }, [clean])

  /**
   * De leeftijd op basis van wat hij intikte.
   *
   * Dit bewijst niets — een zelf ingetikte datum is geen identiteitskaart, en
   * de club controleert er aan de deur nog altijd een. Wat het wel doet is
   * meteen zeggen waarom het niet lukt, in plaats van hem het formulier te
   * laten versturen voor een databasefout die hetzelfde zegt.
   */
  function ageOf(iso: string): number | null {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(iso)) return null
    const [y, m, d] = iso.split('-').map(Number)
    const today = new Date()
    let age = today.getFullYear() - y
    const had = today.getMonth() + 1 > m || (today.getMonth() + 1 === m && today.getDate() >= d)
    if (!had) age -= 1
    return age
  }
  const age = ageOf(birthdate)
  const tooYoung = age !== null && age < 18
  const mismatch = password2 !== '' && password !== password2

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
        // Reist mee in het token tot het profiel opgeeist wordt — ná de
        // bevestigingsmail, wanneer dit formulier allang weg is.
        data: {
          first_name: firstName, last_name: lastName, username,
          public_listing: listing, locale,
          birthdate, stats_consent: consent,
        },
        // Zonder dit landt de bevestigingslink op de voorpagina en mag hij
        // zelf zoeken waar zijn profiel staat.
        // Naar het welkomstscherm en niet naar zijn profiel: daar staat op dat
        // moment nog niets, en dat leest als een fout in plaats van als een
        // begin. Kwam hij via een club binnen, dan gaat hij daar eerst langs
        // en komt het welkomstscherm daarna.
        emailRedirectTo: `${window.location.origin}/auth/callback?next=${
          joinSlug ? `/aansluiten/${joinSlug}` : '/welkom'
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
      p_birthdate: birthdate,
      p_consent: consent,
    })

    router.push(joinSlug ? `/aansluiten/${joinSlug}` : '/welkom')
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

            {/* Twee keer intikken. Een typfout in een wachtwoord merk je pas bij
                het volgende bezoek, en dan sta je met een adres dat bevestigd
                is en een sleutel die je nooit gekend hebt. */}
            <Field label={t('register.password2')}>
              <input
                type="password" value={password2} onChange={(e) => setPassword2(e.target.value)}
                autoComplete="new-password" minLength={8} required
                aria-invalid={mismatch}
                className={`${inputClass}${mismatch ? ' border-[var(--danger)]' : ''}`}
              />
              {mismatch && (
                <p className="mt-1.5 text-xs text-[var(--danger)]">{t('register.password2Bad')}</p>
              )}
            </Field>

            <Field
              label={t('register.username')}
              hint={
                nameFree === false ? t('register.nameTaken')
                : nameFree === true ? t('register.nameFree')
                : t('register.usernameHint')
              }
            >
              <input
                value={username} onChange={(e) => setUsername(e.target.value)}
                pattern="[a-zA-Z0-9._-]{3,24}" autoComplete="off" required
                aria-invalid={nameFree === false}
                className={`${inputClass}${
                  nameFree === false ? ' border-[var(--danger)]' : ''
                }`}
              />
            </Field>

            <Field label={t('register.birthdate')} hint={t('register.birthdateHint')}>
              <input
                type="date" value={birthdate} onChange={(e) => setBirthdate(e.target.value)}
                required autoComplete="bday"
                max={new Date().toISOString().slice(0, 10)}
                className={`${inputClass}${tooYoung ? ' border-[var(--danger)]' : ''}`}
              />
              {tooYoung && (
                <p className="mt-1.5 text-xs text-[var(--danger)]">{t('register.tooYoung')}</p>
              )}
            </Field>

            <label className="flex items-start gap-3 rounded-[var(--radius)] border border-[var(--line)] p-3.5">
              <input
                type="checkbox" checked={consent} required
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

            <Button
              type="submit"
              disabled={busy || tooYoung || mismatch || password2 === '' || nameFree === false}
              className="w-full"
            >
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
