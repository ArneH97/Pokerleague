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

export const viewport = {
  themeColor: "#0a0a0a",
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
