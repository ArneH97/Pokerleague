import { chooseLocale } from '@/lib/i18n/actions'
import { LOCALES, LOCALE_NAMES, type Locale } from '@/lib/i18n/dictionaries'

/**
 * De taalkeuze bij binnenkomst.
 *
 * Verschijnt alleen als er nog geen keuze in het koekje staat, en wordt op de
 * server gerenderd: er is dus geen moment waarop de bezoeker eerst de
 * verkeerde taal ziet staan.
 *
 * De tekst erboven staat in de drie talen tegelijk. Dat is geen slordigheid —
 * je kan iemand niet in één taal vragen welke taal hij wil, want dan heb je
 * de keuze al voor hem gemaakt.
 *
 * Er staat bewust geen kruisje op. Wegklikken zou betekenen dat we alsnog
 * gokken, en de knoppen zijn zo groot dat kiezen sneller gaat dan sluiten.
 */

const FLAGS: Record<Locale, string> = { nl: '🇧🇪', fr: '🇧🇪', en: '🇬🇧' }
const HINTS: Record<Locale, string> = {
  nl: 'Doorgaan in het Nederlands',
  fr: 'Continuer en français',
  en: 'Continue in English',
}

export function LanguageGate() {
  return (
    <div
      className="fixed inset-0 z-[100] flex items-end justify-center bg-[color-mix(in_oklab,#06110c_78%,transparent)] p-4 backdrop-blur-md sm:items-center"
      role="dialog"
      aria-modal="true"
      aria-label="Taal · Langue · Language"
    >
      <div className="w-full max-w-md rounded-[1.75rem] border border-[var(--line)] bg-[var(--bg)] p-6 shadow-2xl sm:p-8">
        <p className="text-sm font-semibold uppercase tracking-[0.22em]">
          Poker<span className="text-[var(--brand)]">League</span>
        </p>

        <h2 className="mt-4 text-2xl font-semibold leading-tight tracking-tight">
          Kies je taal
        </h2>
        <p className="mt-1 text-lg text-[var(--text-muted)]">
          Choisissez votre langue
        </p>
        <p className="text-lg text-[var(--text-muted)]">Choose your language</p>

        <div className="mt-7 space-y-3">
          {LOCALES.map((l) => (
            <form key={l} action={chooseLocale}>
              <input type="hidden" name="locale" value={l} />
              <button
                type="submit"
                lang={l}
                className="flex w-full items-center gap-4 rounded-2xl border border-[var(--line)] bg-[var(--surface-2)] px-5 py-4 text-left transition hover:border-[var(--brand)] hover:bg-[var(--surface-hover)] active:scale-[0.99]"
              >
                <span aria-hidden className="text-2xl leading-none">{FLAGS[l]}</span>
                <span className="min-w-0 flex-1">
                  <span className="block font-semibold">{LOCALE_NAMES[l]}</span>
                  <span className="block text-sm text-[var(--text-muted)]">{HINTS[l]}</span>
                </span>
                <span aria-hidden className="text-[var(--text-faint)]">→</span>
              </button>
            </form>
          ))}
        </div>
      </div>
    </div>
  )
}
