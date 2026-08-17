'use client'

import { createContext, use } from 'react'
import { translator, type Locale, type T } from '@/lib/i18n/dictionaries'

/**
 * Taal voor clientcomponenten.
 *
 * De taal wordt op de server bepaald — bij een clubomgeving door de
 * instelling van de club, op de publieke kant door de keuze van de bezoeker —
 * en hier alleen doorgegeven. Zo staat er nooit even de verkeerde taal op het
 * scherm terwijl de browser nog aan het laden is.
 */
const LocaleContext = createContext<Locale>('nl')

export function LocaleProvider({
  locale, children,
}: { locale: Locale; children: React.ReactNode }) {
  return <LocaleContext value={locale}>{children}</LocaleContext>
}

export function useLocale(): Locale {
  return use(LocaleContext)
}

export function useT(): T {
  return translator(use(LocaleContext))
}
