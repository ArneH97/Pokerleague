# Wat er staat, en hoe je het test

Stand van 17 augustus 2026. Alles hieronder werkt op de clubkant (Cutoff).
De spelerskant van PokerLeague is nog niet gebouwd.

---

## 1. Eerst dit draaien

**Draai `setup.sql` niet opnieuw** op een database waar al iets in staat — die
begint met `create type` en dat kan geen tweede keer. Draai in plaats daarvan
de losse migraties die je nog niet had, in volgorde:

```
0008_floor.sql              spelers toevoegen, rebuy, uitschakelen, afsluiten
0009_club_mark.sql          het beeldmerk apart van het logo
0010_floor_email.sql        mailadres als sleutel bij een nieuwe speler
0011_rls_recursion.sql      lost "infinite recursion in policy" op
0012_floor_undo_buyin.sql   een verkeerde inkoop terugdraaien
0013_entry_fees.sql         per soort inkoop: pot en clubbijdrage apart
0014_standings_period.sql   klassement per jaar of maand
0015_club_overview.sql      ledenbestand en cijfers
0016_deal.sql               de deal aan de finaletafel
0017_payouts.sql            prijzenverdeling door de floor + bubbel
0018_deal_even.sql          even split, en de ladder mag iedereen zien
0019_round_euros.sql        alles in hele euro's
0020_stop_clock_on_finish.sql  de klok stopt zodra het tornooi dicht is
0021_payout_list.sql        de uitbetaallijst voor aan de kassa
0022_whole_points.sql       punten zonder cijfers na de komma
0023_public_club.sql        de publieke clubpagina's voor spelers
0024_club_profile.sql       adres, speeldagen, contact en openingsdag
0025_short_names.sql        publieke namen als "Arne H."
```

Alle achttien zijn meerdere keren te draaien zonder schade — ik heb ze twee keer
na elkaar over een gevulde database gehaald. Weet je niet meer waar je stond,
draai ze dan gewoon allemaal.

Daarna, om te testen:

```
demo_cutoff.sql       28 verzonnen spelers, 14 afgesloten avonden over 7 maanden
demo_testavond.sql    één avond die nu middenin de finaletafel staat
```

En `demo_cutoff_wissen.sql` haalt beide er weer uit. Doe dat vóór 6 september.

Los daarvan staan een paar losse scripts. `cutoff_leegmaken.sql` haalt alle
tornooien, uitslagen en leden weg maar laat je staf, structuren, sjablonen en
seizoenen staan — dat is wat je vóór de opening draait.

En `publieke_namen_aan.sql`. Draai je die, dan tonen de
publieke pagina's van Cutoff de namen van je spelers in plaats van
gebruikersnamen. Zie de uitleg onder *De publieke kant*.

---

## 2. Hoe een avond loopt

### Tornooi aanmaken

`/c/cutoff` → **Nieuw tornooi**.

Het geldoverzicht is één tabel met per soort inkoop twee bedragen: wat naar de
**pot** gaat en wat de **club** houdt. Buy-in, rebuy en add-on staan er los in,
want clubs doen dat niet allemaal hetzelfde. Rechts staat wat de speler in
totaal afrekent — dat is het cijfer aan de kassa.

Verder: startstack, hoeveel **rebuys** per speler zijn toegestaan (standaard 1),
tot welk level er nog ingekocht mag worden, de blindstructuur, de
prijzenverdeling en het seizoen.

### De klok

`/c/cutoff/klok/<id>` — dit is het scherm voor de beamer. Rechtsonder een knopje
voor volledig scherm; Escape brengt je terug. Zolang je voluit staat blijft het
scherm wakker, dus de laptop valt niet in slaap tijdens het spelen.

Links staan spelers, rebuys en add-ons; rechts prijzenpot, gemiddelde stack met
het aantal big blinds erbij, en gespeelde tijd. De C van Cutoff staat als
watermerk achter de tijd. Zodra de inkopen dicht zijn loopt de prijzenladder
onderaan als een balk door — permanent, niet als popup.

