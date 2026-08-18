'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { joinClubs } from '@/lib/joinActions'
import { useT } from '@/lib/i18n/context'

/**
 * De andere clubs, meteen na het aansluiten bij de eerste.
 *
 * Dit is het enige moment waarop dit aanbod niet opdringerig is: iemand heeft
 * net besloten dat hij ergens bij wil horen, en de vraag "waar nog?" volgt
 * dan vanzelf. Een week later op een willekeurig scherm zou dezelfde lijst
 * reclame zijn.
 *
 * Vinkjes en één knop, geen rij losse knoppen die elk een pagina herladen.
 * Wie er drie wil, doet dat in één beweging — en wie er geen wil, klikt door
 * zonder iets aan te raken.
 */

export interface JoinableClub {
  slug: string
  name: string
  city: string | null
  logo_url: string | null
  intro: string | null
  members: number
}

export function JoinClubs({ clubs }: { clubs: JoinableClub[] }) {
  const t = useT()
  const router = useRouter()
  const [picked, setPicked] = useState<Set<string>>(new Set())
  const [busy, setBusy] = useState(false)

  if (clubs.length === 0) return null

  function toggle(slug: string) {
    setPicked((prev) => {
      const next = new Set(prev)
      if (next.has(slug)) next.delete(slug)
      else next.add(slug)
      return next
    })
  }

  async function confirm() {
    setBusy(true)
    await joinClubs([...picked])
    router.push('/ik')
    router.refresh()
  }

  return (
    <section className="mt-6">
      <h2 className="text-xs uppercase tracking-[0.22em] text-[var(--text-faint)]">
        {t('join.moreTitle')}
      </h2>
      <p className="mt-2 max-w-prose text-sm leading-relaxed text-[var(--text-muted)]">
        {t('join.moreBody')}
      </p>

      <ul className="mt-4 space-y-2">
        {clubs.map((c) => {
          const on = picked.has(c.slug)
          return (
            <li key={c.slug}>
              <label
                className={`flex cursor-pointer items-center gap-4 rounded-[var(--radius)] border p-4 transition ${
                  on
                    ? 'border-[var(--brand)] bg-[color-mix(in_oklab,var(--brand)_10%,transparent)]'
                    : 'border-[var(--line)] bg-[var(--surface)] hover:border-[var(--line-strong)]'
                }`}
              >
                <input
                  type="checkbox"
                  checked={on}
                  onChange={() => toggle(c.slug)}
                  className="size-4 shrink-0"
                />
                <span className="flex size-11 shrink-0 items-center justify-center overflow-hidden rounded-xl border border-[var(--line)] bg-[var(--bg)]">
                  {c.logo_url ? (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img src={c.logo_url} alt="" className="size-full object-contain" />
                  ) : (
                    <span className="text-lg font-semibold text-[var(--brand)]">
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

      <div className="mt-5 flex flex-wrap items-center gap-4">
        <button
          type="button"
          disabled={busy || picked.size === 0}
          onClick={() => void confirm()}
          className="rounded-full bg-[var(--brand)] px-5 py-2.5 text-sm font-medium text-[var(--on-brand)] transition hover:brightness-110 disabled:opacity-40"
        >
          {busy
            ? t('common.busy')
            : `${t('join.confirm')}${picked.size > 0 ? ` (${picked.size})` : ''}`}
        </button>
        <button
          type="button"
          disabled={busy}
          onClick={() => router.push('/ik')}
          className="text-sm text-[var(--text-muted)] underline-offset-4 hover:underline"
        >
          {t('join.skip')}
        </button>
      </div>
    </section>
  )
}
