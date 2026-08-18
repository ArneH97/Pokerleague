'use client'

import { useState } from 'react'
import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { joinClubs } from '@/lib/joinActions'
import { useT } from '@/lib/i18n/context'
import { formatMoney } from '@/lib/types'
import type { JoinableClub } from '@/components/JoinClubs'

/**
 * Mijn clubs, met de deur naar de rest erin.
 *
 * Dit heette "Waar je bij hoort" en dat was een uitleg vermomd als kop. De
 * naam van een sectie hoort te zeggen wát er staat, niet waarom het bestaat —
 * die uitleg staat er nog steeds, maar eronder en kleiner.
 *
 * Belangrijker is wat erbij komt: **ontdek meer clubs**. Zonder die knop was
 * dit een doodlopende lijst. Een speler die bij één club zit heeft geen enkele
 * manier om te weten dat er anderen zijn, terwijl dat precies is wat dit
 * platform hem te bieden heeft. Ingeklapt, want wie zijn clubs komt bekijken
 * is niet op zoek naar reclame — maar één tik ver.
 */

export interface MyClubRow {
  slug: string
  name: string
  city: string | null
  logo_url: string | null
  primary_color: string | null
  rank: number | null
  of_players: number | null
  tournaments: number
  points: number
  prize_cents: number
}

