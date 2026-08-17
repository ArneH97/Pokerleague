'use client'

import { useMemo, useState } from 'react'
import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { Button } from '@/components/ui'

/**
 * Maakt een nieuwe blindstructuur aan en gaat er meteen naartoe.
 *
 * Zonder tussenpagina: een formulier met alleen een naamveld is een klik te
 * veel. Je landt in de editor en kan de naam daar aanpassen.
 */
export function NewStructureButton({
  clubId, clubSlug, copyFrom, label = 'Nieuwe structuur', suggestedName,
}: {
  clubId: string
  clubSlug: string
  copyFrom?: string
  label?: string
  suggestedName?: string
}) {
  const router = useRouter()
  const supabase = useMemo(() => createClient(), [])
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function create() {
    setBusy(true)
    setError(null)

    if (copyFrom) {
      const { data, error: err } = await supabase.rpc('duplicate_blind_structure', {
        p_structure_id: copyFrom,
        p_club_id: clubId,
        p_name: suggestedName ?? 'Kopie',
      })
      if (err) { setError(err.message); setBusy(false); return }
      router.push(`/c/${clubSlug}/structuren/${data as string}`)
      return
    }

    const { data, error: err } = await supabase
      .from('blind_structures')
      .insert({ club_id: clubId, name: 'Nieuwe structuur' })
      .select('id')
      .single<{ id: string }>()

    if (err) {
      setError(
        err.code === '42501' || err.message.includes('row-level security')
          ? 'Geen rechten om structuren aan te maken.'
          : err.message,
      )
      setBusy(false)
      return
    }
    router.push(`/c/${clubSlug}/structuren/${data.id}`)
  }

  return (
    <div className="flex flex-col items-end gap-1">
      <Button
        variant={copyFrom ? 'ghost' : 'brand'}
        size="sm"
        onClick={create}
        disabled={busy}
      >
        {busy ? 'Bezig…' : label}
      </Button>
      {error && <span className="text-xs text-[var(--danger)]">{error}</span>}
    </div>
  )
}