De **gemiddelde stack** rekent met wat er in spel hoort te zijn: elke inkoop en
rebuy legt een startstack op tafel, een add-on zijn eigen aantal. Niet met de
opgetelde chipcounts, want die vult bijna niemand in — dan zou het gemiddelde de
hele avond op de startstack blijven staan in plaats van te stijgen bij elke
afvaller.

Geluid moet je één keer aanzetten met de knop — browsers weigeren audio tot je
iets aangeklikt hebt. Daarna: een piep bij de laatste minuut, een drieklank bij
een nieuw level, en de blinds worden uitgesproken. **Vijf minuten voor het einde
van het laatste inkooplevel** klinkt er een waarschuwing dat de rebuys sluiten,
in de taal van de club — voor Cutoff dus Engels.

### De floor

`/c/cutoff/floor/<id>` — hier bedien je alles.

- **Klok**: starten, pauzeren, level vooruit of terug, ±1 minuut.
- **Speler toevoegen**: zoekveld op naam of mailadres. Onbekend? Dan volgt één
  schermpje met naam en mailadres. Bestaat dat adres al ergens op het platform,
  ook bij een andere club, dan wordt hij aan dat profiel gekoppeld. Geen adres
  kan ook, maar dan moet je zeggen waarom.
- **Per speler**: chipcount aanpassen, `Rebuy…` (met het bedrag erop, plus
  add-on en terugdraaien), en Uitschakelen. De geldknoppen zitten met opzet
  achter één knop, weg van Uitschakelen.
- **Prijzengeld**: het aantal betaalde plaatsen met plus en min, en een vinkje
  voor de bubbel. Werkt pas zinvol nadat de inkopen dicht zijn.
- **Deal**: vanaf twee spelers.

### Uitbetalen

Valt er iemand af die in het geld eindigt, dan springt zijn bedrag meteen in
beeld: naam, plaats, bedrag. Je streept hem daar af of je klikt het weg.

Daaronder staat de **uitbetaallijst** — één regel per naam met plaats en
bedrag, en per regel een knop om af te strepen. Bovenaan zie je wat er nog
open staat. Dat afstrepen staat in de database, dus het overleeft een refresh
en je kan het op een tweede toestel aan de kassa openen.

Na een deal staan hier de **afgesproken** bedragen en niet de ladder — dat is
dezelfde bron als de uitslagpagina, dus die twee kunnen niet uit elkaar lopen.
Wie al eerder in het geld afviel houdt gewoon zijn ladderbedrag.

### De deal

Twee stappen.

**Tellen.** De stapels in het systeem zijn een schatting — niet iedereen geeft
zijn chipcount door. Bij een deal gaat het over geld, dus tel je opnieuw.
Onderaan zie je het getelde totaal naast wat er in spel hoort te zijn. Tussen
**95% en 105%** is in orde; chip-ups geven altijd wat drift.

**Voorstellen.** ICM, chipchop en even split naast elkaar. Klik op een kolomkop
om die over te nemen, of typ zelf iets.

Bovenaan staan drie knoppen: **wat de zaal ziet**. Alle drie aan laat de tafel
het verschil zien, één aan maakt korter een einde aan de discussie. Staat het
voorstel al op de beamer, dan gaat een klik er meteen naartoe — je hoeft niet
apart te bewaren.

Bij **Iedereen akkoord** vraagt hij eerst wélk voorstel de tafel afgesproken
heeft, met de bedragen erbij. Staan er drie op het scherm, dan is dat de enige
plek waar dat vastgelegd wordt. Pas na die keuze sluit het tornooi af — met die
bedragen in de uitslag; de punten blijven van de eindstand. En de klok stopt:
een afgesloten tornooi kan geen lopende klok meer hebben.

