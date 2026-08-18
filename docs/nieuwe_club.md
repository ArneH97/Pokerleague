# Een club aansluiten

Van "ja, we doen mee" tot een club die vanavond kan draaien. Reken op een half
uur, waarvan het meeste wachten op DNS is.

## Wat je van de club nodig hebt

Vraag dit vooraf op — met deze acht dingen kan je de omgeving in één keer
juist zetten in plaats van er drie keer op terug te komen.

| | |
|---|---|
| Naam en gemeente | zoals het op een affiche staat |
| Logo | liefst PNG of SVG; en apart het beeldmerk zonder tekst, vrijstaand — dat komt als watermerk achter de klok |
| Huisstijlkleur | een hex-waarde; anders pik ik ze uit het logo |
| Speelritme | "elke woensdag om 20u" — dit staat letterlijk op hun pagina |
| Adres | straat, nummer, postcode, gemeente |
| Contact | mailadres en telefoon die publiek mogen |
| Blindstructuur | niveaus, duur, vanaf wanneer ante, waar de pauzes vallen |
| Uitbetaling en punten | wie er betaald wordt per veldgrootte, en hoe ze punten tellen |

Weet je de laatste twee nog niet, begin dan met de standaard uit het script —
20 niveaus van 20 minuten, drie pauzes, 50/30/20 en `sqrt_ratio`. Dat is wat de
meeste clubs doen en het is achteraf in het scherm aan te passen.

Eén ding moet de club zelf doen: **de beheerder maakt een account op
pokerleague.be/registreren**. Eén account volstaat — dezelfde persoon is speler
op het platform en staf bij de club.

## De omgeving zetten

1. `supabase/nieuwe_club.sql` openen, het blok **INSTELLEN** invullen, en het
   geheel draaien in de SQL-editor van Supabase. Dat maakt de club, de
   blindstructuur met pauzes, het uitbetalingsschema, een seizoen met de
   puntenformule, en het koppelt de beheerder als `owner`.
2. Logo en beeldmerk uploaden en de twee velden vullen:
   ```sql
   update clubs
   set logo_url = '…', mark_url = '…'
   where slug = 'aalst';
   ```
3. Klaar. De club staat meteen op `pokerleague.be/c/<slug>`.

## Het adres

`pokerleague.be/c/aalst` werkt zonder dat er iemand iets moet klikken. Wil de
club een eigen adres, dan is dat twee handelingen van elk een minuut — zie
[domeinen.md](domeinen.md):

* `aalst.pokerleague.be` → Vercel: domein toevoegen, EasyHost: één CNAME.
* `app.aalstpokerclub.be` → hetzelfde, plus `clubs.custom_domain` invullen.

Er is bewust geen jokerteken in DNS; domeinen.md legt uit waarom.

## Voor een demo

Een lege club demonstreert slecht: geen klassement, geen grafiek, een agenda
met niets erin. `supabase/demo_data.sql` vult vijf maanden geschiedenis — pas
bovenaan `c_slug` aan en draai het. Onderaan datzelfde bestand staat het
opruimscript, zodat de club schoon van start gaat op de dag dat ze echt
beginnen.

Draai je het bij twee clubs met hetzelfde script, dan spelen dezelfde
demospelers bij allebei. Dat is geen fout maar de beste demonstratie die er is:
open dan een spelersprofiel en toon hoe twee clubs in één overzicht samenkomen —
precies het ding dat geen enkele club zelf kan tonen.

## De eerste avond

Niets van bovenstaande hoeft opnieuw. De floor maakt een tornooi aan
(structuur en uitbetaling staan al klaar), zet de klok op een scherm in de
zaal, en tikt de spelers in aan de deur. Bij het afsluiten schrijft de app de
uitslag, het klassement en het ledenbestand vanzelf bij.
