'use client'

import { useCallback, useEffect, useState } from 'react'

import { createClient } from '@/lib/supabase/client'
import { useT } from '@/lib/i18n/context'

/**
 * Wat er met de uitnodigingen van deze club gebeurd is.
 *
 * Dit paneel bestaat omdat het versturen vier keer stilzwijgend niets deed en
 * niemand kon zien waaróm. Dat is de eigenlijke fout geweest — niet de
 * ontbrekende sleutel of het gat in `floor_add_entry`, maar dat een club geen
 * enkele manier had om te zien of haar post buiten was.
 *
 * Dus staat hier de stand, en bij een mislukking de letterlijke foutmelding
 * van de bezorgdienst. Bij een adres met een typfout is dat het enige wat
 * helpt: dan weet de floor dat hij het aan de deur moet vragen.
 *
 * De knop is er voor het ongeduld. Normaal vertrekt alles vanzelf — meteen
 * nadat de floor iemand toevoegt, en anders door de cronjob. Maar wie net
 * iemand ingeschreven heeft en wil weten of het werkte, hoort niet te moeten
 * wachten op een klok die hij niet ziet.
 */

interface Row {
  id: string
  email: string
  player_name: string
  created_at: string
  sent_at: string | null
  accepted_at: string | null
  attempts: number
  last_error: string | null
}

export function InvitePanel({ clubId, locale }: { clubId: string; locale: string }) {
  const t = useT()
  const [rows, setRows] = useState<Row[] | null>(null)
  const [busy, setBusy] = useState(false)
  const [result, setResult] = useState<string | null>(null)

  const load = useCallback(async () => {
    const supabase = createClient()
    const { data } = await supabase.rpc('club_invites', { p_club_id: clubId })
    setRows((data ?? []) as unknown as Row[])
  }, [clubId])

  useEffect(() => {
    // De uitkomst van een netwerkvraag, geen afgeleide van wat er al op het
    // scherm staat — daarom hoort dit hier en niet in de render.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    void load()
  }, [load])

  async function sendNow() {
    setBusy(true)
    setResult(null)
    try {
      const res = await fetch('/api/invites/send', { method: 'POST' })
      const body = (await res.json()) as { sent?: number; failed?: number; error?: string }
      setResult(
        body.error
          ? body.error
          : `${body.sent ?? 0} ${t('invites.sentNow')}${
              body.failed ? ` · ${body.failed} ${t('invites.failedNow')}` : ''
            }`,
      )
    } catch {
      setResult(t('invites.noReply'))
    }
    await load()
    setBusy(false)
  }

  if (rows === null) return null

  const open = rows.filter((r) => !r.sent_at && !r.accepted_at && r.attempts < 3)
  const stuck = rows.filter((r) => !r.sent_at && !r.accepted_at && r.attempts >= 3)
  const sent = rows.filter((r) => r.sent_at && !r.accepted_at)
  const done = rows.filter((r) => r.accepted_at)

  // Niets te melden en niets te doen: dan hoort hier ook niets te staan.
  if (rows.length === 0) return null

  const fmt = new Intl.DateTimeFormat(`${locale}-BE`, {
    day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit',
    timeZone: 'Europe/Brussels',
  })

  return (
    <section className="rounded-[var(--radius)] border border-[var(--line)] bg-[var(--surface)] p-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h2 className="text-xs uppercase tracking-[0.22em] text-[var(--text-faint)]">
            {t('invites.title')}
          </h2>
          <p className="tnum mt-1 text-sm text-[var(--text-muted)]">
            {open.length} {t('invites.waiting')} · {sent.length} {t('invites.sent')} ·{' '}
            {done.length} {t('invites.accepted')}
            {stuck.length > 0 && (
              <span className="text-[var(--danger)]"> · {stuck.length} {t('invites.stuck')}</span>
            )}
          </p>
        </div>

        <div className="flex items-center gap-3">
          {result && <span className="text-sm text-[var(--text-muted)]">{result}</span>}
          <button
            type="button"
            onClick={() => void sendNow()}
            disabled={busy || open.length === 0}
            className="rounded-[var(--radius)] border border-[var(--line-strong)] px-3.5 py-2 text-sm transition hover:bg-[var(--surface-hover)] disabled:opacity-40"
          >
            {busy ? t('common.busy') : t('invites.sendNow')}
          </button>
        </div>
      </div>

      {/* Alleen wat aandacht vraagt. Een lijst van alles wat goed ging is een
          lijst die niemand leest. */}
      {stuck.length > 0 && (
        <ul className="mt-3 space-y-1.5 border-t border-[var(--line)] pt-3">
          {stuck.map((r) => (
            <li key={r.id} className="text-sm">
              <span className="text-[var(--danger)]">{r.email}</span>
              <span className="text-[var(--text-faint)]"> — {r.player_name}</span>
              {r.last_error && (
                <span className="block text-xs text-[var(--text-faint)]">{r.last_error}</span>
              )}
            </li>
          ))}
          <li className="pt-1 text-xs leading-relaxed text-[var(--text-faint)]">
            {t('invites.stuckHint')}
          </li>
        </ul>
      )}

      {open.length > 0 && stuck.length === 0 && (
        <p className="mt-3 border-t border-[var(--line)] pt-3 text-xs text-[var(--text-faint)]">
          {t('invites.oldest')} {fmt.format(new Date(open[open.length - 1].created_at))}
        </p>
      )}
    </section>
  )
}
