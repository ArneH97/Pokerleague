'use client'

import { Suspense, useState } from 'react'
import { useRouter, useSearchParams } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { Button, Card, Field, Notice, inputClass } from '@/components/ui'
import { useT } from '@/lib/i18n/context'

/**
 * Aanmelden met e-mail en wachtwoord.
 *
 * Bewust geen magic link: die vereist dat je op de zaalwifi je mailbox kan
 * openen, en dat is precies het moment waarop het misgaat. Een wachtwoord
 * werkt ook als de verbinding hapert.
 *
 * Dezelfde component dient de clubomgeving en het spelersplatform; alleen de
 * naam erboven verschilt. Eén account, twee gezichten — dezelfde persoon kan
 * staf zijn bij een club én speler op het platform.
 */
interface Props {
  /** Wat er boven het formulier staat. Bij een club is dat de clubnaam. */
  brandName: string
  logoUrl?: string | null
  /** Waar naartoe na aanmelden, als er geen ?next= in de URL staat. */
  fallbackNext: string
  /** Gebruik de clubkleur voor de knop. */
  branded?: boolean
  /**
   * De uitweg voor wie hier per ongeluk staat.
   *
   * Het clubdomein is werkgereedschap geworden, dus wie app.cutoff.be intypt
   * zonder er te werken belandt op dit scherm. Zonder deze regel is dat een
   * doodlopende straat met een wachtwoordveld — en dan denkt iemand dat hij
   * een wachtwoord vergeten is terwijl hij gewoon op het verkeerde adres is.
   */
  playerHref?: string
  playerLabel?: string
  /**
   * Alleen de kaart, zonder eigen paginahoogte en zonder kop.
   *
   * De voorpagina van het platform is nu een aanmeldscherm met de uitleg
   * ernaast. Daar hoort dit formulier ín te staan en niet als losse pagina die
   * zichzelf over het hele scherm uitrekt.
   */
  bare?: boolean
}

function Form({
  brandName, logoUrl, fallbackNext, branded, playerHref, playerLabel, bare,
}: Props) {
  const router = useRouter()
  const params = useSearchParams()
  const t = useT()
  const next = params.get('next') ?? fallbackNext

  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault()
    setBusy(true)
    setError(null)

    const supabase = createClient()
    const { error: err } = await supabase.auth.signInWithPassword({ email, password })

    if (err) {
      setError(
        err.message === 'Invalid login credentials'
          ? t('login.badCredentials')
          : err.message,
      )
      setBusy(false)
      return
    }

    router.push(next)
    router.refresh()
  }

  return (
    <main className={bare ? '' : 'flex min-h-dvh items-center justify-center px-5 py-10'}>
      <div className={bare ? 'w-full' : 'w-full max-w-sm'}>
        <div className={`mb-7 flex flex-col items-center gap-4 text-center${bare ? ' hidden' : ''}`}>
          {logoUrl ? (
            <>
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={logoUrl} alt={brandName} className="h-24 w-auto max-w-[13rem] object-contain" />
              <h1 className="sr-only">{brandName}</h1>
            </>
          ) : (
            <p className="text-[0.7rem] font-medium uppercase tracking-[0.18em] text-[var(--text-faint)]">
              {brandName}
            </p>
          )}
          <h2 className="text-2xl font-semibold tracking-tight">{t('common.signIn')}</h2>
        </div>

        <Card>
          <form onSubmit={onSubmit} className="space-y-4">
            <Field label={t('common.email')}>
              <input
                type="email"
                required
                autoComplete="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                className={inputClass}
              />
            </Field>

            <Field label={t('common.password')}>
              <input
                type="password"
                required
                autoComplete="current-password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                className={inputClass}
              />
            </Field>

            {error && <Notice tone="error">{error}</Notice>}

            <Button
              type="submit"
              size="lg"
              variant={branded ? 'brand' : 'brand'}
              disabled={busy}
              className="w-full"
            >
              {busy ? t('common.busy') : t('common.signIn')}
            </Button>
          </form>
        </Card>

        {playerHref && (
          <p className="mt-5 text-center text-sm leading-relaxed text-[var(--text-muted)]">
            {t('login.playerHere')}{' '}
            <a
              href={playerHref}
              className="text-[var(--brand)] underline-offset-4 hover:underline"
            >
              {playerLabel} →
            </a>
          </p>
        )}
      </div>
    </main>
  )
}

export function LoginForm(props: Props) {
  return (
    <Suspense fallback={<main className="min-h-dvh" />}>
      <Form {...props} />
    </Suspense>
  )
}
