import type { Metadata, Viewport } from 'next'

/**
 * De schil van de spelersapp.
 *
 * Alleen hier, en niet in de hoofdlayout. Die layout draagt ook de
 * clubomgeving op `app.<club>.be`, en een manifest met "PokerLeague" erin zou
 * dáár een pictogram op het beginscherm zetten met de verkeerde naam. Een
 * geïnstalleerde app hoort te heten waar hij vandaan komt.
 *
 * `standalone` haalt de adresbalk weg zodra iemand dit toevoegt aan zijn
 * beginscherm; `start_url` is `/ik`, want wie de app opent is aangemeld en wil
 * zijn eigen scherm zien en geen landingspagina. De themakleur is exact de
 * achtergrond van de app: staat daar een andere kleur, dan zie je bovenaan een
 * streep die niet bij het scherm hoort.
 *
 * `viewportFit: 'cover'` laat de inhoud tot achter de inkeping lopen; de
 * tabbalk vangt dat op met `pb-safe`. Zonder dit staan er zwarte balken boven
 * en onder en ziet het eruit als een website in een venster.
 */

export const metadata: Metadata = {
  manifest: '/app/pokerleague.webmanifest',
  applicationName: 'PokerLeague',
  appleWebApp: {
    capable: true,
    title: 'PokerLeague',
    statusBarStyle: 'black-translucent',
  },
  icons: {
    icon: [{ url: '/app/icon-192.png', sizes: '192x192', type: 'image/png' }],
    apple: [{ url: '/app/apple-touch-icon.png', sizes: '180x180', type: 'image/png' }],
  },
}

export const viewport: Viewport = {
  themeColor: '#0a1120',
  colorScheme: 'dark',
  viewportFit: 'cover',
}

export default function Layout({ children }: LayoutProps<'/ik'>) {
  return children
}
