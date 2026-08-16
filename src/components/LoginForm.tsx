'use client'

import { Suspense, useState } from 'react'
import { useRouter, useSearchParams } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'

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
}

function Form({ brandName, logoUrl, fallbackNext, branded }: Props) {
  const router = useRouter()
  const params = useSearchParams()
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
          ? 'E-mailadres of wachtwoord klopt niet.'
          : err.message,
      )
      setBusy(false)
      return
    }

    router.push(next)
    router.refresh()
  }

  return (
    <main className="flex min-h-dvh items-center justify-center bg-neutral-950 p-6 text-white">
      <form onSubmit={onSubmit} className="w-full max-w-sm space-y-5">
        <div className="flex items-center gap-3">
          {logoUrl && (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={logoUrl} alt="" className="size-10 rounded object-contain" />
          )}
          <div>
            <p className="text-sm uppercase tracking-widest text-neutral-500">{brandName}</p>
            <h1 className="text-2xl font-semibold">Aanmelden</h1>
          </div>
        </div>

        <label className="block space-y-1">
          <span className="text-sm text-neutral-400">E-mailadres</span>
          <input
            type="email"
            required
            autoComplete="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            className="w-full rounded-lg border border-neutral-700 bg-neutral-900 px-3 py-2 outline-none focus:border-neutral-400"
          />
        </label>

        <label className="block space-y-1">
          <span className="text-sm text-neutral-400">Wachtwoord</span>
          <input
            type="password"
            required
            autoComplete="current-password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            className="w-full rounded-lg border border-neutral-700 bg-neutral-900 px-3 py-2 outline-none focus:border-neutral-400"
          />
        </label>

        {error && <p className="text-sm text-red-400">{error}</p>}

        <button
          type="submit"
          disabled={busy}
          className="w-full rounded-lg px-4 py-2.5 font-medium disabled:opacity-50"
          style={
            branded
              ? { background: 'var(--club-brand)', color: 'var(--club-on-brand)' }
              : { background: '#059669', color: '#ffffff' }
          }
        >
          {busy ? 'Bezig…' : 'Aanmelden'}
        </button>
      </form>
    </main>
  )
}

export function LoginForm(props: Props) {
  return (
    <Suspense fallback={<main className="min-h-dvh bg-neutral-950" />}>
      <Form {...props} />
    </Suspense>
  )
}