Even split heeft geen telling nodig: dat is de resterende pot gedeeld door het
aantal spelers. Daar staat een aparte knop voor op het telscherm.

### Afsluiten en daarna

`/c/cutoff/tornooien/<id>` toont de uitslag met prijzengeld en punten, en
waarschuwt als het uitbetaalde bedrag afwijkt van de pot.

### Instellingen

`/c/cutoff/instellingen`, alleen voor de eigenaar en beheerders. Hier staat
alles wat vroeger alleen met een SQL van mij te wijzigen was: naam en gemeente,
taal en tijdzone, logo en clubkleur, de hele publieke pagina, de
prijzenverdeling per veldgrootte, het puntensysteem, de seizoenen en het
gedoogbeleid.

Elk blok heeft zijn eigen bewaarknop. Een fout in het ene blok houdt het
andere niet tegen, en je hebt niet het gevoel dat je met de clubkleur ook het
gedoogbeleid mee wegschrijft.

De **prijzenverdeling** typ je als één regel per veldgrootte:
`9;17;50, 30, 20` betekent dat bij negen tot zeventien deelnemers de eerste
drie 50, 30 en 20 procent krijgen. De som hoort rond de honderd te liggen; ver
ernaast weigert hij, want dat is een tikfout.

Wat er bewust niet bij staat: het adres van de club, want daar hangt DNS aan
die niet mee verhuist, en de blindstructuren, want die hebben hun eigen scherm.

Een **floor kan hier niets wijzigen**. Dat wordt niet in het scherm bewaakt
maar in de database, en er staat een test op die het probeert.

Verder in het menu bovenaan: **Klassement** (per seizoen, jaar of maand, met de
puntenformule eronder uitgelegd), **Leden** (met bovenaan wie er geen mailadres
heeft) en **Cijfers** (avonden, deelnames, geld, en twee grafieken over de
laatste twaalf maanden).

De cijfers lopen over **dit jaar, deze maand, alles** of een periode die je
zelf ingeeft. Het seizoen zit er niet meer bij: dat is een begrip van het
klassement — daar bepaalt het wie er meedingt — terwijl je bij de cijfers
kalendertijd wil vergelijken. De gekozen periode staat in de URL, dus je kan
ze bewaren of doorsturen.

### De publieke kant

Nieuw: alles hierboven is voor jou en je floor. Daarnaast heeft de club nu
pagina's voor de zaal, zonder login en mobiel eerst.

De club is bereikbaar op **cutoff.pokerleague.be** zodra jij één jokerteken in
DNS en in Vercel zet — daarna is elke volgende club gratis bereikbaar. Een
eigen domein als app.cutoff.be is een verbetering achteraf, geen voorwaarde
vooraf. De volledige werkwijze staat in `docs/domeinen.md`, en
`clubdomein_zetten.sql` koppelt het domein zodra de DNS actief is.

Dat clubadres (of `/c/cutoff`) is één adres met twee gezichten. Log je in
als staf, dan krijg je het dashboard dat je kent. Iedereen anders krijgt de
publieke voorpagina: wat er nu loopt, wanneer de volgende avond is, de laatste
uitslag en de kop van het klassement.

- **Nu** — loopt er een avond, dan staat daar een knop naar het live-bord.
- **Kalender** — komende avonden en wat er gespeeld is.
- **Klassement** — punten, aantal avonden en beste plaats. Alles, dit jaar of
  deze maand.

Het **live-bord** (`/c/cutoff/live/<id>`) is de avond op een telefoon: de klok
telt lokaal af zodat hij vloeiend loopt, de stand wordt elke acht seconden
opgehaald, en je ziet wie er nog zit en wie eruit is. Is het tornooi
afgelopen, dan toont datzelfde adres de uitslag — zo blijft een link die
tijdens de avond rondging daarna nog kloppen.

