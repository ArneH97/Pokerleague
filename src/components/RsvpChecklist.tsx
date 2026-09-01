'use client'

import { useMemo, useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { useT } from '@/lib/i18n/context'
import { dbMessage } from '@/lib/dbMessage'

/**
 * De lijst met wie vooraf inschreef, met de twee knoppen die erbij horen.
 *
 * Twee schermen tonen dezelfde mensen om een andere reden, en dat is precies
 * waarom dit één component is en geen twee. Op de tornooipagina kijk je er
 * dagen op voorhand naar: hoeveel volk komt er, en klopt die lijst nog. Op het
 * floorscherm werk je hem af terwijl er mensen voor je staan. Zouden die twee
 * uit elkaar lopen, dan zou je op de ene plek iemand kunnen schrappen die op
 * de andere blijft staan.
 *
 * **"Aan tafel" staat alleen op de floor.** Iemand inschrijven boekt zijn
 * inleg, en die knop hoort dus niet op een overzichtspagina waar je aan het
 * kijken bent en niet aan het werken.
 *
 * Het kruisje trekt de inschrijving in; het verwijdert de rij niet. Iemand die
 * belt dat hij toch komt, schrijft zich gewoon opnieuw in en belandt op
 * dezelfde regel.
 */

export interface RsvpRow {
  playerId: string
  name: string
  email: string | null
  hasAccount: boolean
}

export function RsvpChecklist({
  rows, tournamentId, onSeat, onChanged, busy = false, tone = 'plain',
}: {
  rows: RsvpRow[]
  tournamentId: string
  /** Alleen meegeven op het floorscherm. Zonder dit staat er geen zitknop. */
  onSeat?: (playerId: string) => void | Promise<void>
  /** De lijst opnieuw ophalen nadat er iets veranderde. */
  onChanged: () => void | Promise<void>
  busy?: boolean
  /** 'floor' zet de regels op een eigen vlak; op een kaart hoeft dat niet. */
  tone?: 'plain' | 'floor'
}) {
  const supabase = useMemo(() => createClient(), [])
  const t = useT()
  const [pending, setPending] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [asking, setAsking] = useState<string | null>(null)

  async function remove(playerId: string) {
    setPending(playerId)
    setError(null)
    const { error: err } = await supabase.rpc('cancel_rsvp', {
      p_tournament_id: tournamentId,
      p_player_id: playerId,
    })
    if (err) setError(dbMessage(err, t))
    setAsking(null)
    await onChanged()
    setPending(null)
  }

  return (
    <>
      <ul className={tone === 'floor' ? 'space-y-1.5' : 'divide-y divide-[var(--line)]'}>
        {rows.map((r) => (
          <li
            key={r.playerId}
            className={
              tone === 'floor'
                ? 'flex items-center gap-2 rounded-xl bg-[var(--surface-2)] px-3.5 py-2.5'
                : 'flex items-center gap-2 px-4 py-2.5'
            }
          >
            <span className="min-w-0 flex-1">
              <span className="block truncate font-medium">{r.name}</span>
              {r.email && (
                <span className="block truncate text-xs text-[var(--text-faint)]">{r.email}</span>
              )}
            </span>

            {tone !== 'floor' && !r.hasAccount && (
              <span className="hidden shrink-0 rounded-full border border-[var(--line-strong)] px-2 py-0.5 text-[0.65rem] text-[var(--text-faint)] sm:inline">
                {t('rsvpList.noAccount')}
              </span>
            )}

            {/* Bevestigen, maar zonder venster. Een dialoog midden op een avond
                is een klik extra én een scherm dat de rest afdekt; twee knoppen
                op dezelfde regel zijn even veilig en storen niemand. */}
            {asking === r.playerId ? (
              <span className="flex shrink-0 items-center gap-1.5">
                <button
                  type="button"
                  disabled={pending !== null}
                  onClick={() => void remove(r.playerId)}
                  className="rounded-full border border-[var(--danger)] px-3 py-1.5 text-xs font-medium text-[var(--danger)] transition hover:bg-[var(--surface-hover)] disabled:opacity-40"
                >
                  {t('rsvpList.removeYes')}
                </button>
                <button
                  type="button"
                  onClick={() => setAsking(null)}
                  className="rounded-full px-2.5 py-1.5 text-xs text-[var(--text-faint)] transition hover:text-[var(--text)]"
                >
                  {t('common.cancel')}
                </button>
              </span>
            ) : (
              <>
                {onSeat && (
                  <button
                    type="button"
                    disabled={busy || pending !== null}
                    onClick={() => void onSeat(r.playerId)}
                    className="shrink-0 rounded-full bg-[var(--brand)] px-4 py-2 text-sm font-medium text-[var(--on-brand)] transition hover:brightness-110 disabled:opacity-40"
                  >
                    {t('rsvpList.seat')}
                  </button>
                )}
                <button
                  type="button"
                  aria-label={t('rsvpList.remove')}
                  title={t('rsvpList.remove')}
                  disabled={busy || pending !== null}
                  onClick={() => setAsking(r.playerId)}
                  className="flex size-9 shrink-0 items-center justify-center rounded-full text-[var(--text-faint)] transition hover:bg-[var(--surface-hover)] hover:text-[var(--danger)] disabled:opacity-40"
                >
                  <svg viewBox="0 0 24 24" aria-hidden className="size-4" fill="none"
                       stroke="currentColor" strokeWidth="2" strokeLinecap="round">
                    <path d="M6 6l12 12M18 6L6 18" />
                  </svg>
                </button>
              </>
            )}
          </li>
        ))}
      </ul>

      {error && <p className="mt-2 px-1 text-sm text-[var(--danger)]">{error}</p>}
    </>
  )
}
