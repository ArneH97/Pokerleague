/**
 * Nagebouwde zaalklok voor op de landingspagina.
 *
 * Bewust geen screenshot: een afbeelding wordt onscherp op een groot scherm,
 * veroudert zodra de klok verandert, en kost laadtijd. Dit is dezelfde
 * opmaak, in HTML, en blijft dus vanzelf kloppen.
 */
export function ClockPreview() {
  return (
    <div className="relative">
      <div
        aria-hidden
        className="absolute -inset-4 rounded-[2rem] opacity-40 blur-2xl"
        style={{ background: 'radial-gradient(60% 60% at 50% 40%, #0d523855, transparent 70%)' }}
      />
      <div className="relative overflow-hidden rounded-3xl border border-[#1d4a37] bg-[#0b2a1e] shadow-2xl">
        {/* Voortgangsbalk van het level */}
        <div className="h-1.5 bg-white/10">
          <div className="h-full w-[62%] rounded-r-full bg-[#e0b563]" />
        </div>

        <div className="px-6 pb-6 pt-5 text-[#f2f7f4]">
          <div className="flex items-start justify-between">
            <div>
              <p className="text-[0.6rem] font-medium uppercase tracking-[0.28em] text-[#7fa393]">
                Cutoff Cardroom
              </p>
              <p className="mt-0.5 text-sm font-semibold">Vrijdagavondtornooi</p>
            </div>
            <div className="text-right">
              <p className="text-[0.6rem] font-medium uppercase tracking-[0.28em] text-[#7fa393]">
                Level
              </p>
              <p className="tnum text-xl font-bold leading-none text-[#e0b563]">
                7<span className="text-xs font-medium text-[#7fa393]"> / 20</span>
              </p>
            </div>
          </div>

          <p className="tnum mt-5 text-center text-[4.2rem] font-bold leading-none tracking-tight">
            12:47
          </p>

          <div className="mt-4 flex items-end justify-center gap-7">
            <Blind label="Small blind" value="300" />
            <Blind label="Big blind" value="600" gold />
            <Blind label="Ante" value="600" />
          </div>

          <p className="mt-4 text-center text-xs text-[#7fa393]">Hierna — 400 / 800</p>

          {/* Levelstreepjes */}
          <div className="mt-5 flex items-end justify-center gap-[3px]">
            {Array.from({ length: 20 }, (_, i) => (
              <span
                key={i}
                className="rounded-full"
                style={{
                  width: i === 6 ? 10 : 4,
                  height: i % 5 === 4 ? 4 : i === 6 ? 9 : 6,
                  background: i === 6 ? '#e0b563' : i < 6 ? '#e0b56366' : '#ffffff1f',
                }}
              />
            ))}
          </div>

          <div className="mt-5 grid grid-cols-3 gap-2 text-center">
            <Stat label="Spelers over" value="14" sub="van 27" />
            <Stat label="Gem. stack" value="38.500" />
            <Stat label="Prijzenpot" value="€ 540" />
          </div>
        </div>
      </div>
    </div>
  )
}

function Blind({ label, value, gold }: { label: string; value: string; gold?: boolean }) {
  return (
    <div className="text-center">
      <p className="text-[0.55rem] font-medium uppercase tracking-[0.22em] text-[#7fa393]">
        {label}
      </p>
      <p
        className="tnum font-bold leading-none"
        style={{ fontSize: gold ? '1.9rem' : '1.4rem', color: gold ? '#e0b563' : '#f2f7f4' }}
      >
        {value}
      </p>
    </div>
  )
}

function Stat({ label, value, sub }: { label: string; value: string; sub?: string }) {
  return (
    <div className="rounded-xl border border-white/[0.07] bg-white/[0.04] px-2 py-2">
      <p className="truncate text-[0.5rem] font-medium uppercase tracking-[0.18em] text-[#7fa393]">
        {label}
      </p>
      <p className="tnum text-base font-bold leading-tight">{value}</p>
      {sub && <p className="tnum text-[0.6rem] text-[#7fa393]">{sub}</p>}
    </div>
  )
}
