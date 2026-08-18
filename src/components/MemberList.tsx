'use client'

import { useMemo, useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { formatMoney } from '@/lib/types'
import { useT } from '@/lib/i18n/context'
import { dbMessage } from '@/lib/dbMessage'

/**
 * Het ledenbestand van een club.
 *
 * Twee dingen die de club hiermee doet, en waar de indeling op gebouwd is:
 * iemand terugvinden, en de gaten dichten. Dat tweede is niet cosmetisch —
 * een speler zonder mailadres kan je niet uitnodigen, en zijn resultaten bij
 * een tweede club tellen niet als dezelfde persoon. Vandaar dat die groep
 * bovenaan staat in plaats van verstopt tussen de rest.
 *
 * Het saldo per speler is bewust ingelegd minus gewonnen, over alles heen.
 * Dat is een cijfer waar een clubeigenaar naar kijkt bij het inschatten van
 * wie er blijft komen — niet iets om aan de speler zelf te tonen.
 */

export interface Member {
  playerId: string
  name: string
  username: string | null
  email: string | null
  noEmailReason: string | null
  linkState: string
  entries: number
  lastPlayed: string | null
  bestPosition: number | null
  cashes: number
  totalPrize: number
  totalSpent: number
  knockouts: number
}

export function MemberList({
  clubId, currency, locale, initial,
}: {
  clubId: string
  currency: string
  locale: string
  initial: Member[]
}) {
  const supabase = useMemo(() => createClient(), [])
  const t = useT()
  const [members, setMembers] = useState(initial)
  const [query, setQuery] = useState('')
  const [editing, setEditing] = useState<string | null>(null)
  const [email, setEmail] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const needle = query.trim().toLowerCase()
  const shown = needle === ''
    ? members
    : members.filter((m) =>
        m.name.toLowerCase().includes(needle) ||
        (m.email ?? '').toLowerCase().includes(needle) ||
        (m.username ?? '').toLowerCase().includes(needle))

  const missing = members.filter((m) => m.email === null)

  const fmtDate = new Intl.DateTimeFormat(`${locale}-BE`, {
    day: 'numeric', month: 'short', year: 'numeric',
  })

  async function saveEmail(playerId: string) {
    setBusy(true)
    setError(null)
    const { data, error: err } = await supabase.rpc('set_player_email', {
      p_player_id: playerId,
      p_email: email.trim(),
      p_club_id: clubId,
    })

    if (err) {
      setError(dbMessage(err, t))
      setBusy(false)
      return
    }

    // De functie geeft een ánder spelers-id terug wanneer dit adres al bij
    // iemand bestaat. Dan is dit dezelfde persoon en moeten die twee
    // samengevoegd worden — dat doen we niet stilzwijgend.
    if (typeof data === 'string' && data !== playerId) {
      setError(t('members.emailTaken'))
      setBusy(false)
      return
    }

    setMembers((list) => list.map((m) =>
      m.playerId === playerId ? { ...m, email: email.trim().toLowerCase(), noEmailReason: null, linkState: 'invited' } : m))
    setEditing(null)
    setEmail('')
    setBusy(false)
  }

  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <input
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder={t('members.search')}
          autoComplete="off"
          className="min-w-0 max-w-md flex-1 rounded-[var(--radius)] border border-[var(--line)] bg-[var(--surface)] px-4 py-2.5 text-sm outline-none placeholder:text-[var(--text-faint)] focus:border-[var(--brand)]"
        />
        <p className="tnum text-sm text-[var(--text-faint)]">
          {members.length} {t('members.count')}
        </p>
      </div>

      {/* De gaten eerst. Deze lijst hoort leeg te zijn; zolang dat niet zo is
          is er werk. */}
      {missing.length > 0 && needle === '' && (
        <div className="rounded-[var(--radius-lg)] border border-[color-mix(in_oklab,var(--warn)_35%,transparent)] bg-[color-mix(in_oklab,var(--warn)_8%,transparent)] p-4">
          <p className="text-sm font-medium text-[var(--warn)]">
            {t('members.missingEmail')} · {missing.length}
          </p>
          <p className="mt-1 max-w-2xl text-xs leading-relaxed text-[var(--text-muted)]">
            {t('members.missingEmailBody')}
          </p>
          <ul className="mt-3 space-y-1.5">
            {missing.map((m) => (
              <li key={m.playerId} className="flex flex-wrap items-center gap-2">
                <span className="min-w-0 flex-1 truncate text-sm">
                  {m.name}
                  {m.noEmailReason && (
                    <span className="ml-2 text-xs text-[var(--text-faint)]">
                      {m.noEmailReason}
                    </span>
                  )}
                </span>
                {editing === m.playerId ? (
                  <span className="flex items-center gap-1.5">
                    <input
                      autoFocus
                      type="email"
                      inputMode="email"
                      autoComplete="off"
                      autoCapitalize="off"
                      spellCheck={false}
                      value={email}
                      onChange={(e) => setEmail(e.target.value)}
                      onKeyDown={(e) => { if (e.key === 'Enter') void saveEmail(m.playerId) }}
                      className="w-56 rounded-lg border border-[var(--line-strong)] bg-[var(--surface)] px-3 py-1.5 text-sm outline-none focus:border-[var(--brand)]"
                    />
                    <button
                      type="button"
                      disabled={busy}
                      onClick={() => void saveEmail(m.playerId)}
                      className="rounded-lg bg-[var(--brand)] px-3 py-1.5 text-sm font-medium text-[var(--on-brand)] transition hover:brightness-110 disabled:opacity-45"
                    >
                      {t('common.save')}
                    </button>
                    <button
                      type="button"
                      onClick={() => { setEditing(null); setError(null) }}
                      className="rounded-lg border border-[var(--line-strong)] px-3 py-1.5 text-sm"
                    >
                      {t('common.cancel')}
                    </button>
                  </span>
                ) : (
                  <button
                    type="button"
                    onClick={() => { setEditing(m.playerId); setEmail(''); setError(null) }}
                    className="rounded-lg border border-[var(--line-strong)] px-3 py-1.5 text-sm transition hover:bg-[var(--surface-hover)]"
                  >
                    {t('members.addEmail')}
                  </button>
                )}
              </li>
            ))}
          </ul>
          {error && <p className="mt-2 text-sm text-[var(--danger)]">{error}</p>}
        </div>
      )}

      {shown.length === 0 ? (
        <p className="rounded-[var(--radius-lg)] border border-dashed border-[var(--line-strong)] p-8 text-center text-sm text-[var(--text-muted)]">
          {needle === '' ? t('members.noneBody') : t('members.noMatches')}
        </p>
      ) : (
        <div className="overflow-x-auto rounded-[var(--radius-lg)] border border-[var(--line)]">
          <table className="w-full min-w-[52rem] text-sm">
            <thead>
              <tr className="border-b border-[var(--line)] text-left text-xs uppercase tracking-widest text-[var(--text-faint)]">
                <th className="px-4 py-2.5 font-medium">{t('members.player')}</th>
                <th className="px-4 py-2.5 text-right font-medium">{t('members.entries')}</th>
                <th className="px-4 py-2.5 text-right font-medium">{t('members.best')}</th>
                <th className="px-4 py-2.5 text-right font-medium">{t('members.cashes')}</th>
                <th className="px-4 py-2.5 text-right font-medium">{t('members.spent')}</th>
                <th className="px-4 py-2.5 text-right font-medium">{t('members.won')}</th>
                <th className="px-4 py-2.5 text-right font-medium">{t('members.balance')}</th>
                <th className="px-4 py-2.5 text-right font-medium">{t('members.lastPlayed')}</th>
              </tr>
            </thead>
            <tbody>
              {shown.map((m) => {
                const balance = m.totalPrize - m.totalSpent
                return (
                  <tr key={m.playerId} className="border-b border-[var(--line)] last:border-0">
                    <td className="px-4 py-2.5">
                      <span className="flex flex-wrap items-center gap-x-2">
                        <span className="font-medium">{m.name}</span>
                        {m.linkState === 'claimed' && (
                          <span className="rounded px-1.5 py-0.5 text-[0.65rem] uppercase tracking-wider text-[var(--ok)] ring-1 ring-[color-mix(in_oklab,var(--ok)_35%,transparent)]">
                            {t('members.claimed')}
                          </span>
                        )}
                        {m.email === null && (
                          <span className="rounded px-1.5 py-0.5 text-[0.65rem] uppercase tracking-wider text-[var(--warn)] ring-1 ring-[color-mix(in_oklab,var(--warn)_35%,transparent)]">
                            {t('players.noEmailBadge')}
                          </span>
                        )}
                      </span>
                      {m.email && (
                        <span className="block truncate text-xs text-[var(--text-faint)]">{m.email}</span>
                      )}
                    </td>
                    <td className="tnum px-4 py-2.5 text-right text-[var(--text-muted)]">{m.entries}</td>
                    <td className="tnum px-4 py-2.5 text-right text-[var(--text-muted)]">
                      {m.bestPosition ?? '—'}
                    </td>
                    <td className="tnum px-4 py-2.5 text-right text-[var(--text-muted)]">{m.cashes}</td>
                    <td className="tnum px-4 py-2.5 text-right text-[var(--text-muted)]">
                      {m.totalSpent > 0 ? formatMoney(m.totalSpent, currency) : '—'}
                    </td>
                    <td className="tnum px-4 py-2.5 text-right text-[var(--text-muted)]">
                      {m.totalPrize > 0 ? formatMoney(m.totalPrize, currency) : '—'}
                    </td>
                    <td
                      className="tnum px-4 py-2.5 text-right font-medium"
                      style={{ color: balance > 0 ? 'var(--ok)' : balance < 0 ? 'var(--text-muted)' : undefined }}
                    >
                      {m.entries === 0 ? '—' : formatMoney(balance, currency)}
                    </td>
                    <td className="tnum px-4 py-2.5 text-right text-[var(--text-faint)]">
                      {m.lastPlayed ? fmtDate.format(new Date(m.lastPlayed)) : t('members.never')}
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}
