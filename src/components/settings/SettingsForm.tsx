'use client'

import { useActionState } from 'react'
import { useT } from '@/lib/i18n/context'

type Result = { ok: true } | { ok: false; error: string }
type Action = (prev: Result | null, fd: FormData) => Promise<Result>

/**
 * Eén blok instellingen met zijn eigen bewaarknop.
 *
 * Bewust per blok en niet één knop onderaan de hele pagina. Wie de kleur van
 * de club aanpast wil niet het gevoel hebben dat hij tegelijk het gedoogbeleid
 * mee wegschrijft, en een fout in het ene blok hoort het andere niet tegen te
 * houden.
 *
 * De knop staat onderaan en niet bovenaan: je leest eerst wat je verandert.
 * Na het bewaren blijft de melding staan tot je iets anders doet — een
 * bevestiging die na twee seconden verdwijnt heb je net gemist wanneer je
 * naar het veld keek dat je aanpaste.
 */
export function SettingsForm({
  action, title, description, children, danger,
}: {
  action: Action
  title: string
  description?: string
  children: React.ReactNode
  /** Voor blokken waar een vergissing gevolgen heeft, zoals het gedoogbeleid. */
  danger?: boolean
}) {
  const t = useT()
  const [state, formAction, pending] = useActionState(action, null)

  return (
    <form
      action={formAction}
      className={`rounded-[var(--radius)] border p-5 sm:p-6 ${
        danger
          ? 'border-[color-mix(in_oklab,var(--warn)_35%,transparent)] bg-[color-mix(in_oklab,var(--warn)_5%,transparent)]'
          : 'border-[var(--line)] bg-[var(--surface)]'
      }`}
    >
      <h2 className="text-lg font-semibold">{title}</h2>
      {description && (
        <p className="mt-1 max-w-prose text-sm leading-relaxed text-[var(--text-muted)]">
          {description}
        </p>
      )}

      <div className="mt-5 space-y-4">{children}</div>

      <div className="mt-6 flex flex-wrap items-center gap-3">
        <button
          type="submit"
          disabled={pending}
          className="rounded-[var(--radius)] bg-[var(--brand)] px-4 py-2.5 text-sm font-medium text-[var(--on-brand)] transition hover:brightness-110 disabled:opacity-45"
        >
          {pending ? t('common.saving') : t('common.save')}
        </button>

        {state?.ok === true && (
          <span className="text-sm text-[var(--ok)]">{t('common.saved')}</span>
        )}
        {state?.ok === false && (
          <span className="text-sm text-[var(--danger)]">{state.error}</span>
        )}
      </div>
    </form>
  )
}
