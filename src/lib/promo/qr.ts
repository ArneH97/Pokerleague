import QRCode from 'qrcode'

/**
 * Een QR-code als SVG-data-URI.
 *
 * **Waarom zelf tekenen en niet de PNG van de bibliotheek?** Omdat dit in een
 * `ImageResponse` terechtkomt, en satori daar een afbeelding van maakt op de
 * grootte die de affiche vraagt. Een PNG van 300 pixels die naar 420 wordt
 * uitgerekt geeft wollige randen, en een wollige QR is een QR die de helft van
 * de telefoons niet pakt. Een SVG heeft geen grootte: die tekent scherp op elk
 * formaat.
 *
 * **De stille rand van vier modules eromheen is geen marge maar deel van de
 * code.** Scanners zoeken het patroon in een leeg vlak; plak je de code tegen
 * iets aan, dan vinden ze hem niet. Vandaar dat de rand hier in de SVG zit en
 * niet in de opmaak van de affiche — dan kan hij niet per ongeluk wegvallen.
 *
 * Foutcorrectie staat op Q (25%). Hoger dan de standaard M, want deze codes
 * hangen aan een raam of liggen op een toog: een vinger, een lichtvlek of een
 * vouw mag hem niet onleesbaar maken.
 */
export async function qrDataUri(
  tekst: string,
  opties: { donker?: string; licht?: string } = {},
): Promise<string> {
  const donker = opties.donker ?? '#000000'
  const licht = opties.licht ?? '#ffffff'

  const qr = QRCode.create(tekst, { errorCorrectionLevel: 'Q' })
  const n = qr.modules.size
  const data = qr.modules.data
  const rand = 4
  const zij = n + rand * 2

  // Aaneengesloten modules op één rij worden één rechthoek. Dat scheelt een
  // factor tien in de lengte van het pad, en een korter pad is een kleinere
  // data-URI — die telt mee in de bundel van de afbeelding.
  const stukken: string[] = []
  for (let y = 0; y < n; y++) {
    let x = 0
    while (x < n) {
      if (!data[y * n + x]) { x++; continue }
      let breed = 1
      while (x + breed < n && data[y * n + x + breed]) breed++
      stukken.push(`M${x + rand} ${y + rand}h${breed}v1h-${breed}z`)
      x += breed
    }
  }

  const svg =
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${zij} ${zij}" shape-rendering="crispEdges">`
    + `<rect width="${zij}" height="${zij}" fill="${licht}"/>`
    + `<path d="${stukken.join('')}" fill="${donker}"/>`
    + `</svg>`

  return `data:image/svg+xml;base64,${Buffer.from(svg).toString('base64')}`
}
