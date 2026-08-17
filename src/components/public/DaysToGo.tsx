'use client'

import { useEffect, useState } from 'react'
import { useT } from '@/lib/i18n/context'

/**
 * Het aftellen naar de openingsdag.
 *
 * Bewust in de browser en niet op de server. Een server rendert één keer en
 * dat antwoord kan uren blijven staan in een cache; dan zegt de pagina morgen
 * nog altijd "nog twintig dagen". Hier telt hij tegen de klok van de bezoeker
 * zelf, en dat is precies de klok waarmee hij rekent.
 *
 * Vóór hydratatie staat er niets. Dat is met opzet: een getal dat verspringt
 * zodra de pagina inlaadt leest slordiger dan een getal dat een tel later
 * verschijnt.
 */
export function DaysToGo({ date }: { date: string }) {
  const t = useT()
  const [days, setDays] = useState<number | null>(null)

  useEffect(() => {
    const target = new Date(`${date}T00:00:00`)
    const bereken = () => {
      const vandaag = new Date()
      vandaag.setHours(0, 0, 0, 0)
      setDays(Math.round((target.getTime() - vandaag.getTime()) / 86_400_000))
    }
    bereken()
    // Blijft het scherm de hele nacht aan staan, dan klopt het 's ochtends nog.
    const id = setInterval(bereken, 60 * 60_000)
    return () => clearInterval(id)
  }, [date])

  if (days === null || days <= 0) return null

  return (
    <p className="mt-1 text-lg text-[var(--text-muted)]">
      {days === 1 ? t('pub.oneDayToGo') : `${t('pub.stillTo')} ${days} ${t('pub.days')}`}
    </p>
  )
}
