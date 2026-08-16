'use client'

import { useCallback, useEffect, useRef, useState } from 'react'

/**
 * Meet hoeveel de klok van dit apparaat afwijkt van de server en geeft
 * functies terug die de gecorrigeerde tijd opleveren.
 *
 * Werkt als een vereenvoudigde NTP-uitwisseling: we meten de rondreistijd en
 * gaan ervan uit dat het antwoord halverwege is opgesteld. Van meerdere
 * metingen houden we die met de kortste rondreis, want die is het minst
 * vervuild door netwerkvertraging.
 *
 * Waarom dit nodig is: de zaalweergave en het floor-scherm zijn twee
 * verschillende apparaten. Zonder correctie tellen ze een paar seconden uit
 * elkaar af, en dat ziet iedereen in de zaal.
 *
 * De afwijking staat in state en niet in een ref, zodat componenten hem
 * tijdens het renderen mogen lezen. Hij verandert hooguit een paar keer per
 * uur, dus dat kost geen extra renders van betekenis.
 */
export function useServerTime(resyncMs = 5 * 60_000) {
  const [offsetMs, setOffsetMs] = useState(0)
  const bestRoundTripRef = useRef(Number.POSITIVE_INFINITY)

  useEffect(() => {
    let cancelled = false

    async function sync() {
      try {
        const sent = Date.now()
        const res = await fetch('/api/time', { cache: 'no-store' })
        const received = Date.now()
        if (!res.ok || cancelled) return

        const { now } = (await res.json()) as { now: number }
        const roundTrip = received - sent
        if (roundTrip >= bestRoundTripRef.current) return

        bestRoundTripRef.current = roundTrip
        setOffsetMs(now + roundTrip / 2 - received)
      } catch {
        // Geen verbinding: we blijven op de laatst bekende afwijking staan.
        // Beter een klok die doortikt dan een klok die stilvalt.
      }
    }

    void sync()
    // Twee extra metingen kort na elkaar; de snelste wint.
    const quick = [setTimeout(sync, 400), setTimeout(sync, 1200)]
    const interval = setInterval(() => {
      bestRoundTripRef.current = Number.POSITIVE_INFINITY
      void sync()
    }, resyncMs)

    return () => {
      cancelled = true
      quick.forEach(clearTimeout)
      clearInterval(interval)
    }
  }, [resyncMs])

  const nowMs = useCallback(() => Date.now() + offsetMs, [offsetMs])
  const nowIso = useCallback(
    () => new Date(Date.now() + offsetMs).toISOString(),
    [offsetMs],
  )

  return { nowMs, nowIso, offsetMs }
}

/**
 * Laat een component periodiek opnieuw tekenen. Bewust losgekoppeld van de
 * klokstand: de waarheid staat in de database, dit zorgt er alleen voor dat
 * het scherm de berekening opnieuw uitvoert.
 */
export function useTicker(intervalMs = 250) {
  const [, setTick] = useState(0)

  useEffect(() => {
    const id = setInterval(() => setTick((n) => n + 1), intervalMs)
    return () => clearInterval(id)
  }, [intervalMs])
}