**Namen.** Standaard tonen die pagina's gebruikersnamen en geen echte namen:
een naam is een persoonsgegeven en de speler heeft er niets voor getekend.
Voor de eigen pagina's van een club kan dat anders: `publieke_namen_aan.sql`
zet het om, en dan verklaar je dat Cutoff die toestemming heeft via het
clubreglement of het aanmeldformulier. Terugdraaien kan altijd.

**Wat een bezoeker níét ziet**, en dat is met tests vastgelegd: het
geldregister, de spelerstabel met mailadressen, de blindstructuren van de
club, de uitbetaallijst, en tornooien die niet op publiek staan.

---

## 3. Wat je onthoudt over hoe het werkt

**De klok bewaart geen aftellende teller.** Alleen wanneer het level begon en
hoeveel tijd er al opgebouwd was. De resterende tijd is een berekening tegen
servertijd. Daarom overleeft hij een refresh, een tweede scherm en een laptop
die in slaap valt — en loopt hij gewoon door als niemand doorklikt.

Een afgelopen tornooi heeft een stilstaande klok — dat is een regel op de
tabel zelf, niet iets waar elke afsluitroute apart aan moet denken.

Doorrollen gebeurt op die opgebouwde tijd, niet op de wandklok. Een pauze van
een uur schuift dus nooit een level op — de opgebouwde tijd staat stil. Maar
staat er meer tijd geboekt dan het level lang duurt, dan rekent het scherm uit
waar de klok werkelijk staat in plaats van 00:00 te tonen, en de floor-pagina
zet die stand meteen recht in de database.

**Levels worden geteld zonder de pauzes.** Wat de zaal leest als "5 / 17" heet
op de floor ook level 5 van 17. Een pauze heeft een naam, geen nummer.

**De server telt, de browser toont.** Eindplaatsen, prijzengeld en punten worden
in de database berekend, onder een vergrendeling. Twee toestellen die tegelijk
iemand wegklikken kunnen dus niet dezelfde plaats uitdelen.

**Het mailadres is de sleutel.** Er staat een unieke index op over het hele
platform, niet per club. Dezelfde man bij Cutoff en bij Aalst is daardoor één
speler met één historie.

**Elke inkoop is terug te draaien.** Niets wordt gewist; een fout wordt geschrapt
mét de reden. Dat register is je verantwoording tegenover het gedoogbeleid.

**Prijzengeld gaat in hele euro's.** Nooit centen, en de som blijft exact de pot.
Komt een even split niet rond uit, dan gaat de euro die overblijft naar de
grootste stapel — de kortste stapel krijgt er een minder.

**Punten zijn hele getallen.** Afgerond bij de bron en niet in het scherm:
anders tonen drie avonden van 10,5 punten elk 11 terwijl het totaal 32 is.

**Loopt een tornooi voorbij zijn structuur, dan groeit ze mee.** De klok maakt
levels bij in het ritme dat de club zelf hanteert, zodat de blinds blijven
stijgen in plaats van stil te vallen op 00:00. Die levels komen niet in de
database — een structuur wordt gedeeld tussen avonden.

---

## 4. Wat je kan testen

Draai `demo_testavond.sql` en ga naar de floor. Je staat dan met 14 spelers
waarvan 5 nog aan tafel, pot € 320, level 5, inkopen gesloten.

- [ ] Zet het zaalscherm open in een tweede tabblad en leg ze naast elkaar.
      Alles wat je op de floor doet hoort binnen een seconde op de klok te staan.
- [ ] Klok: pauzeren, hervatten, ±1 minuut, een level vooruit en terug.
- [ ] Geluid aanzetten en één level laten aflopen — piep, drieklank, gesproken
      blinds.
- [ ] Volledig scherm aan en met Escape er weer uit.
- [ ] Onderaan het zaalscherm staat de prijzenladder. Past hij op het scherm,
      dan staat hij stil en gecentreerd; is hij te lang, dan schuift hij door.
