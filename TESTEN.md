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
```

Alle veertien zijn meerdere keren te draaien zonder schade — ik heb ze twee keer
na elkaar over een gevulde database gehaald. Weet je niet meer waar je stond,
draai ze dan gewoon allemaal.

Daarna, om te testen:

```
demo_cutoff.sql       28 verzonnen spelers, 14 afgesloten avonden over 7 maanden
demo_testavond.sql    één avond die nu middenin de finaletafel staat
```

En `demo_cutoff_wissen.sql` haalt beide er weer uit. Doe dat vóór 6 september.

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
om die over te nemen, of typ zelf iets. Met de vinkjes kies je wat de zaal te
zien krijgt — alle drie tegelijk mag.

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

Verder in het menu bovenaan: **Klassement** (per seizoen, jaar of maand, met de
puntenformule eronder uitgelegd), **Leden** (met bovenaan wie er geen mailadres
heeft) en **Cijfers** (avonden, deelnames, geld, en twee grafieken over de
laatste twaalf maanden).

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
      zaalscherm, en sluit af. Hij hoort te vragen welk voorstel het geworden
      is, en de klok hoort daarna stil te staan. Daarna hoort de
      uitbetaallijst de afgesproken bedragen per naam te tonen.
- [ ] Bekijk de uitslag en daarna het klassement, het ledenbestand en de cijfers.
- [ ] Ledenbestand: vul het mailadres aan van Marcel Vandeputte.

Loopt het spoor door? Draai `demo_testavond.sql` opnieuw; hij zet alles terug.

---

## 5. Wat er nog niet is

- **De spelerskant van PokerLeague**: accounts, online inschrijven, je eigen
  stack ingeven, live klassement, resultaten over clubs heen.
- **De uitnodigingsmails**: staan in de wachtrij, vertrekken pas zodra er een
  mailleverancier aanhangt (Resend of Brevo).
- **Instellingen per club**: de prijzenverdeling per veldgrootte en het
  puntensysteem zitten alleen in de database, daar is nog geen scherm voor.
- **Mobiele pass** over de publieke kant.

En op jouw lijstje: DNS voor pokerleague.be, en Supabase op Pro vóór
6 september — anders pauzeert de database na een week stilte en heb je geen
back-ups.
