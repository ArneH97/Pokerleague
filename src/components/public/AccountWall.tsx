import Link from 'next/link'
import type { T } from '@/lib/i18n/dictionaries'

/**
 * Wat er staat waar de cijfers stonden, als je geen account hebt.
 *
 * Een muur is een slecht idee als hij niet uitlegt waarom hij er staat — dan
 * is het gewoon een deur die dichtvalt. Dus staat de reden erbij, en die is
 * echt: een uitslagenlijst is met pseudoniemen nog altijd een tijdlijn van
 * iemands avonden, en "iedereen op internet" is daarvoor een ruimere kring dan
 * nodig.
 *
 * Het clubkaartje erboven blijft wél open. Wie de club zoekt, vindt hem — met
 * adres, speeldag en telefoonnummer. Alleen wat over gespeelde avonden gaat
 * zit hierachter.
 */
export function AccountWall({ t, next }: { t: T; next?: string }) {
  const suffix = next ? `?next=${encodeURIComponent(next)}` : ''

  return (
    <section className="rounded-3xl border border-dashed border-[var(--line-strong)] px-6 py-10 text-center sm:px-10 sm:py-14">
      <p className="text-2xl" aria-hidden>♠</p>
      <h2 className="mt-3 text-xl font-semibold tracking-tight">{t('wall.title')}</h2>
      <p className="mx-auto mt-2 max-w-md text-pretty text-sm leading-relaxed text-[var(--text-muted)]">
        {t('wall.body')}
      </p>
      <div className="mt-6 flex flex-wrap items-center justify-center gap-3">
        <Link
          href={`/registreren${suffix}`}
          className="rounded-full bg-[var(--brand)] px-5 py-2.5 text-sm font-medium text-[var(--on-brand)] transition hover:brightness-110"
        >
          {t('wall.cta')}
        </Link>
        <Link
          href={`/login${suffix}`}
          className="text-sm text-[var(--text-muted)] underline-offset-4 hover:underline"
        >
          {t('common.signIn')}
        </Link>
      </div>
    </section>
  )
}
