# Promomateriaal

De affiches die de floor kan maken bij een tornooi met een voorinschrijfbonus.

## Het lettertype

`fonts.ts` bevat Inter Regular en Inter Black, uitgedund tot de tekens die op
een affiche kunnen staan, als base64 in de code. Waarom dat zo is, staat
bovenaan dat bestand.

Opnieuw maken — bijvoorbeeld als er een taal bij komt met andere tekens:

```sh
pyftsubset Inter-Regular.otf \
  --output-file=Inter-Regular.subset.otf \
  --unicodes="U+0020-007E,U+00A0-00FF,U+0100-017F,U+2010-2015,U+2018-201D,U+2022,U+2026,U+20AC,U+00B7,U+2192" \
  --layout-features="kern,liga" --no-hinting --desubroutinize
```

Daarna het bestand base64-coderen en in `fonts.ts` zetten. Houd het totaal
onder de 500 kB: dat is de grens die `ImageResponse` aan een afbeelding stelt,
inclusief lettertypes en ingesloten beelden.

## De licentie van Inter

Inter is van de Inter Project Authors en staat onder de SIL Open Font License
1.1. Die staat toe dat het lettertype meegeleverd wordt met software, ook
commercieel, zolang het niet apart verkocht wordt en de licentie meereist.
Vandaar deze paragraaf.

De volledige tekst staat op <https://github.com/rsms/inter/blob/master/LICENSE.txt>.

## De QR-code

`qr.ts` maakt er een van als SVG, niet als PNG — de reden staat in dat bestand.
Foutcorrectie staat op Q omdat deze codes aan een raam hangen.

## De affiches zelf

`poster.tsx` beschrijft hoe ze eruitzien; `/api/promo/[club]/[id]` maakt ze.
Vier stuks per tornooi: vierkant en verhaal, elk in het Nederlands en het Frans.
