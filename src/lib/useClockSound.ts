'use client'

import { useCallback, useEffect, useRef, useState } from 'react'
import { formatBlinds, type BlindLevel } from '@/lib/tournament/clock'

/**
 * Geluid voor de zaalklok.
 *
 * Belangrijk: browsers weigeren audio af te spelen tot de gebruiker iets op
 * de pagina heeft aangeklikt. Zet je het zaalscherm 's ochtends open en raak
 * je het daarna niet meer aan, dan piept er die avond niets. Vandaar de
 * expliciete aanzetknop met een testpiep — dan hoor je meteen dat het werkt
 * in plaats van het pas om acht uur te ontdekken.
 *
 * De tonen worden gegenereerd met de Web Audio API. Geen geluidsbestanden,
 * dus niets dat kan ontbreken of traag laden op zaalwifi.
 */

type Ctor = typeof AudioContext

function getAudioContextCtor(): Ctor | null {
  if (typeof window === 'undefined') return null
  const w = window as unknown as { AudioContext?: Ctor; webkitAudioContext?: Ctor }
  return w.AudioContext ?? w.webkitAudioContext ?? null
}

export function useClockSound() {
  const ctxRef = useRef<AudioContext | null>(null)
  const [enabled, setEnabled] = useState(false)
  // Niet vooraf detecteren: dat zou tijdens het renderen naar `window` moeten
  // kijken en dat loopt mis bij hydratie. We gaan uit van ondersteuning en
  // merken het pas als het aanzetten faalt — dat gebeurt in een klik, waar
  // state zetten gewoon mag.
  const [supported, setSupported] = useState(true)

  /** Eén toon met een korte in- en uitloop, zodat er geen klik hoorbaar is. */
  const tone = useCallback(
    (freq: number, durationMs: number, startOffsetMs = 0, volume = 0.35) => {
      const ctx = ctxRef.current
      if (!ctx) return

      const start = ctx.currentTime + startOffsetMs / 1000
      const end = start + durationMs / 1000

      const osc = ctx.createOscillator()
      const gain = ctx.createGain()

      osc.type = 'sine'
      osc.frequency.setValueAtTime(freq, start)

      gain.gain.setValueAtTime(0.0001, start)
      gain.gain.exponentialRampToValueAtTime(volume, start + 0.015)
      gain.gain.setValueAtTime(volume, end - 0.05)
      gain.gain.exponentialRampToValueAtTime(0.0001, end)

      osc.connect(gain).connect(ctx.destination)
      osc.start(start)
      osc.stop(end + 0.02)
    },
    [],
  )

  const enable = useCallback(async () => {
    const Ctor = getAudioContextCtor()
    if (!Ctor) {
      setSupported(false)
      return
    }
    ctxRef.current ??= new Ctor()
    // Safari start opgeschort; hervatten mag alleen vanuit een klik.
    if (ctxRef.current.state === 'suspended') await ctxRef.current.resume()

    setEnabled(true)
    tone(880, 160)  // testpiep, zodat je het volume meteen kan zetten
  }, [tone])

  const disable = useCallback(() => {
    setEnabled(false)
  }, [])

  /** Nog één minuut: twee korte piepjes. */
  const playOneMinute = useCallback(() => {
    if (!enabled) return
    tone(880, 140)
    tone(880, 140, 220)
  }, [enabled, tone])

  /** Nieuw level: oplopend drieklankje, duidelijk anders dan de waarschuwing. */
  const playLevelUp = useCallback(() => {
    if (!enabled) return
    tone(660, 180, 0, 0.4)
    tone(880, 180, 200, 0.4)
    tone(1320, 340, 400, 0.4)
  }, [enabled, tone])

  /** Pauze afgelopen of tornooi begint: langere lage toon. */
  const playAttention = useCallback(() => {
    if (!enabled) return
    tone(440, 500, 0, 0.4)
  }, [enabled, tone])

  /**
   * Spreekt de nieuwe blinds uit, als het apparaat een Nederlandse stem
   * heeft. Puur bonus: in een luide zaal is dit het verschil tussen wel en
   * niet gehoord worden. Ontbreekt de stem, dan blijft het bij de toon.
   */
  const announce = useCallback(
    (level: BlindLevel | null) => {
      if (!enabled || !level || typeof window === 'undefined') return
      if (!('speechSynthesis' in window)) return

      const text = level.isBreak
        ? `Pauze. ${Math.round(level.durationS / 60)} minuten.`
        : `Nieuwe blinds. ${formatBlinds(level).replace('/', 'op')}`

      const utter = new SpeechSynthesisUtterance(text)
      utter.lang = 'nl-BE'
      utter.rate = 0.95

      const voice = window.speechSynthesis
        .getVoices()
        .find((v) => v.lang.startsWith('nl'))
      if (voice) utter.voice = voice

      // Na het geluidje, niet eroverheen.
      window.setTimeout(() => window.speechSynthesis.speak(utter), 900)
    },
    [enabled],
  )

  useEffect(() => {
    return () => {
      void ctxRef.current?.close()
      ctxRef.current = null
    }
  }, [])

  return {
    enabled, supported, enable, disable,
    playOneMinute, playLevelUp, playAttention, announce,
  }
}
