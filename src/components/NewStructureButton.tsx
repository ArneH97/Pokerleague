'use client'

import { useMemo, useState } from 'react'
import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { Button } from '@/components/ui'
import { useT } from '@/lib/i18n/context'
import { dbMessage } from '@/lib/dbMessage'

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
  const t = useT()
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function create() {
    setBusy(true)
    setError(null)

    if (copyFrom) {
      const { data, error: err } = await supabase.rpc('duplicate_blind_structure', {
        p_structure_id: copyFrom,
        p_club_id: clubId,
        p_name: suggestedName ?? t('struct.copySuffix'),
      })
      if (err) { setError(dbMessage(err, t)); setBusy(false); return }
      router.push(`/c/${clubSlug}/structuren/${data as string}`)
      return
    }

    const { data, error: err } = await supabase
      .from('blind_structures')
      .insert({ club_id: clubId, name: t('struct.newName') })
      .select('id')
      .single<{ id: string }>()

    if (err) {
      setError(
        err.code === '42501' || err.message.includes('row-level security')
          ? t('struct.noRightsCreate')
          : dbMessage(err, t),
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
        {busy ? t('common.busy') : (label ?? t('struct.new'))}
      </Button>
      {error && <span className="text-xs text-[var(--danger)]">{error}</span>}
    </div>
  )
}
