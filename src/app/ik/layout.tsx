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
 * Het tot achter de inkeping lopen (`viewportFit: 'cover'`) staat bewust in de
 * hoofdlayout en niet hier: stond het alleen op deze schermen, dan verspringt
 * de hele pagina zodra je in de app naar een tabblad buiten `/ik` tikt.
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

// `viewportFit` staat in de hoofdlayout, zodat elk scherm van de app dezelfde
// randen heeft en er niets verspringt als je van tabblad wisselt.
export const viewport: Viewport = {
  themeColor: '#0a1120',
  colorScheme: 'dark',
}

export default function Layout({ children }: LayoutProps<'/ik'>) {
  return children
}
