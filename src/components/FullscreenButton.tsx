'use client'

import { useEffect, useState } from 'react'
import { useT } from '@/lib/i18n/context'

/**
 * Volledig scherm voor de zaalweergave.
 *
 * Twee dingen die op een tornooiavond echt gebeuren en die dit oplost: de
 * adresbalk en de tabbladen van de browser hangen de hele avond mee op de
 * beamer, en de laptop valt na twintig minuten in slaap terwijl er nog
 * gespeeld wordt.
 *
 * De knop moet door de gebruiker aangeklikt worden — een browser gaat nooit
 * uit zichzelf naar volledig scherm, dat is een beveiliging en geen
 * beperking die we kunnen omzeilen. Escape brengt je terug; dat regelt de
 * browser zelf, wij hoeven er niets voor te doen.
 *
 * Safari op de Mac gebruikt nog altijd de webkit-namen, en dat is precies de
 * combinatie waarop deze klok zal draaien.
 */

interface WebkitDoc extends Document {
  webkitFullscreenElement?: Element | null
  webkitExitFullscreen?: () => Promise<void>
}
interface WebkitEl extends HTMLElement {
  webkitRequestFullscreen?: () => Promise<void>
}

function isFullscreen(): boolean {
  const d = document as WebkitDoc
  return Boolean(d.fullscreenElement ?? d.webkitFullscreenElement)
}

export function FullscreenButton() {
  const t = useT()
  const [on, setOn] = useState(false)
  const [hidden, setHidden] = useState(false)

  useEffect(() => {
    const sync = () => setOn(isFullscreen())
    document.addEventListener('fullscreenchange', sync)
    document.addEventListener('webkitfullscreenchange', sync)
    return () => {
      document.removeEventListener('fullscreenchange', sync)
      document.removeEventListener('webkitfullscreenchange', sync)
    }
  }, [])

  // In volledig scherm verdwijnt de knop zodra de muis stilligt. Anders hangt
  // er de hele avond een knop op de beamer.
  useEffect(() => {
    if (!on) return
    let timer: ReturnType<typeof setTimeout>
    const wake = () => {
      setHidden(false)
      clearTimeout(timer)
      timer = setTimeout(() => setHidden(true), 2500)
    }
    wake()
    window.addEventListener('mousemove', wake)
    window.addEventListener('touchstart', wake)
    return () => {
      clearTimeout(timer)
      window.removeEventListener('mousemove', wake)
      window.removeEventListener('touchstart', wake)
      setHidden(false)
    }
  }, [on])

  // Scherm wakker houden zolang de klok voluit staat. Niet elke browser kent
  // dit; waar het ontbreekt gebeurt er gewoon niets.
  useEffect(() => {
    if (!on || !('wakeLock' in navigator)) return

    let lock: WakeLockSentinel | null = null
    let cancelled = false

    const acquire = async () => {
      try {
        const next = await navigator.wakeLock.request('screen')
        if (cancelled) { void next.release(); return }
        lock = next
      } catch {
        // Geweigerd of niet ondersteund: dan valt het scherm gewoon in slaap
        // zoals vroeger. Geen reden om de klok te storen met een melding.
      }
    }

    // Na het wisselen van tabblad geeft de browser de vergrendeling vrij.
    const onVisible = () => { if (document.visibilityState === 'visible') void acquire() }

    void acquire()
    document.addEventListener('visibilitychange', onVisible)

    return () => {
      cancelled = true
      document.removeEventListener('visibilitychange', onVisible)
      void lock?.release()
    }
  }, [on])

  async function toggle() {
    const d = document as WebkitDoc
    try {
      if (isFullscreen()) {
        await (d.exitFullscreen?.() ?? d.webkitExitFullscreen?.())
      } else {
        const el = document.documentElement as WebkitEl
        await (el.requestFullscreen?.() ?? el.webkitRequestFullscreen?.())
      }
    } catch {
      // Sommige browsers weigeren dit in een ingebedde weergave. Niets aan
      // te doen, en zeker geen reden om de zaal een foutmelding te tonen.
    }
  }

  // Rechtsonder. Boven staan links de tornooinaam en rechts het level, en
  // die mogen geen van beide half achter een knop verdwijnen.
  return (
    <button
      type="button"
      onClick={() => void toggle()}
      title={on ? t('clock.exitFullscreenHint') : t('clock.fullscreen')}
      aria-label={on ? t('clock.exitFullscreenHint') : t('clock.fullscreen')}
      className={`absolute bottom-[1.2vh] right-[1vw] z-30 rounded-full border border-white/10 bg-black/30 p-[1.1vh] text-[var(--text-faint)] backdrop-blur transition hover:border-white/25 hover:text-[var(--text)] ${
        on && hidden ? 'pointer-events-none opacity-0' : 'opacity-70'
      }`}
    >
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"
           strokeLinecap="round" strokeLinejoin="round" className="size-[2.4vh]">
        {on ? (
          <>
            <path d="M9 3v6H3" /><path d="M15 3v6h6" />
            <path d="M9 21v-6H3" /><path d="M15 21v-6h6" />
          </>
        ) : (
          <>
            <path d="M3 9V3h6" /><path d="M21 9V3h-6" />
            <path d="M3 15v6h6" /><path d="M21 15v6h-6" />
          </>
        )}
      </svg>
    </button>
  )
}
