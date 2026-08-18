
import type { Club } from '@/lib/club'
import { translator, type Locale } from '@/lib/i18n/dictionaries'
import { playerUrl } from '@/lib/site'
import { createClient } from '@/lib/supabase/server'
import { formatMoney } from '@/lib/types'

/**
 * Wat jij bij déze club hebt staan.
 *
 * Dit strookje is het antwoord op een klacht die niet over tekst ging: spelers
 * en clubs wisten niet wat PokerLeague was en wat de club was. Dat kwam niet
 * doordat het ergens slecht uitgelegd stond, maar doordat er een schakel
 * ontbrak. Een speler zag op de clubpagina het klassement van iedereen, en op
 * zijn eigen pagina de optelsom van alles — en nergens het ene ding waarmee
 * het kwartje valt: *wat hij hier heeft staan.*
 *
 * Met die schakel is het ineens simpel te zeggen, en dat is dan ook precies
 * wat er staat:
 *
 *   Je speelt bij een club. Je resultaten staan op je profiel.
 *
 * Drie toestanden, want alle drie komen ze voor en ze verdienen elk een ander
 * antwoord:
 *
 *   * aangemeld en er staan cijfers → zijn plaats, zijn avonden, zijn geld
 *   * aangemeld maar nog niets gespeeld → zeggen dat het klopt en wanneer het
 *     komt, in plaats van nullen tonen die op een fout lijken
 *   * niet aangemeld → één uitnodiging, en verder niets
 *
 * **Over het witlabel.** De clubpagina draagt bewust geen PokerLeague-merk;
 * dit is de pagina van de club. Die regel blijft staan. De naam valt hier
 * precies één keer, en alleen omdat de bezoeker op dat moment zelf de vraag
 * stelt waar het antwoord op is: waar staat de rest van mijn spel? Een merk in
 * de kop is branding, een naam in een antwoord is een wegwijzer.
 */

interface Stat {
  tournaments: number
  points: number
  best_position: number
  cashes: number
  prize_cents: number
  rank: number
  of_players: number
}

export async function YourNumbers({ club, locale }: { club: Club; locale: Locale }) {
  const t = translator(locale)
  const supabase = await createClient()

  // Relatief zolang we op het platform staan, absoluut vanaf een clubdomein.
  // Zie playerUrl: een sprong naar een ander domein kost je je sessie.
  const mineHref = await playerUrl('/ik')
  const joinHref = await playerUrl(`/registreren?club=${club.slug}`)
  const signInHref = await playerUrl(`/aansluiten/${club.slug}`)

  const { data: claims } = await supabase.auth.getClaims()

  // ------------------------------------------------------------ bezoeker ---
  if (!claims?.claims) {
    return (
      <section className="mt-4 flex flex-wrap items-center gap-x-5 gap-y-2 rounded-2xl border border-dashed border-[var(--line-strong)] px-5 py-4">
        <p className="min-w-0 flex-1 text-sm leading-relaxed text-[var(--text-muted)]">
          <span className="text-[var(--text)]">{t('pub.joinTitle')}</span>{' '}
          {t('pub.joinBody').replace('{club}', club.name)}
        </p>
        <span className="flex shrink-0 items-center gap-3">
          {/* Absolute adressen naar het platform, niet relatieve paden. Op
              app.cutoff.be zou /registreren door de proxy vertaald worden naar
              /c/cutoff/registreren — een pagina die niet bestaat — en /login
              naar het personeelsscherm. Zie de uitleg in lib/site.ts. */}
          <a
            href={joinHref}
            className="rounded-full bg-[var(--brand)] px-4 py-2 text-sm font-medium text-[var(--on-brand)] transition hover:brightness-110"
          >
            {t('pub.joinCta')}
          </a>
          <a
            href={signInHref}
            className="text-sm text-[var(--text-muted)] underline-offset-4 hover:underline"
          >
            {t('common.signIn')}
          </a>
        </span>
      </section>
    )
  }

  const { data } = await supabase.rpc('my_club_stats', { p_club_slug: club.slug })
  const s = ((data ?? []) as unknown as Stat[])[0] ?? null

  // ------------------------------- aangemeld, maar hier nog niets gespeeld ---
  if (!s) {
    return (
      <section className="mt-4 flex flex-wrap items-center gap-x-5 gap-y-2 rounded-2xl border border-[var(--line)] bg-[var(--surface)] px-5 py-4">
        <p className="min-w-0 flex-1 text-sm leading-relaxed text-[var(--text-muted)]">
          {t('pub.yoursNone').replace('{club}', club.name)}
        </p>
        <a
          href={mineHref}
          className="shrink-0 text-sm text-[var(--brand)] underline-offset-4 hover:underline"
        >
          {t('pub.yoursAll')} →
        </a>
      </section>
    )
  }

  // --------------------------------------------------------- met cijfers ---
  return (
    <section className="mt-4 rounded-2xl border border-[var(--line)] bg-[var(--surface)] px-5 py-4">
      <div className="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1">
        <h2 className="text-xs uppercase tracking-[0.22em] text-[var(--text-faint)]">
          {t('pub.yours')}
        </h2>
        <a
          href={mineHref}
          className="text-sm text-[var(--brand)] underline-offset-4 hover:underline"
        >
          {t('pub.yoursAll')} →
        </a>
      </div>

      <div className="mt-3 grid grid-cols-2 gap-x-4 gap-y-3 sm:grid-cols-4">
        <Cell
          label={t('pub.standings')}
          value={`${s.rank}`}
          sub={`${t('common.of')} ${s.of_players}`}
          accent
        />
        <Cell label={t('me.played')} value={`${s.tournaments}`} />
        <Cell label={t('pub.pts')} value={`${Math.round(Number(s.points))}`} />
        <Cell
          label={t('me.won')}
          value={Number(s.prize_cents) > 0 ? formatMoney(Number(s.prize_cents), club.currency) : '—'}
          sub={s.cashes > 0 ? `${s.cashes}× ${t('me.cashes').toLowerCase()}` : undefined}
        />
      </div>
    </section>
  )
}

function Cell({
  label, value, sub, accent,
}: { label: string; value: string; sub?: string; accent?: boolean }) {
  return (
    <div>
      <p className="text-[0.6rem] uppercase tracking-[0.16em] text-[var(--text-faint)]">{label}</p>
      <p
        className={`tnum mt-0.5 text-xl font-semibold leading-tight ${
          accent ? 'text-[var(--brand)]' : ''
        }`}
      >
        {value}
        {sub && <span className="ml-1 text-xs font-normal text-[var(--text-faint)]">{sub}</span>}
      </p>
    </div>
  )
}