- [ ] Voeg een speler toe die al lid is, en daarna één met een nieuw mailadres.
- [ ] Probeer iemand toe te voegen zonder mailadres — hij hoort een reden te
      vragen.
- [ ] Voeg iemand toe met een mailadres dat al bestaat; hij hoort aan die
      bestaande speler gekoppeld te worden zonder tweede profiel.
- [ ] Geef een rebuy en draai hem daarna terug. Prijzenpot en teller horen mee
      te bewegen.
- [ ] Schakel iemand uit en draai het terug; zijn stapel hoort er nog te zijn.
- [ ] Prijzengeld: zet 6 plaatsen met plus en min, vink de bubbel aan, leg vast.
      Alle bedragen horen ronde euro's te zijn en op te tellen tot € 320.
- [ ] Schakel iemand uit die net in het geld valt. Zijn bedrag hoort meteen in
      beeld te springen, en hij hoort op de uitbetaallijst te komen.
- [ ] Streep hem af, ververs de pagina: hij hoort afgestreept te blijven.
      Draai het daarna terug.
- [ ] Deal: tel de stapels (probeer eens een totaal ver naast de waarheid — hij
      hoort te weigeren), bekijk de drie voorstellen, zet ze alle drie op het
      zaalscherm, klik er daarna twee weg en kijk of de beamer meteen volgt,
      en sluit af. Hij hoort te vragen welk voorstel het geworden
      is, en de klok hoort daarna stil te staan. Daarna hoort de
      uitbetaallijst de afgesproken bedragen per naam te tonen.
- [ ] Pauzeer en hervat: het zaalscherm hoort "tornooi gepauzeerd" en
      "tornooi hervat" te tonen en om te roepen.
- [ ] Zet de klok op het laatste level en laat het aflopen. Er hoort een
      nieuw level bij te komen met hogere blinds, niet 00:00.
- [ ] Cijfers: klik door dit jaar, deze maand en alles, en geef daarna zelf
      twee data in.
- [ ] Instellingen: verander de clubkleur en kijk of de zaalklok meekleurt.
- [ ] Instellingen: pas de prijzenverdeling aan, maak een nieuw tornooi en kijk
      of de nieuwe ladder erin staat.
- [ ] Instellingen: typ een regel met percentages die optellen tot 70. Hij
      hoort te weigeren en te zeggen waarom.
- [ ] Log in als iemand met de rol floor en open de instellingen. Je hoort een
      melding te krijgen in plaats van een formulier.
- [ ] Open `/c/cutoff` in een privévenster (dus uitgelogd). Je hoort de
      publieke voorpagina te zien en niet het inlogscherm.
- [ ] Volg het live-bord op je telefoon terwijl je op de floor iemand
      uitschakelt. Binnen acht seconden hoort hij bij "Eruit" te staan.
- [ ] Draai `publieke_namen_aan.sql` en herlaad: waar eerst "Speler a3f2"
      stond horen nu de namen te staan.
- [ ] Zet een tornooi op besloten en probeer het live-adres in een
      privévenster: dat hoort niet gevonden te worden.
- [ ] Bekijk de uitslag en daarna het klassement, het ledenbestand en de cijfers.
- [ ] Ledenbestand: vul het mailadres aan van Marcel Vandeputte.

Loopt het spoor door? Draai `demo_testavond.sql` opnieuw; hij zet alles terug.

---

## 5. Wat er nog niet is

- **De spelerskant van PokerLeague**: accounts, online inschrijven, je eigen
  stack ingeven, live klassement, resultaten over clubs heen.
- **De uitnodigingsmails**: staan in de wachtrij, vertrekken pas zodra er een
  mailleverancier aanhangt (Resend of Brevo).
- **Mobiele pass** over de publieke kant.

En op jouw lijstje: DNS voor pokerleague.be, en Supabase op Pro vóór
6 september — anders pauzeert de database na een week stilte en heb je geen
back-ups.
