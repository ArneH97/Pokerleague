import { chooseLocale } from '@/lib/i18n/actions'
import { LOCALES, type Locale } from '@/lib/i18n/dictionaries'

/**
 * Taal wisselen nadat de keuze al gemaakt is.
 *
 * Drie korte codes naast elkaar in plaats van een uitklaplijst: op een
 * telefoon is dat één tik in plaats van drie, en het neemt minder plaats in
 * dan een keuzemenu met vlaggen.
 */
export function LanguageSwitch({
  current, label,
}: { current: Locale; label: string }) {
  return (
    <div className="flex items-center gap-0.5 rounded-full border border-[var(--line)] p-0.5" aria-label={label}>
      {LOCALES.map((l) => (
        <form key={l} action={chooseLocale}>
          <input type="hidden" name="locale" value={l} />
          <button
            type="submit"
            lang={l}
            aria-current={l === current ? 'true' : undefined}
            className={`rounded-full px-2.5 py-1 text-xs font-semibold uppercase tracking-wider transition ${
              l === current
                ? 'bg-[var(--brand)] text-[var(--on-brand)]'
                : 'text-[var(--text-faint)] hover:bg-[var(--surface-hover)] hover:text-[var(--text)]'
            }`}
          >
            {l}
          </button>
        </form>
      ))}
    </div>
  )
}
