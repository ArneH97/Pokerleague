'use client'

import { useState } from 'react'
import { useT } from '@/lib/i18n/context'

/**
 * Promomateriaal bij een avond met een voorinschrijfbonus.
 *
 * **Waarom een knop en niet meteen vier beelden op de pagina.** Elke affiche is
 * een serverfunctie die satori draait. Vier daarvan bij elke keer dat iemand de
 * tornooipagina opent, terwijl de floor er meestal komt om iets anders te doen,
 * is rekenwerk voor niets. Nu gebeurt het als hij erom vraagt.
 *
 * **En waarom ze daarna gewoon in beeld staan.** De floor deelt dit op een
 * telefoon: lang drukken op een afbeelding en "bewaren" is daar de kortste weg
 * naar Facebook. Een downloadknop die een bestand in een map zet, is op een
 * telefoon juist de omweg. Vandaar dat de beelden zichtbaar zijn én er een
 * bewaarlink onder staat voor wie op een laptop zit.
 *
 * Zonder bonus staat hier niets te halen: dan is de affiche een affiche zonder
 * belofte. Het scherm zegt dat, met de weg ernaartoe.
 */

type Vorm = 'vierkant' | 'verhaal'

const AFFICHES: { vorm: Vorm; locale: 'nl' | 'fr'; taal: string }[] = [
  { vorm: 'vierkant', locale: 'nl', taal: 'NL' },
  { vorm: 'vierkant', locale: 'fr', taal: 'FR' },
  { vorm: 'verhaal', locale: 'nl', taal: 'NL' },
  { vorm: 'verhaal', locale: 'fr', taal: 'FR' },
]

export function PromoPanel({
  clubSlug, tournamentId, hasBonus,
}: {
  clubSlug: string
  tournamentId: string
  hasBonus: boolean
}) {
  const t = useT()
  const [tonen, setTonen] = useState(false)

  if (!hasBonus) {
    return (
      <p className="text-xs leading-relaxed text-[var(--text-faint)]">
        {t('promo.noBonus')}
      </p>
    )
  }

  const src = (vorm: Vorm, locale: string) =>
    `/api/promo/${clubSlug}/${tournamentId}?vorm=${vorm}&l=${locale}`

  if (!tonen) {
    return (
      <div>
        <button
          type="button"
          onClick={() => setTonen(true)}
          className="rounded-lg border border-[var(--line-strong)] px-3 py-2 text-sm transition hover:bg-[var(--surface-hover)]"
        >
          {t('promo.button')}
        </button>
        <p className="mt-2 text-xs leading-relaxed text-[var(--text-faint)]">
          {t('promo.hint')}
        </p>
      </div>
    )
  }

  return (
    <div>
      {/* Twee kolommen op een breed scherm, één op een telefoon. De verhalen
          zijn bijna twee keer zo hoog als de vierkanten, dus ze staan per
          vorm bij elkaar in plaats van door elkaar. */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        {AFFICHES.map(({ vorm, locale, taal }) => (
          <figure key={`${vorm}-${locale}`} className="min-w-0">
            <figcaption className="mb-1.5 flex items-center justify-between gap-2 text-xs text-[var(--text-faint)]">
              <span>
                {vorm === 'vierkant' ? t('promo.square') : t('promo.story')} · {taal}
              </span>
              <a
                href={src(vorm, locale)}
                download={`${clubSlug}-${vorm}-${locale}.png`}
                className="underline decoration-dotted underline-offset-2 transition hover:text-[var(--text)]"
              >
                {t('promo.download')}
              </a>
            </figcaption>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img
              src={src(vorm, locale)}
              alt=""
              loading="lazy"
              className="w-full rounded-xl border border-[var(--line)] bg-[var(--surface-2)]"
            />
          </figure>
        ))}
      </div>
      <p className="mt-2 text-xs leading-relaxed text-[var(--text-faint)]">
        {t('promo.hint')}
      </p>
    </div>
  )
}
