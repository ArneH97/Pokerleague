import type { Locale } from '@/lib/i18n/dictionaries'
import { translator } from '@/lib/i18n/dictionaries'
import { formatMoney } from '@/lib/types'

/**
 * De affiche voor een avond met een voorinschrijfbonus.
 *
 * **Wat deze affiche moet doen, en wat dus de opmaak bepaalt.** Iemand scrolt
 * voorbij op een telefoon. Er is één seconde om te zeggen wat er te halen valt,
 * en die seconde gaat naar de bonus — niet naar de clubnaam, niet naar de
 * datum. Vandaar het zegel rechtsboven: dat is het eerste wat het oog pakt, en
 * het zegt meteen dat er iets te winnen valt door nú in te schrijven.
 *
 * **Goud op zwart, met een echt verloop.** Niet één vlakke kleur maar licht
 * naar donker naar licht, want dat is wat goud tot goud maakt. Satori kan dat
 * via `backgroundClip: 'text'`, en het scheelt het verschil tussen iets dat
 * eruitziet als een spreadsheet en iets dat eruitziet als een affiche. Het
 * verloop wordt gemaakt uit de clubkleur, dus een club met een blauwe huisstijl
 * krijgt blauw metaal in plaats van goud.
 *
 * **De QR staat op wit, altijd.** De rest is donker, maar een QR met omgekeerde
 * kleuren wordt door een deel van de telefoons niet gelezen. Een affiche die er
 * mooi uitziet en niet scant is geen affiche.
 *
 * Twee formaten in één component: een vierkant voor in de tijdlijn en een
 * verhaal voor de stories. Het verhaal krijgt meer lucht en een grotere QR;
 * verder is het dezelfde affiche, zodat ze naast elkaar herkenbaar blijven.
 */

export type Vorm = 'vierkant' | 'verhaal'

export const MATEN: Record<Vorm, { width: number; height: number }> = {
  vierkant: { width: 1080, height: 1080 },
  verhaal: { width: 1080, height: 1920 },
}

export interface AfficheData {
  clubNaam: string
  logoUrl: string | null
  merk: string
  tornooi: string
  wanneer: string
  plaats: string | null
  inleg: string
  stapel: number
  bonus: number
  /** Duur van een speellevel in minuten, of null als er geen structuur hangt. */
  levelMin: number | null
  /** Tot en met welk level je nog kan instappen, of null. */
  lateReg: number | null
  telefoon: string | null
  web: string | null
  /** Het korte adres dat onder de QR staat, om over te typen. */
  toonUrl: string
  qr: string
}

/** Duizendtallen met een punt, zoals aan tafel geteld wordt. */
const getal = (n: number) => n.toLocaleString('nl-BE')

/**
 * Een metaalverloop in de kleur van de club.
 *
 * Licht bovenaan, de kleur zelf, een donkere band op tweederde en dan weer
 * licht. Die donkere band is wat het metaal maakt — zonder hem leest het als
 * een gewone kleurovergang.
 */
function zachtMetaal(merk: string): string {
  return `linear-gradient(178deg, #ffffff 0%, ${merk} 34%, ${merk} 62%, #ffffff 100%)`
}

function metaal(merk: string): string {
  return `linear-gradient(179deg, #ffffff 0%, ${merk} 26%, ${merk}cc 52%, #1a1206 63%, ${merk} 76%, #ffffff 100%)`
}

