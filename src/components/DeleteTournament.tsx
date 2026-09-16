'use client'

import { useEffect, useState } from 'react'
import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { useT } from '@/lib/i18n/context'
import { dbMessage } from '@/lib/dbMessage'

/**
 * Een avond verwijderen.
 *
 * **Waarom het onderaan staat en er anders uitziet dan de rest.** Dit is de
 * enige knop in de app die iets weggooit dat niet terugkomt. Hij hoort niet
 * tussen de velden die je aanpast: wie een naam komt rechtzetten, mag hier niet
 * per ongeluk op klikken. Vandaar onderaan, apart, in de waarschuwkleur.
 *
 * **Eerst tellen, dan vragen.** De bevestiging noemt wat er precies verdwijnt —
 * zoveel deelnames, zoveel inschrijvingen, zoveel uitslagregels. "Weet je het
 * zeker?" is een vraag die niemand leest; "dit wist 12 deelnames en 12
 * uitslagregels" is er een die je wél tegenhoudt als het de verkeerde avond is.
 *
 * **En wie het niet mag, ziet het ook.** Een floor kan een avond zonder
 * geschiedenis wissen — rommel opruimen. Een avond waar gespeeld is, verandert
 * het klassement van de club, en dat blijft bij owner en admin. De databank
 * bewaakt dat; dit scherm zegt het alleen vooraf, zodat je niet op een knop
 * drukt die daarna weigert.
 */

interface Info {
  name: string
  status: string
  spelers: number
  inschrijvingen: number
  inkopen: number
  uitslagen: number
  mag_ik: boolean
}

export function DeleteTournament({
  clubSlug, tournamentId,
}: { clubSlug: string; tournamentId: string }) {
  const supabase = useState(() => createClient())[0]
  const router = useRouter()
  const t = useT()

  const [info, setInfo] = useState<Info | null>(null)
  const [open, setOpen] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    let weg = false
    void (async () => {
      const { data } = await supabase
        .rpc('tournament_delete_info', { p_tournament_id: tournamentId })
        .maybeSingle<Info>()
      if (!weg) setInfo(data ?? null)
    })()
    return () => { weg = true }
  }, [supabase, tournamentId])

  async function wis() {
    setBusy(true)
    setError(null)
    const { error: err } = await supabase.rpc('floor_delete_tournament', {
      p_tournament_id: tournamentId,
    })
    if (err) {
      setError(dbMessage(err, t))
      setBusy(false)
      return
    }
    // Terug naar het clubscherm: de pagina waar we op staan bestaat niet meer.
    router.replace(`/c/${clubSlug}`)
    router.refresh()
  }

  if (!info) return null

  const sporen = info.spelers + info.inkopen + info.uitslagen

  return (
    <section className="rounded-[var(--radius-lg)] border border-[color-mix(in_oklab,var(--danger)_35%,transparent)] p-5">
      <h2 className="text-sm font-semibold text-[var(--danger)]">{t('del.title')}</h2>

      {!open ? (
        <>
          <p className="mt-1.5 text-sm leading-relaxed text-[var(--text-muted)]">
            {sporen === 0 ? t('del.cleanBody') : t('del.playedBody')}
          </p>
          <button
            type="button"
            onClick={() => setOpen(true)}
            disabled={!info.mag_ik}
            className="mt-4 rounded-[var(--radius)] border border-[color-mix(in_oklab,var(--danger)_45%,transparent)] px-3 py-2 text-sm text-[var(--danger)] transition hover:bg-[color-mix(in_oklab,var(--danger)_12%,transparent)] disabled:cursor-not-allowed disabled:opacity-40"
          >
            {t('del.button')}
          </button>
          {!info.mag_ik && (
            <p className="mt-2 text-xs leading-relaxed text-[var(--text-faint)]">
              {t('del.notAllowed')}
            </p>
          )}
        </>
      ) : (
        <>
          <p className="mt-1.5 text-sm leading-relaxed">
            {t('del.confirm').replace('{name}', info.name)}
          </p>

          {/* Wat er precies verdwijnt. Alleen de regels die er zijn: op een
              avond zonder inkopen hoort er geen "0 inkopen" te staan. */}
          {sporen + info.inschrijvingen > 0 ? (
            <ul className="mt-3 space-y-1 text-sm text-[var(--text-muted)]">
              {info.spelers > 0 && <Regel n={info.spelers} tekst={t('del.players')} />}
              {info.inschrijvingen > 0 && <Regel n={info.inschrijvingen} tekst={t('del.rsvps')} />}
              {info.inkopen > 0 && <Regel n={info.inkopen} tekst={t('del.buyins')} />}
              {info.uitslagen > 0 && <Regel n={info.uitslagen} tekst={t('del.results')} />}
            </ul>
          ) : (
            <p className="mt-3 text-sm text-[var(--text-muted)]">{t('del.nothingAttached')}</p>
          )}

          {info.uitslagen > 0 && (
            <p className="mt-3 text-sm text-[var(--danger)]">{t('del.standingsWarn')}</p>
          )}

          {error && (
            <p className="mt-3 rounded-lg border border-[color-mix(in_oklab,var(--danger)_35%,transparent)] bg-[color-mix(in_oklab,var(--danger)_10%,transparent)] p-2.5 text-sm text-[var(--danger)]">
              {error}
            </p>
          )}

          <div className="mt-4 flex flex-wrap gap-2">
            <button
              type="button"
              onClick={() => void wis()}
              disabled={busy}
              className="rounded-[var(--radius)] bg-[var(--danger)] px-3 py-2 text-sm font-medium text-white transition hover:brightness-110 disabled:opacity-40"
            >
              {busy ? t('common.busy') : t('del.confirmButton')}
            </button>
            <button
              type="button"
              onClick={() => { setOpen(false); setError(null) }}
              disabled={busy}
              className="rounded-[var(--radius)] border border-[var(--line-strong)] px-3 py-2 text-sm transition hover:bg-[var(--surface-hover)] disabled:opacity-40"
            >
              {t('common.cancel')}
            </button>
          </div>
        </>
      )}
    </section>
  )
}

function Regel({ n, tekst }: { n: number; tekst: string }) {
  return (
    <li className="flex items-baseline gap-2">
      <span className="tnum font-medium text-[var(--text)]">{n}</span>
      <span>{tekst}</span>
    </li>
  )
}
