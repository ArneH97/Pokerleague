'use client'

import { useState } from 'react'
import { useT } from '@/lib/i18n/context'
import { RsvpForm } from '@/components/public/RsvpForm'

/**
 * De vraag die vóór het formulier komt: ken je ons al?
 *
 * **Waarom dit er is.** Het formulier vraagt naam, adres en geboortedatum. Voor
 * iemand die hier voor het eerst komt is dat het snelste pad naar een plaats op
 * de lijst. Voor een vaste speler die al een account heeft is het drie keer
 * intypen wat het platform allang weet — en pas ná het opsturen kreeg hij te
 * horen dat hij zich beter had kunnen aanmelden. Dat is de verkeerde volgorde:
 * de melding komt op het moment dat het werk al gedaan is.
 *
 * Dus eerst de vraag, dan het pad. Twee knoppen, geen uitleg vooraf.
 *
 * **Waarom "ik heb al een account" naar een ander adres springt.** Aanmelden
 * gebeurt op pokerleague.be en niet op het clubdomein. Dat is geen omweg maar
 * de kern van de opzet: een aanmeldkoekje reist niet over domeinen, en op het
 * clubdomein zit de sessie van de floor. Een speler die zich daar zou
 * aanmelden, gooit de floor eruit — midden in een tornooi. Vandaar dat hij
 * naar het platform gaat, zich daar aanmeldt, en meteen terugkomt op dezelfde
 * avond, waar dan één knop staat in plaats van een formulier.
 *
 * **En waarom "ik ben nieuw" geen sprong is.** Dat is verreweg de grootste
 * groep, en die hoort niet te betalen voor het gemak van de kleinere. Eén tik
 * en het formulier staat er, op dezelfde pagina.
 */
export function SignupChoice({
  tournamentId, clubName, bonusStack, registerHref, loginHref,
}: {
  tournamentId: string
  clubName: string
  bonusStack: number
  registerHref: string
  /** Aanmelden op het platform, met een terugweg naar déze avond. */
  loginHref: string
}) {
  const t = useT()
  const [nieuw, setNieuw] = useState(false)

  if (nieuw) {
    return (
      <div>
        <button
          type="button"
          onClick={() => setNieuw(false)}
          className="mb-3 text-sm text-[var(--text-muted)] underline decoration-dotted underline-offset-4 transition hover:text-[var(--text)]"
        >
          {t('choice.back')}
        </button>
        <RsvpForm
          tournamentId={tournamentId}
          clubName={clubName}
          bonusStack={bonusStack}
          registerHref={registerHref}
          loginHref={loginHref}
        />
      </div>
    )
  }

  return (
    <div className="rounded-[var(--radius-lg)] border border-[var(--line)] bg-[var(--surface)] p-6">
      <h2 className="text-lg font-semibold">{t('choice.title')}</h2>
      <p className="mt-1.5 text-sm leading-relaxed text-[var(--text-muted)]">
        {t('choice.lede')}
      </p>

      <div className="mt-5 flex flex-col gap-3">
        {/* De nieuwe speler eerst: dat is de grootste groep en de reden dat
            deze pagina bestaat. */}
        <button
          type="button"
          onClick={() => setNieuw(true)}
          className="rounded-[var(--radius)] bg-[var(--brand)] px-4 py-3.5 text-center font-medium text-[var(--on-brand)] transition hover:brightness-110"
        >
          {t('choice.new')}
        </button>

        <a
          href={loginHref}
          className="rounded-[var(--radius)] border border-[var(--line-strong)] px-4 py-3.5 text-center font-medium transition hover:bg-[var(--surface-hover)]"
        >
          {t('choice.have')}
        </a>
      </div>

      <p className="mt-4 text-xs leading-relaxed text-[var(--text-faint)]">
        {t('choice.hint')}
      </p>
    </div>
  )
}
