/**
 * De tekst van een clubpagina tonen.
 *
 * Een eigen, kleine opmaaktaal in plaats van een markdown-bibliotheek. Twee
 * redenen, en de tweede is de belangrijkste.
 *
 * De eerste: een clubsecretaris die een reglement overtikt heeft koppen,
 * opsommingen en genummerde punten nodig, en verder niets. Een volledige
 * markdownverwerker is dan honderden kilobytes voor drie tekens.
 *
 * De tweede: deze tekst komt uit een database en is door een mens ingetikt.
 * Hem als HTML doorlaten zou betekenen dat wie het bewerkscherm haalt ook
 * scripts op het clubdomein kan zetten. Hier wordt niets als HTML
 * geïnterpreteerd — elk stuk tekst gaat als tekst in een element, en React
 * ontsnapt dat zelf. Er is geen `dangerouslySetInnerHTML` in dit bestand en
 * dat hoort zo te blijven.
 *
 * Wat het kent:
 *
 *     ## Kop              een kop
 *     - punt              opsomming
 *     1. punt             genummerde opsomming
 *     ---                 een streep
 *     lege regel          nieuwe alinea
 *     **vet**             vet binnen een regel
 */

type Blok =
  | { soort: 'kop'; tekst: string }
  | { soort: 'alinea'; regels: string[] }
  | { soort: 'lijst'; genummerd: boolean; punten: string[] }
  | { soort: 'streep' }

function ontleed(body: string): Blok[] {
  const blokken: Blok[] = []
  const regels = body.replace(/\r\n/g, '\n').split('\n')

  let alinea: string[] = []
  let lijst: { genummerd: boolean; punten: string[] } | null = null

  const sluitAlinea = () => {
    if (alinea.length > 0) {
      // De regels blijven regels. Markdown plakt losse regels aan elkaar tot
      // één alinea, en dat is precies wat iemand die een adres of een
      // openingszin van drie regels intikt niét bedoelt.
      blokken.push({ soort: 'alinea', regels: alinea })
      alinea = []
    }
  }
  const sluitLijst = () => {
    if (lijst) {
      blokken.push({ soort: 'lijst', ...lijst })
      lijst = null
    }
  }
  const sluitAlles = () => { sluitAlinea(); sluitLijst() }

  for (const ruw of regels) {
    const regel = ruw.trim()

    if (regel === '') { sluitAlles(); continue }

    if (/^---+$/.test(regel)) {
      sluitAlles()
      blokken.push({ soort: 'streep' })
      continue
    }

    const kop = /^#{1,3}\s+(.*)$/.exec(regel)
    if (kop) {
      sluitAlles()
      blokken.push({ soort: 'kop', tekst: kop[1] })
      continue
    }

    const punt = /^[-*•]\s+(.*)$/.exec(regel)
    const nummer = /^(\d+)[.)]\s+(.*)$/.exec(regel)
    if (punt || nummer) {
      sluitAlinea()
      const genummerd = punt === null
      const tekst = punt ? punt[1] : nummer![2]
      if (lijst && lijst.genummerd !== genummerd) sluitLijst()
      if (!lijst) lijst = { genummerd, punten: [] }
      lijst.punten.push(tekst)
      continue
    }

    sluitLijst()
    alinea.push(regel)
  }
  sluitAlles()
  return blokken
}

/** `**vet**` binnen een regel. Alles blijft tekst; niets wordt HTML. */
function metVet(tekst: string, sleutel: string): React.ReactNode[] {
  return tekst.split(/(\*\*[^*]+\*\*)/g).filter(Boolean).map((deel, i) =>
    deel.startsWith('**') && deel.endsWith('**')
      ? <strong key={`${sleutel}-${i}`} className="font-semibold text-[var(--text)]">{deel.slice(2, -2)}</strong>
      : <span key={`${sleutel}-${i}`}>{deel}</span>,
  )
}

export function PageBody({ body }: { body: string }) {
  const blokken = ontleed(body)

  return (
    <div className="max-w-prose">
      {blokken.map((b, i) => {
        if (b.soort === 'streep') {
          return <hr key={i} className="my-6 border-0 border-t border-[var(--line)]" />
        }
        if (b.soort === 'kop') {
          return (
            <h2 key={i} className="mt-7 text-base font-semibold tracking-tight first:mt-0 sm:text-lg">
              {b.tekst}
            </h2>
          )
        }
        if (b.soort === 'lijst') {
          const Tag = b.genummerd ? 'ol' : 'ul'
          return (
            <Tag
              key={i}
              className={`mt-3 space-y-1.5 ps-5 text-sm leading-relaxed text-[var(--text-muted)] ${
                b.genummerd ? 'list-decimal' : 'list-disc'
              }`}
            >
              {b.punten.map((p, j) => <li key={j}>{metVet(p, `${i}-${j}`)}</li>)}
            </Tag>
          )
        }
        return (
          <p key={i} className="mt-3 text-sm leading-relaxed text-[var(--text-muted)]">
            {b.regels.map((regel, j) => (
              <span key={j}>
                {j > 0 && <br />}
                {metVet(regel, `${i}-${j}`)}
              </span>
            ))}
          </p>
        )
      })}
    </div>
  )
}
