import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

// Bewust neutraal en algemeen: elke clubomgeving overschrijft dit met zijn
// eigen naam via generateMetadata, en de spelerskant zet er PokerLeague neer.
// Hier hoort geen merknaam, anders staat er "Pokerleague" in het tabblad van
// een club die daar niets mee te maken heeft.
export const metadata: Metadata = {
  title: { default: "Tornooibeheer", template: "%s" },
  description: "Tornooibeheer en klok voor pokerclubs",
};

// `viewportFit: 'cover'` staat hier en niet alleen op de spelersapp.
//
// Het stond eerst alleen op `/ik`, en dat gaf precies wat het moest oplossen:
// wie in de geïnstalleerde app van zijn overzicht naar de clubgids tikte,
// wisselde van een pagina die tot achter de statusbalk loopt naar een die dat
// niet doet. Het hele scherm verspringt dan een centimeter. Dat is het
// haperen tussen de tabbladen.
//
// Alles wat de inkeping raakt houdt zijn eigen ruimte vrij met `pt-safe` /
// `pb-safe`; in een gewoon browservenster is die inset nul en verandert er
// niets.
export const viewport = {
  themeColor: "#0a0a0a",
  viewportFit: "cover" as const,
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html
      lang="nl"
      className={`${geistSans.variable} ${geistMono.variable} h-full antialiased`}
    >
      <body className="min-h-full flex flex-col">{children}</body>
    </html>
  );
}
