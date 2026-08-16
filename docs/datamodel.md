# Datamodel

Twee beslissingen in dit schema zijn later niet meer goedkoop te wijzigen. De
rest is gewoon werk.

## 1. Speleridentiteit staat los van de club

`players` is platformbreed: één rij per persoon, over alle clubs heen.
`club_players` is slechts de kijk van één club op die persoon — lidnummer,
bijnaam, sinds wanneer.

Een club maakt aan de tafel een **schaduwprofiel** aan: een `players`-rij zonder
`auth_user_id`, met `link_state = 'shadow'`. Dat kost de floor twee seconden en
er komt geen e-mailadres aan te pas. Later stuurt de club een uitnodiging
(`player_invites`), de speler registreert zich, en `auth_user_id` wordt
ingevuld — `link_state` gaat naar `claimed`.

Speelt diezelfde persoon ook bij een andere club, dan hangt er een tweede
`club_players`-rij aan dezelfde `players`-rij. Zijn historie bij beide clubs is
vanaf dat moment één geheel, zonder migratie.

Dubbels blijven onvermijdelijk — dezelfde man die bij twee clubs anders
geregistreerd staat. Daarvoor is `merged_into_id`: de oude rij blijft bestaan
zodat bestaande verwijzingen niet breken, en `resolve_player()` volgt de
pointer naar de overlevende.

Zou je spelers per club opslaan, dan is een ranking over clubs heen later
alleen nog te bouwen met een pijnlijke datamigratie en handmatig ontdubbelen.

## 2. Elke clubgebonden tabel draagt `club_id`

Strikt genomen redundant — je kan `club_id` altijd via de foreign keys
afleiden. Maar het maakt elke RLS-policy één simpele check in plaats van een
join per policy, en dat scheelt zowel fouten als querytijd. Een club kan nooit
data van een andere club zien; dat is afgedwongen in de database, niet in de
applicatie.

## Puntensystemen zijn configuratie, geen code

Vrijwel elke amateurclub rekent zijn seizoensranking anders. `ranking_configs`
ondersteunt vier methodes met parameters:

| Methode | Formule | Parameters |
|---|---|---|
| `fixed_table` | vaste puntentabel per plaats | `table`, `tail` |
| `linear` | `base − (plaats−1) × decrement`, met bodem | `base`, `decrement`, `floor` |
| `sqrt_ratio` | `multiplier × √N / √plaats` | `multiplier` |
| `pokerstars` | `multiplier × (√N/√plaats) × log₁₀(1+buy-in)` | `multiplier` |

Plus `bonus_per_ko`, `bonus_entry`, `count_best_n` (alleen de beste N tornooien
tellen mee) en `min_tournaments`.

Bewust geen vrij invoerbare formule: dat is een injectierisico en op termijn
onderhoudt niemand het. Een nieuwe methode toevoegen is één `case`-tak in
`calc_points()`.

## Geld

Alles in **hele centen**, nooit floats. Drie stromen die niet door elkaar mogen
lopen:

- `amount_cents` — gaat naar de prijzenpot
- `fee_cents` — clubbijdrage, blijft bij de club
- `bounty_cents` — gaat rechtstreeks naar wie de knock-out maakt

`finalize_tournament()` rekent de pot uitsluitend uit `amount_cents`. De
afronding van de payouts gaat naar beneden op een veelvoud (standaard €5), en
het restant gaat naar plaats 1 zodat de som exact de pot is — anders klopt de
kas aan het eind van de avond niet.

## `buyins` is het compliance-register

Elke euro die iemand inzet staat als aparte rij met tijdstip, speler en type.
Dat is precies wat een club moet kunnen tonen om aan te tonen dat niemand boven
de daglimiet uit het gedoogbeleid van de Kansspelcommissie ging (€50 buy-in,
één re-entry, €100 per speler per dag).

De trigger `enforce_compliance_on_buyin` bewaakt dat bij het inboeken. Het
gedrag staat per club in `clubs.compliance` en kent drie standen: `off`, `warn`
en `block`. Configureerbaar omdat dit gedoogbeleid is en geen wet — het
koninklijk besluit dat de voorwaarden vastlegt moet nog komen, en die getallen
gaan bewegen.

### De dag hoort bij de club, niet bij de server

Een pokeravond loopt door na middernacht en de databaseserver draait op UTC.
Om 00:30 in Brussel is het in UTC nog de vorige dag. Wie de daglimiet tegen
`current_date` telt, telt hem tegen de verkeerde dag — en precies bij de late
re-entries, wanneer het er het meest toe doet.

Daarom bucket `daily_spend_unchecked()` elke inkoop op de lokale dag van de
club waar hij plaatsvond, en bepaal je de dag met `club_today(club_id)`. Er
staat een regressietest op in `supabase/tests/engine_test.sql`.

### Functies die RLS omzeilen

`finalize_tournament`, `season_standings` en `player_daily_spend_cents` zijn
`security definer` en omzeilen dus RLS. Zonder extra grens zou elke ingelogde
speler ze kunnen aanroepen voor eender welke club.

Ze controleren daarom zelf de rechten via `is_service_context()`, dat kijkt
naar de **rol uit het JWT** en niet naar `current_user`. Dat onderscheid is
essentieel: binnen een `security definer`-functie is `current_user` altijd de
eigenaar van die functie, dus een controle daarop zou voor iedereen slagen.

`daily_spend_unchecked()` heeft die controle bewust niet — de
compliance-trigger draait midden in een verzoek van een floormedewerker en
heeft het totaal over alle clubs nodig. De beveiliging zit daar in een
`revoke` op `anon` en `authenticated`, wat niet te omzeilen is met een
geknutseld token.

### Append-only

Het register is append-only. Een fout corrigeer je met `is_void = true` en een
reden, niet met een `delete`. Spelers zien deze tabel nooit; er is geen enkele
leespolicy voor hen.

## De klok

`tournaments` bewaart géén aftellende teller, maar `level_started_at` en
`level_elapsed_ms`. De resterende tijd is altijd een berekening tegen
servertijd, uitgevoerd in `src/lib/tournament/clock.ts`.

Daardoor overleeft de klok een refresh, een tweede scherm dat later aansluit,
en een laptop die in slaap valt. `resolveClock()` rolt bovendien automatisch
door verlopen levels heen: als de floor vergeet door te klikken loopt de klok
gewoon door in plaats van te bevriezen op 00:00.

Alle klokfuncties zijn puur — de tijd komt als argument binnen, nooit via
`Date.now()` in de functie zelf. Dat maakt ze testbaar en zorgt dat een
verkeerd ingestelde laptopklok de blinds niet beïnvloedt.

## Zichtbaarheid en GDPR

`players.public_profile` staat standaard op `false`. Een speler verschijnt pas
in een publieke ranking als hij dat zelf aanzet bij het claimen van zijn
profiel. Per tornooi bepaalt `player_visibility` (`private` / `members` /
`public`) wie de deelnemerslijst en de stand mag zien.
