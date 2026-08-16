'use client'

import { useState } from 'react'
import { useRouter, useSearchParams } from 'next/navigation'
import { Suspense } from 'react'
import { createClient } from '@/lib/supabase/client'

/**
 * Aanmelden met e-mail en wachtwoord.
 *
 * Bewust geen magic link: die vereist dat je op de zaalwifi je mailbox kan
 * openen, en dat is precies het moment waarop het misgaat. Een wachtwoord
 * werkt ook als de wifi hapert.
 */
function LoginForm() {
  const router = useRouter()
  const params = useSearchParams()
  const next = params.get('next') ?? '/'

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
        <div>
          <p className="text-sm uppercase tracking-widest text-neutral-500">Pokerleague</p>
          <h1 className="text-2xl font-semibold">Aanmelden</h1>
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
          className="w-full rounded-lg bg-emerald-600 px-4 py-2.5 font-medium hover:bg-emerald-500 disabled:opacity-50"
        >
          {busy ? 'Bezig…' : 'Aanmelden'}
        </button>
      </form>
    </main>
  )
}

export default function Page() {
  return (
    <Suspense fallback={<main className="min-h-dvh bg-neutral-950" />}>
      <LoginForm />
    </Suspense>
  )
}