export function MyClubs({
  mine, discover,
}: { mine: MyClubRow[]; discover: JoinableClub[] }) {
  const t = useT()
  const router = useRouter()
  const [open, setOpen] = useState(false)
  const [picked, setPicked] = useState<Set<string>>(new Set())
  const [busy, setBusy] = useState(false)

  async function join() {
    setBusy(true)
    await joinClubs([...picked])
    setPicked(new Set())
    setOpen(false)
    setBusy(false)
    router.refresh()
  }

  return (
    <section>
      <div className="mb-2 flex flex-wrap items-baseline justify-between gap-x-3">
        <h2 className="text-xs uppercase tracking-[0.22em] text-[var(--text-faint)]">
          {t('me.myClubs')}
        </h2>
        {discover.length > 0 && (
          <button
            type="button"
            onClick={() => setOpen((v) => !v)}
            className="text-sm font-medium text-[var(--brand)] underline-offset-4 hover:underline"
          >
            {open ? t('me.discoverClose') : `${t('me.discover')} →`}
          </button>
        )}
      </div>

      {mine.length === 0 ? (
        <div className="rounded-[var(--radius)] border border-dashed border-[var(--line-strong)] p-5">
          <p className="text-sm leading-relaxed text-[var(--text-muted)]">{t('me.noClubs')}</p>
        </div>
      ) : (
        <ul className="grid gap-3 sm:grid-cols-2">
          {mine.map((c) => {
            const accent = c.primary_color ?? 'var(--brand)'
            return (
              <li key={c.slug}>
                <Link
                  href={`/c/${c.slug}`}
                  className="group block h-full overflow-hidden rounded-[var(--radius)] border border-[var(--line)] bg-[var(--surface)] transition hover:border-[var(--line-strong)]"
                >
                  {/* Een streep in de kleur van de club. Genoeg om de kaarten
                      uit elkaar te houden zonder dat het platform van kleur
                      verandert bij elke club die erbij komt. */}
                  <span className="block h-1" style={{ background: accent }} />

                  <span className="flex items-center gap-3 px-4 pt-4">
                    <span
                      className="flex size-11 shrink-0 items-center justify-center overflow-hidden rounded-xl border border-[var(--line)]"
                      style={{ background: `color-mix(in oklab, ${accent} 10%, transparent)` }}
                    >
                      {c.logo_url ? (
                        // eslint-disable-next-line @next/next/no-img-element
                        <img src={c.logo_url} alt="" className="size-full object-contain" />
                      ) : (
                        <span className="text-lg font-semibold" style={{ color: accent }}>
                          {c.name.slice(0, 1)}
                        </span>
                      )}
                    </span>
                    <span className="min-w-0 flex-1">
                      <span className="block truncate font-semibold">{c.name}</span>
                      {c.city && (
                        <span className="block truncate text-xs text-[var(--text-faint)]">
                          {c.city}
                        </span>
                      )}
                    </span>
                    <span
                      aria-hidden
                      className="shrink-0 text-[var(--text-faint)] transition group-hover:translate-x-0.5 group-hover:text-[var(--text)]"
                    >
                      ›
                    </span>
                  </span>

                  {c.rank !== null ? (
                    <span className="mt-3 grid grid-cols-3 gap-px border-t border-[var(--line)] bg-[var(--line)]">
                      <Cell
                        label={t('pub.standings')}
                        value={String(c.rank)}
                        sub={`${t('common.of')} ${c.of_players}`}
                        accent={accent}
                      />
                      <Cell label={t('me.playedShort')} value={String(c.tournaments)} />
                      <Cell
                        label={t('me.won')}
                        value={
                          Number(c.prize_cents) > 0
                            ? formatMoney(Number(c.prize_cents), 'EUR')
                            : '—'
                        }
                      />
                    </span>
                  ) : (
                    <span className="mt-3 block border-t border-[var(--line)] px-4 py-3 text-xs text-[var(--text-faint)]">
                      {t('me.noneHereYet')}
                    </span>
                  )}
                </Link>
              </li>
            )
          })}
        </ul>
      )}

      <p className="mt-3 text-xs leading-relaxed text-[var(--text-faint)]">
        {t('me.clubsBody')}
      </p>

      {/* ------------------------------------------------------ ontdekken */}
      {open && (
        <div className="mt-4 rounded-[var(--radius)] border border-[var(--brand)] bg-[color-mix(in_oklab,var(--brand)_6%,transparent)] p-4 sm:p-5">
          <h3 className="font-semibold">{t('me.discoverTitle')}</h3>
          <p className="mt-1 text-sm leading-relaxed text-[var(--text-muted)]">
            {t('me.discoverBody')}
          </p>

          <ul className="mt-4 space-y-2">
            {discover.map((c) => {
              const on = picked.has(c.slug)
              return (
                <li key={c.slug}>
                  <label
                    className={`flex cursor-pointer items-center gap-3 rounded-[var(--radius)] border bg-[var(--bg)] p-3.5 transition ${
                      on ? 'border-[var(--brand)]' : 'border-[var(--line)] hover:border-[var(--line-strong)]'
                    }`}
                  >
                    <input
                      type="checkbox"
                      checked={on}
                      onChange={() =>
                        setPicked((prev) => {
                          const next = new Set(prev)
                          if (next.has(c.slug)) next.delete(c.slug)
                          else next.add(c.slug)
                          return next
                        })
                      }
                      className="size-4 shrink-0"
                    />
                    <span className="flex size-10 shrink-0 items-center justify-center overflow-hidden rounded-lg border border-[var(--line)] bg-[var(--surface-2)]">
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
                      <span className="block truncate text-xs text-[var(--text-faint)]">
                        {[c.city, `${c.members} ${t('join.members')}`].filter(Boolean).join(' · ')}
                      </span>
                    </span>
                  </label>
                </li>
              )
            })}
          </ul>

          <button
            type="button"
            disabled={busy || picked.size === 0}
            onClick={() => void join()}
            className="mt-4 w-full rounded-full bg-[var(--brand)] px-5 py-3 text-sm font-medium text-[var(--on-brand)] transition hover:brightness-110 disabled:opacity-40 sm:w-auto"
          >
            {busy
              ? t('common.busy')
              : `${t('join.confirm')}${picked.size > 0 ? ` (${picked.size})` : ''}`}
          </button>
        </div>
      )}
    </section>
  )
}

function Cell({
  label, value, sub, accent,
}: { label: string; value: string; sub?: string; accent?: string }) {
  return (
    <span className="block bg-[var(--surface)] px-2 py-2.5 text-center">
      <span className="block text-[0.55rem] uppercase tracking-[0.12em] text-[var(--text-faint)]">
        {label}
      </span>
      <span
        className="tnum mt-0.5 block text-sm font-semibold"
        style={accent ? { color: accent } : undefined}
      >
        {value}
      </span>
      {sub && <span className="block text-[0.6rem] text-[var(--text-faint)]">{sub}</span>}
    </span>
  )
}
