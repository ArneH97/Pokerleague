'use client'

import { useMemo, useState } from 'react'
import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { useT } from '@/lib/i18n/context'
import { dbMessage } from '@/lib/dbMessage'

/**
 * "Ik kom" voor iemand die al aangemeld is.
 *
 * Het inschrijfformulier op de affichepagina vraagt naam, adres en
 * geboortedatum. Voor een lid dat al binnen is, zijn dat drie vragen waarvan
 * het platform het antwoord al heeft — en drie kansen om af te haken. Dus één
 * knop, en dezelfde knop draait het weer terug.
 *
 * Afzeggen staat er even prominent als inschrijven, en dat is met opzet. Een
 * lijst waar mensen op blijven staan omdat ze er niet af kunnen, is precies zo
 * onbruikbaar als geen lijst — en dan blijft de floor gokken hoeveel tafels
 * hij moet zetten.
 */
export function RsvpToggle({
  tournamentId, isIn, size = 'md',
}: {
  tournamentId: string
  isIn: boolean
  size?: 'sm' | 'md'
}) {
  const supabase = useMemo(() => createClient(), [])
  const router = useRouter()
  const t = useT()
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function toggle(e: React.MouseEvent) {
    // De knop zit in een rij die zelf een link is. Zonder dit navigeer je weg
    // op het moment dat je inschrijft.
    e.preventDefault()
    e.stopPropagation()

    setBusy(true)
    setError(null)
    const { error: err } = isIn
      ? await supabase.rpc('cancel_my_rsvp', { p_tournament_id: tournamentId })
      : await supabase.rpc('rsvp_as_me', { p_tournament_id: tournamentId })
    if (err) setError(dbMessage(err, t))
    setBusy(false)
    router.refresh()
  }

  const pad = size === 'sm' ? 'px-3.5 py-2 text-xs' : 'px-5 py-2.5 text-sm'

  return (
    <span className="inline-flex flex-col items-end gap-1">
      <button
        type="button"
        onClick={(e) => void toggle(e)}
        disabled={busy}
        className={`shrink-0 whitespace-nowrap rounded-full font-medium transition disabled:opacity-40 ${pad} ${
          isIn
            ? 'border border-[var(--line-strong)] text-[var(--text-muted)] hover:bg-[var(--surface-hover)]'
            : 'bg-[var(--brand)] text-[var(--on-brand)] hover:brightness-110'
        }`}
      >
        {busy ? t('common.busy') : isIn ? t('cal.rsvpOut') : t('cal.rsvpIn')}
      </button>
      {error && <span className="text-xs text-[var(--danger)]">{error}</span>}
    </span>
  )
}
