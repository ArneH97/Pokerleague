import { pointsFor, stakeWeight, type PointsRules } from '@/lib/points'
import type { T } from '@/lib/i18n/dictionaries'

/**
 * Hoe de punten tot stand komen, onderaan het klassement.
 *
 * De eerste vraag bij elk klassement met een prijs eraan is "waarom heeft hij
 * er meer dan ik". Dat antwoord hoort onder de tabel te staan en niet in een
 * handleiding die niemand opent.
 *
 * De formule komt uit de database (`club_public_season_rules`) en niet uit
 * code hier. Dat is geen omweg: zou het scherm zijn eigen versie van de
 * formule hebben, dan legt het vroeg of laat iets uit dat de telling niet
 * meer doet — en een verkeerde uitleg is erger dan geen uitleg.
 *
 * Het rekenvoorbeeld gaat over plaats 1, 2, 5 en laatste bij twintig spelers.
 * Twintig omdat dat een normale avond is; de uitersten erbij omdat de vraag
 * eigenlijk altijd gaat over het verschil tussen winnen en meedoen.
 */
export function PointsExplainer({
  rules, locale, t, currency = 'EUR',
}: {
  rules: PointsRules
  locale: string
  t: T
  currency?: string
}) {
  const getal = (n: number) => n.toLocaleString(`${locale}-BE`)
  const geld = (n: number) =>
    new Intl.NumberFormat(`${locale}-BE`, {
      style: 'currency', currency, maximumFractionDigits: 0,
    }).format(n)

  const steil = rules.exponent !== 0.5
  const ijkpunt = rules.buyin_ref ?? 0
  const regels: string[] = []

  if (rules.bonus_entry > 0) {
    regels.push(t('expl.entry').replace('{n}', getal(rules.bonus_entry)))
  }
  if (rules.bonus_per_ko > 0) {
    regels.push(t('expl.ko').replace('{n}', getal(rules.bonus_per_ko)))
  }
  if (ijkpunt > 0) {
    regels.push(t('expl.stake').replace('{ref}', geld(ijkpunt)))
  }
  if (rules.count_best_n) {
    regels.push(t('expl.bestN').replace('{n}', String(rules.count_best_n)))
  }
  if (rules.min_tournaments > 0) {
    regels.push(t('expl.minEvents').replace('{n}', String(rules.min_tournaments)))
  }

  // Het voorbeeld op de ijkinleg: daar is de weging precies 1, en dan toont
  // het de formule zonder dat de inleg het beeld vertroebelt.
  const inzet = ijkpunt > 0 ? ijkpunt * 100 : 3000
  const VELD = 20
  const voorbeeld = [1, 2, 5, VELD]
    .map((plaats) => ({ plaats, punten: pointsFor(rules, plaats, VELD, inzet) }))
    .filter((x): x is { plaats: number; punten: number } => x.punten !== null)

  return (
    <section className="mt-6 rounded-[var(--radius-lg,1rem)] border border-[var(--line)] bg-[var(--surface)] p-4 sm:p-5">
      <h2 className="text-sm font-semibold">{t('expl.title')}</h2>

      <p className="tnum mt-2 text-sm text-[var(--text-muted)]">
        {steil
          ? t('points.sqrtExp')
            .replace('{mult}', getal(rules.multiplier))
            .replace('{exp}', getal(rules.exponent))
          : t('points.sqrt').replace('{mult}', getal(rules.multiplier))}
      </p>

      {regels.length > 0 && (
        <ul className="mt-3 space-y-1.5 text-sm leading-relaxed text-[var(--text-muted)]">
          {regels.map((r) => (
            <li key={r} className="flex gap-2">
              <span aria-hidden className="text-[var(--text-faint)]">·</span>
              <span>{r}</span>
            </li>
          ))}
        </ul>
      )}

      {voorbeeld.length > 0 && (
        <div className="mt-4">
          <p className="text-xs uppercase tracking-[0.18em] text-[var(--text-faint)]">
            {ijkpunt > 0
              ? t('expl.exampleAt').replace('{n}', String(VELD)).replace('{ref}', geld(ijkpunt))
              : t('expl.example').replace('{n}', String(VELD))}
          </p>
          {/* Een rij blokjes en geen tabel: vier getallen met een label
              erboven leest op een telefoon beter dan vier rijen met één
              getal. Ze wrappen vanzelf als de taal langere woorden heeft. */}
          <div className="mt-2 flex flex-wrap gap-x-5 gap-y-2">
            {voorbeeld.map((x) => (
              <div key={x.plaats}>
                <p className="text-xs text-[var(--text-faint)]">
                  {x.plaats === 1 ? t('expl.winner')
                    : x.plaats === VELD ? t('expl.last')
                      : t('expl.place').replace('{n}', String(x.plaats))}
                </p>
                <p className="tnum text-base font-semibold">
                  {getal(x.punten)} <span className="text-xs font-normal text-[var(--text-faint)]">{t('pub.pts')}</span>
                </p>
              </div>
            ))}
          </div>
        </div>
      )}
    </section>
  )
}

/**
 * De weging van één avond als tekst, bijvoorbeeld "×1,15". Null wanneer de
 * club de inzet niet laat meewegen — dan hoort er niets te staan in plaats
 * van een nietszeggende ×1,00.
 */
export function weightLabel(
  rules: PointsRules, stakeCents: number, locale: string,
): string | null {
  const w = stakeWeight(rules, stakeCents)
  if (w === null) return null
  return `×${w.toLocaleString(`${locale}-BE`, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
}