export function Affiche({
  vorm, locale, d,
}: { vorm: Vorm; locale: Locale; d: AfficheData }) {
  const t = translator(locale)
  const verhaal = vorm === 'verhaal'
  const merk = d.merk
  const goud = metaal(merk)
  const zacht = zachtMetaal(merk)
  const lucht = verhaal ? 40 : 20

  // Het logo als de club er een heeft, anders de naam in metaal. Los gehouden
  // omdat het in de kopregel naast het zegel moet staan.
  const kop = d.logoUrl
    // eslint-disable-next-line @next/next/no-img-element
    ? <img src={d.logoUrl} alt="" height={verhaal ? 132 : 100} style={{ objectFit: 'contain' }} />
    : (
      <div
        style={{
          fontSize: verhaal ? 44 : 35,
          fontWeight: 900,
          letterSpacing: 8,
          lineHeight: 1.1,
          textTransform: 'uppercase',
          backgroundImage: zacht,
          backgroundClip: 'text',
          color: 'transparent',
        }}
      >
        {d.clubNaam}
      </div>
    )

  return (
    <div
      style={{
        width: '100%',
        height: '100%',
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        justifyContent: 'space-between',
        backgroundColor: '#08080a',
        backgroundImage:
          `radial-gradient(58% 34% at 50% 6%, ${merk}33 0%, transparent 72%),`
          + `radial-gradient(80% 40% at 50% 104%, ${merk}1a 0%, transparent 70%)`,
        padding: verhaal ? '74px 62px 0' : '40px 54px 0',
        fontFamily: 'Inter',
        color: '#ffffff',
      }}
    >
      {/* ------------------------------------------------------------- kopregel */}
      {/* Clubnaam links, zegel rechts. Eerst stond het zegel absoluut in de
          hoek en liep de titel eronderdoor — op een lange tornooinaam kruipt
          het goud dan onder het rood. Nu staan ze naast elkaar en kan dat
          niet meer gebeuren, hoe lang de naam ook is. */}
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', width: '100%' }}>
      <div style={{ display: 'flex', flex: 1, minWidth: 0 }}>{kop}</div>
      <div
        style={{
          display: 'flex',
          width: verhaal ? 252 : 208,
          height: verhaal ? 252 : 208,
          borderRadius: 999,
          alignItems: 'center',
          justifyContent: 'center',
          backgroundImage: 'radial-gradient(circle at 38% 28%, #c0392b 0%, #7d1c12 72%)',
          border: `5px solid ${merk}`,
          flexShrink: 0,
          transform: 'rotate(-9deg)',
          boxShadow: '0 12px 40px rgba(0,0,0,0.6)',
        }}
      >
        <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
          <div
            style={{
              fontSize: verhaal ? 21 : 18,
              fontWeight: 900,
              letterSpacing: 2,
              textTransform: 'uppercase',
              color: '#f7d9a0',
            }}
          >
            {t('promo.sealTop')}
          </div>
          <div style={{ fontSize: verhaal ? 62 : 52, fontWeight: 900, lineHeight: 1, marginTop: 2 }}>
            {`+${getal(d.bonus)}`}
          </div>
          <div
            style={{
              fontSize: verhaal ? 26 : 22,
              fontWeight: 900,
              letterSpacing: 1,
              textTransform: 'uppercase',
            }}
          >
            {t('promo.sealChips')}
          </div>
        </div>
      </div>

      </div>

      {/* ---------------------------------------------------------- de kop */}
      <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', width: '100%' }}>
        <div
          style={{
            marginTop: lucht,
            fontSize: verhaal ? 112 : 76,
            fontWeight: 900,
            lineHeight: 0.94,
            letterSpacing: -2,
            textTransform: 'uppercase',
            textAlign: 'center',
            backgroundImage: goud,
            backgroundClip: 'text',
            color: 'transparent',
            maxWidth: verhaal ? 920 : 900,
          }}
        >
          {d.tornooi}
        </div>

        {/* Datum tussen twee lijnen in de clubkleur, zoals op een affiche hoort. */}
        <div
          style={{
            display: 'flex',
            flexDirection: 'column',
            alignItems: 'center',
            marginTop: lucht,
            paddingTop: verhaal ? 20 : 12,
            paddingBottom: verhaal ? 20 : 12,
            width: '100%',
            borderTop: `2px solid ${merk}66`,
            borderBottom: `2px solid ${merk}66`,
          }}
        >
          <div
            style={{
              fontSize: verhaal ? 42 : 33,
              fontWeight: 900,
              letterSpacing: 1,
              textTransform: 'uppercase',
              textAlign: 'center',
            }}
          >
            {d.wanneer}
          </div>
        </div>
      </div>

      {/* ------------------------------------------------------------ tegels */}
      <div
        style={{
          display: 'flex',
          flexWrap: 'wrap',
          justifyContent: 'center',
          width: '100%',
          gap: verhaal ? 18 : 13,
          marginTop: lucht,
        }}
      >
        <Tegel label={t('rsvp.buyin')} waarde={d.inleg} merk={merk} verhaal={verhaal} />
        <Tegel
          label={t('promo.stack')}
          waarde={getal(d.stapel + d.bonus)}
          onder={`${getal(d.stapel)} + ${getal(d.bonus)}`}
          merk={merk}
          verhaal={verhaal}
          goud
        />
        {d.levelMin !== null && (
          <Tegel
            label={t('promo.levels')}
            waarde={`${d.levelMin} ${t('floor.min')}`}
            merk={merk}
            verhaal={verhaal}
          />
        )}
        {d.lateReg !== null && (
          <Tegel
            label={t('promo.lateReg')}
            waarde={`${t('promo.tillLevel')} ${d.lateReg}`}
            merk={merk}
            verhaal={verhaal}
          />
        )}
      </div>

      {/* ------------------------------------------------------------- de QR */}
      <div
        style={{
          display: 'flex',
          alignItems: 'center',
          gap: verhaal ? 32 : 24,
          marginTop: lucht,
          marginBottom: lucht,
        }}
      >
        <div
          style={{
            display: 'flex',
            padding: verhaal ? 15 : 12,
            borderRadius: 22,
            backgroundColor: '#ffffff',
          }}
        >
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={d.qr} alt="" width={verhaal ? 296 : 196} height={verhaal ? 296 : 196} />
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', maxWidth: verhaal ? 560 : 490 }}>
          <div
            style={{
              fontSize: verhaal ? 40 : 31,
              fontWeight: 900,
              lineHeight: 1.05,
              textTransform: 'uppercase',
              color: merk,
            }}
          >
            {t('promo.scan')}
          </div>
          <div style={{ marginTop: 9, fontSize: verhaal ? 27 : 22, color: '#c9d1de' }}>
            {d.toonUrl.replace(/^https:\/\//, '')}
          </div>
          <div
            style={{
              marginTop: 9,
              fontSize: verhaal ? 24 : 19,
              lineHeight: 1.3,
              color: '#8b94a3',
            }}
          >
            {t('promo.bonusWhy')}
          </div>
        </div>
      </div>

      {/* ---------------------------------------------------------- voetbalk */}
      {/* Loopt tot tegen de rand, dus de negatieve marge compenseert de
          binnenmarge van de affiche. */}
      <div
        style={{
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          gap: verhaal ? 36 : 26,
          width: verhaal ? 1080 : 1080,
          marginLeft: verhaal ? -62 : -54,
          paddingTop: verhaal ? 24 : 16,
          paddingBottom: verhaal ? 24 : 16,
          borderTop: `2px solid ${merk}55`,
          backgroundColor: 'rgba(255,255,255,0.03)',
          fontSize: verhaal ? 24 : 19,
          color: '#a9b2c0',
        }}
      >
        {d.plaats && <div style={{ display: 'flex' }}>{d.plaats}</div>}
        {d.telefoon && <div style={{ display: 'flex' }}>{d.telefoon}</div>}
        {d.web && <div style={{ display: 'flex' }}>{d.web}</div>}
      </div>
    </div>
  )
}

function Tegel({
  label, waarde, onder, merk, verhaal, goud,
}: {
  label: string
  waarde: string
  onder?: string
  merk: string
  verhaal: boolean
  goud?: boolean
}) {
  return (
    <div
      style={{
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        justifyContent: 'center',
        // Twee per rij, met de tussenruimte al verrekend.
        width: verhaal ? 469 : 479,
        paddingTop: verhaal ? 18 : 11,
        paddingBottom: verhaal ? 18 : 11,
        borderRadius: 18,
        border: `2px solid ${goud ? merk : `${merk}44`}`,
        backgroundColor: goud ? `${merk}14` : 'rgba(255,255,255,0.035)',
      }}
    >
      <div
        style={{
          fontSize: verhaal ? 22 : 18,
          letterSpacing: 3,
          textTransform: 'uppercase',
          color: '#8b94a3',
        }}
      >
        {label}
      </div>
      <div
        style={{
          marginTop: 3,
          fontSize: verhaal ? 50 : 40,
          fontWeight: 900,
          color: goud ? merk : '#ffffff',
        }}
      >
        {waarde}
      </div>
      {onder && (
        <div style={{ marginTop: 1, fontSize: verhaal ? 21 : 17, color: '#8b94a3' }}>
          {onder}
        </div>
      )}
    </div>
  )
}

/** De gegevens van een tornooi omzetten naar wat de affiche toont. */
export function afficheData(
  locale: Locale,
  r: {
    clubNaam: string
    logoUrl: string | null
    merk: string
    tornooi: string
    scheduledAt: string
    timezone: string
    stad: string | null
    adres: string | null
    buyinCents: number
    feeCents: number
    currency: string
    stapel: number
    bonus: number
    levelMin: number | null
    lateReg: number | null
    telefoon: string | null
    web: string | null
    toonUrl: string
    qr: string
  },
): AfficheData {
  const wanneer = new Intl.DateTimeFormat(`${locale}-BE`, {
    weekday: 'long', day: 'numeric', month: 'long',
    hour: '2-digit', minute: '2-digit',
    timeZone: r.timezone || 'Europe/Brussels',
  }).format(new Date(r.scheduledAt))

  return {
    clubNaam: r.clubNaam,
    logoUrl: r.logoUrl,
    merk: r.merk,
    tornooi: r.tornooi,
    wanneer,
    plaats: [r.adres, r.stad].filter(Boolean).join(' · ') || null,
    inleg: formatMoney(r.buyinCents + r.feeCents, r.currency),
    stapel: r.stapel,
    bonus: r.bonus,
    levelMin: r.levelMin,
    lateReg: r.lateReg,
    telefoon: r.telefoon,
    web: r.web,
    toonUrl: r.toonUrl,
    qr: r.qr,
  }
}
