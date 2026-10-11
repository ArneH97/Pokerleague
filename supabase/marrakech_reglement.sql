-- Pokerleague — het reglement van de Marrakech League als clubpagina
--
-- Zet het officiële reglement op cutoff.pokerleague.be/p/reglement, in drie
-- talen, gekoppeld aan het seizoen Marrakechbound. Twee keer draaien doet
-- niets dubbel: bestaat de pagina al, dan wordt ze bijgewerkt.
--
-- **De Engelse tekst is de versie die telt.** Het reglement is in het Engels
-- geschreven en daar is de juridische formulering op gekozen. Het Nederlands
-- en het Frans zijn getrouwe vertalingen voor de leesbaarheid, geen beëdigde
-- vertalingen. Dat staat ook in artikel 19 van elke versie, zodat er bij een
-- meningsverschil geen discussie is over wélke zin geldt.
--
-- **De affiche.** Zet het adres van de afbeelding hieronder bij c_afbeelding.
-- Laat je het leeg, dan staat de pagina er zonder; je kan ze achteraf altijd
-- toevoegen via Instellingen → Eigen pagina's.
--
-- Draai dit ná migratie 0067 en ná marrakechbound.sql (die het seizoen
-- aanmaakt waar deze pagina aan hangt).

do $$
declare
  c_slug       text := 'cutoff';
  c_seizoen    text := 'Marrakechbound';
  c_pagina     text := 'reglement';
  c_afbeelding text := '/clubs/marrakechbound.webp';

  v_club   uuid;
  v_season uuid;
  v_id     uuid;

  v_titel_nl text := 'Reglement Marrakech Poker League';
  v_titel_fr text := 'Règlement Marrakech Poker League';
  v_titel_en text := 'Marrakech Poker League — Official Rules';

  v_nl text;
  v_fr text;
  v_en text;
begin
  select id into v_club from clubs where slug = c_slug;
  if v_club is null then
    raise exception 'Geen club met slug %.', c_slug;
  end if;

  select id into v_season from seasons where club_id = v_club and name = c_seizoen;
  if v_season is null then
    raise notice 'LET OP  geen seizoen "%" gevonden. De pagina komt er zonder seizoen op te staan.', c_seizoen;
  end if;

  -- =========================================================================
  -- Nederlands
  -- =========================================================================
  v_nl := $nl$**Leagueperiode:** 7 oktober 2026 — 28 februari 2027
**Organisator:** CUTOFF CARDROOM / CUTOFF VZW
**Eindbestemming:** Marrakech, Marokko

---

## 1. Het concept

De CUTOFF Marrakech Poker League is een seizoensgebonden pokerklassement, georganiseerd door CUTOFF CARDROOM.

Spelers verzamelen klassementspunten in de CUTOFF-tornooien die binnen de officiële leagueperiode meetellen.

Het doel is bovenaan het klassement te eindigen en zo het Marrakech-pakket te winnen: de kans om deel te nemen aan het aangeduide Marrakech Poker Open-evenement.

---

## 2. Leagueperiode

De league start op woensdag 7 oktober 2026 en eindigt na het laatste meetellende tornooi op zondag 28 februari 2027.

Alleen tornooien die CUTOFF officieel als leaguetornooi aanduidt, leveren leaguepunten op.

CUTOFF maakt bekend welke tornooien meetellen en, waar van toepassing, met welke puntenweging of bijzondere voorwaarden.

---

## 3. Deelnamevoorwaarden

De league staat open voor spelers die voldoen aan de geldende regels van CUTOFF CARDROOM en aan de voorwaarden van elk afzonderlijk tornooi.

Een speler moet:

- correcte inschrijvingsgegevens opgeven;
- de tornooiregels naleven;
- voldoen aan de leeftijdsvereisten en de wettelijke voorwaarden;
- eerlijk spelen;
- de beslissingen van de tornooileiding volgen.

CUTOFF behoudt zich het recht voor deelname te weigeren of een speler uit te sluiten wanneer dat verantwoord is op grond van de geldende regels, de veiligheid, fair play, wettelijke vereisten of ernstig wangedrag.

---

## 4. Minimum aantal deelnames

**Minstens 10 tornooien.**

Om in aanmerking te komen voor het Marrakech-pakket moet een speler tijdens de leagueperiode aan minstens 10 meetellende leaguetornooien hebben deelgenomen.

Een speler die eerste eindigt in het klassement maar aan minder dan 10 meetellende tornooien heeft deelgenomen, komt niet in aanmerking voor het pakket.

In dat geval gaat het pakket naar de hoogst geklasseerde speler die:

1. de vereiste 10 deelnames wél haalde; en
2. voor het overige aan alle voorwaarden van dit reglement voldoet.

Deze drempel is een voorwaarde om het pakket te krijgen en niet louter een klassementsregel.

---

## 5. Leaguepunten

Elk meetellend tornooi levert punten op volgens de officiële puntentelling van de CUTOFF League.

Punten kunnen worden toegekend op basis van:

- de eindplaats;
- deelname;
- de inleg of categorie van het tornooi;
- bijzondere leaguewegingen;
- andere vooraf aangekondigde sportieve bonussen.

De punten per tornooi worden door CUTOFF geregistreerd en verwerkt in het officiële klassement.

CUTOFF kan verschillende wegingen hanteren voor verschillende tornooicategorieën, om de league evenwichtig en competitief te houden.

---

## 6. De beste resultaten tellen

Om te vermijden dat louter het aantal deelnames de uitslag bepaalt, tellen enkel de 15 beste leagueresultaten van een speler mee voor de eindstand.

De tussenstand van een speler kan tijdens het seizoen dus hoger liggen dan het puntentotaal waarmee hij uiteindelijk geklasseerd wordt.

Speelt een speler meer dan 15 meetellende tornooien, dan kunnen zijn laagst scorende resultaten uit de eindberekening vallen.

De deelnamedrempel blijft 10 werkelijke deelnames, ongeacht hoeveel resultaten er uiteindelijk meetellen.

---

## 7. Het officiële klassement

CUTOFF houdt het klassement bij en publiceert het tijdens het seizoen.

Het gepubliceerde klassement is voorlopig tot de league officieel is afgelopen en alle resultaten en voorwaarden zijn nagekeken.

CUTOFF kan een administratieve, reken- of registratiefout in het klassement rechtzetten.

De definitieve eindstand wordt vastgesteld na het laatste leaguetornooi en na controle van alle deelnamevoorwaarden.

---

## 8. Gelijke stand

Eindigen twee of meer spelers met hetzelfde aantal punten, dan geldt achtereenvolgens:

1. het hoogste aantal tornooioverwinningen tijdens de league;
2. bij verdere gelijkheid, het hoogste aantal tweede plaatsen;
3. bij verdere gelijkheid, het hoogste aantal derde plaatsen;
4. bij verdere gelijkheid, het hoogste resultaat in één tornooi;
5. bij verdere gelijkheid, het grootste aantal deelnames tijdens de leagueperiode.

Blijft het daarna gelijk, dan kan CUTOFF een beslissend tornooi organiseren of een andere eerlijke en objectief toepasbare procedure volgen.

---

## 9. Het Marrakech-pakket

De speler die als eerste eindigt onder alle spelers die aan de voorwaarden voldoen, wint het Marrakech-pakket.

Het pakket bestaat uit:

- een ticket voor het Main Event van de Marrakech Poker Open (12 — 21 maart);
- het verblijf;
- de vluchten.

De geschatte waarde bedraagt € 2.000; zie artikel 10 over wat die waarde betekent.

Het pakket bestaat uitsluitend uit wat hierboven en in de officiële leaguecommunicatie uitdrukkelijk beschreven staat.

Tenzij uitdrukkelijk anders vermeld omvat het pakket geen bijkomende kosten, belastingen, maaltijden, transfers, verzekeringen, persoonlijke uitgaven of andere uitgaven.

Het pakket is bestemd voor het aangeduide Marrakech Poker Open-evenement en is afhankelijk van:

- de beschikbaarheid van het evenement;
- de officiële data ervan;
- de regels en voorwaarden van de organisator van dat evenement;
- de inschrijvingsvereisten van dat tornooi;
- paspoort-, visum- en reisvereisten;
- de beschikbaarheid van de verblijfs- en reisonderdelen uit het pakket.

---

## 10. Geschatte waarde

Wordt er een geldwaarde voor het pakket gecommuniceerd, dan is dat een geschatte waarde en geen geldprijs.

Het pakket kan niet op eenvoudig verzoek van de winnaar in geld worden omgezet.

Tenzij CUTOFF en/of de betrokken leverancier daar schriftelijk mee instemt, kan de winnaar geen geldwaarde opeisen voor een onderdeel van het pakket dat hij niet gebruikt.

---

## 11. Niet overdraagbaar

Het Marrakech-pakket wordt toegekend aan de winnaar van de league en is in beginsel persoonlijk en niet overdraagbaar.

De winnaar mag het pakket niet verkopen, veilen, ruilen of overdragen zonder voorafgaande schriftelijke toestemming van CUTOFF en, waar van toepassing, van de organisator of leverancier in kwestie.

Elke overdracht moet voldoen aan de regels van de Marrakech Poker Open en van de betrokken leveranciers.

---

## 12. Reis en verblijf

Zijn vluchten en/of verblijf inbegrepen, dan gelden ze onder voorbehoud van beschikbaarheid en onder de voorwaarden die aan de winnaar worden meegedeeld.

CUTOFF is niet verantwoordelijk voor kosten die voortkomen uit:

- problemen met paspoort of visum;
- niet afreizen;
- gemiste vluchten;
- persoonlijke wijzigingen aan de reisregeling;
- extra bagage;
- persoonlijke uitgaven;
- reisverzekering;
- kosten door eigen toedoen van de winnaar of door het niet naleven van de reisvereisten.

De precieze reis- en verblijfsregeling wordt meegedeeld zodra het pakket bevestigd is.

---

## 13. Annulering of wijziging van het evenement

De Marrakech Poker Open en de andere evenementen waarnaar het pakket verwijst, worden door derden georganiseerd.

CUTOFF heeft geen zeggenschap over de organisatie, de kalender, een annulering of uitstel, de locatie, de tornooistructuur of andere beslissingen van die organisator.

Wordt het aangeduide evenement geannuleerd, uitgesteld, wezenlijk gewijzigd of onbeschikbaar om redenen buiten de redelijke controle van CUTOFF, dan kan CUTOFF, waar dat redelijkerwijs mogelijk is, voorstellen:

- een gelijkwaardig alternatief;
- een vervangend evenement of pakket;
- een verplaatste deelname;
- of een andere redelijke oplossing.

De winnaar heeft niet automatisch recht op terugbetaling of op de tegenwaarde in geld louter omdat een extern evenement geannuleerd of gewijzigd wordt.

---

## 14. Fair play en uitsluiting

Elke vorm van valsspelen, samenspel, bedrog, opzettelijke manipulatie van leagueresultaten, identiteitsfraude of andere ernstige inbreuk op de integriteit van het tornooi kan leiden tot:

- verlies van leaguepunten;
- annulering van resultaten;
- uitsluiting uit de league;
- verlies van het recht op het Marrakech-pakket.

CUTOFF kan optreden wanneer er redelijke grond is om aan te nemen dat de integriteit van de league is aangetast.

---

## 15. Afwezigheden

Spelers zijn niet verplicht aan elk leaguetornooi deel te nemen.

Ze blijven wel zelf verantwoordelijk voor het halen van de minimumdrempel van 10 deelnames om voor het pakket in aanmerking te komen.

Voor tornooien waaraan een speler niet deelneemt, worden geen punten toegekend.

---

## 16. Wijzigingen aan de league

CUTOFF zal het puntensysteem of de deelnamevoorwaarden niet willekeurig wijzigen om een individuele speler te bevoordelen of te benadelen.

Elke betekenisvolle wijziging aan het reglement wordt publiek meegedeeld vóór ze van kracht wordt.

Wijzigingen kunnen niettemin nodig zijn in uitzonderlijke omstandigheden, waaronder wettelijke vereisten, technische fouten, overmacht, beperkingen van de locatie of omstandigheden buiten de redelijke controle van CUTOFF.

---

## 17. Overmacht

CUTOFF is niet verantwoordelijk voor omstandigheden buiten zijn redelijke controle, waaronder maar niet beperkt tot:

- overheidsmaatregelen;
- wettelijke of reglementaire wijzigingen;
- sluiting of onbeschikbaarheid van de locatie;
- natuurrampen;
- ernstige technische storingen;
- verstoring van het vervoer;
- annulering van externe evenementen;
- oorlog, burgerlijke onrust of andere uitzonderlijke omstandigheden.

CUTOFF zal zich redelijkerwijs inspannen om waar mogelijk een passende oplossing te vinden.

---

## 18. Eindcontrole

Het Marrakech-pakket wordt pas officieel toegekend nadat:

1. het laatste leaguetornooi gespeeld is;
2. de eindstand berekend is;
3. het aantal geldige deelnames van de winnaar nagekeken is;
4. alle voorwaarden gecontroleerd zijn;
5. openstaande betwistingen of administratieve fouten opgelost zijn.

Het bekendmaken van een voorlopige eerste plaats betekent op zich nog geen definitieve bevestiging.

---

## 19. Aanvaarding van het reglement

Deelname aan een meetellend tornooi van de CUTOFF Marrakech Poker League geldt als aanvaarding van dit reglement.

Spelers zijn er zelf verantwoordelijk voor zich vooraf met het reglement vertrouwd te maken.

De geldende versie is die welke CUTOFF CARDROOM via zijn officiële kanalen publiceert. Dit reglement is opgesteld in het Engels; de Nederlandse en Franse tekst zijn vertalingen voor de leesbaarheid. Bij een verschil tussen de versies geldt de Engelse tekst.

---

## 20. Slotbepaling

De CUTOFF Marrakech Poker League wil een eerlijk, transparant en competitief seizoenskampioenschap zijn, met Marrakech als eindpunt.

CUTOFF zal de league consequent, transparant en te goeder trouw beheren, met behoud van de integriteit van de competitie.

**CUTOFF CARDROOM**
*More than a position.*

Officiële leagueperiode: 7 oktober 2026 — 28 februari 2027.$nl$;

  -- =========================================================================
  -- Frans
  -- =========================================================================
  v_fr := $fr$**Période de la ligue :** 7 octobre 2026 — 28 février 2027
**Organisateur :** CUTOFF CARDROOM / CUTOFF ASBL
**Destination finale :** Marrakech, Maroc

---

## 1. Le concept

La CUTOFF Marrakech Poker League est un classement de poker saisonnier organisé par CUTOFF CARDROOM.

Les joueurs accumulent des points de classement lors des tournois CUTOFF retenus pendant la période officielle de la ligue.

L’objectif est de terminer en tête du classement et de remporter le Package Marrakech : la possibilité de participer à l’événement Marrakech Poker Open désigné.

---

## 2. Période de la ligue

La ligue démarre le mercredi 7 octobre 2026 et se termine après le dernier tournoi retenu, le dimanche 28 février 2027.

Seuls les tournois officiellement désignés par CUTOFF comme tournois de ligue attribuent des points.

CUTOFF publiera les tournois retenus et, le cas échéant, leur pondération ou leurs conditions particulières.

---

## 3. Conditions de participation

La ligue est ouverte aux joueurs qui respectent le règlement de CUTOFF CARDROOM ainsi que les conditions propres à chaque tournoi.

Un joueur doit :

- fournir des données d’inscription exactes ;
- respecter le règlement des tournois ;
- satisfaire aux conditions d’âge et aux exigences légales ;
- jouer loyalement ;
- se conformer aux décisions de la direction du tournoi.

CUTOFF se réserve le droit de refuser la participation ou d’exclure un joueur lorsque cela se justifie au regard du règlement, de la sécurité, du fair-play, des exigences légales ou d’une faute grave.

---

## 4. Nombre minimum de participations

**Au moins 10 tournois.**

Pour prétendre au Package Marrakech, un joueur doit avoir participé à au moins 10 tournois de ligue retenus pendant la période de la ligue.

Un joueur qui termine premier au classement mais qui a participé à moins de 10 tournois retenus ne peut pas recevoir le package.

Dans ce cas, le package revient au joueur le mieux classé qui :

1. atteint le minimum requis de 10 participations ; et
2. satisfait par ailleurs à toutes les conditions du présent règlement.

Cette exigence est une condition d’attribution du package et non un simple critère de classement.

---

## 5. Points de ligue

Chaque tournoi retenu attribue des points selon le barème officiel de la CUTOFF League.

Les points peuvent être attribués en fonction :

- de la place finale ;
- de la participation ;
- de la cave ou de la catégorie du tournoi ;
- de pondérations particulières de la ligue ;
- d’autres bonus sportifs annoncés à l’avance.

Les points de chaque tournoi sont enregistrés par CUTOFF et repris dans le classement officiel.

CUTOFF peut appliquer des pondérations différentes selon les catégories de tournois, afin de préserver l’équilibre et la compétitivité de la ligue.

---

## 6. Les meilleurs résultats comptent

Afin d’éviter que le seul volume de participations détermine le résultat final, seuls les 15 meilleurs résultats d’un joueur comptent pour le classement final.

Le total d’un joueur peut donc être plus élevé en cours de saison que le score finalement retenu.

Si un joueur dispute plus de 15 tournois retenus, ses résultats les plus faibles peuvent être écartés du calcul final.

L’exigence de participation reste de 10 participations effectives, quel que soit le nombre de résultats finalement retenus.

---

## 7. Le classement officiel

CUTOFF tient le classement à jour et le publie tout au long de la saison.

Le classement publié est provisoire jusqu’à la clôture officielle de la ligue et la vérification de tous les résultats et de toutes les conditions.

CUTOFF peut corriger une erreur administrative, de calcul ou d’enregistrement constatée dans le classement.

Le classement final est établi après le dernier tournoi de ligue et après vérification de toutes les conditions d’éligibilité.

---

## 8. Égalité

Si deux joueurs ou plus terminent à égalité de points, les critères suivants s’appliquent successivement :

1. le plus grand nombre de victoires en tournoi pendant la ligue ;
2. en cas d’égalité persistante, le plus grand nombre de deuxièmes places ;
3. en cas d’égalité persistante, le plus grand nombre de troisièmes places ;
4. en cas d’égalité persistante, le meilleur score réalisé sur un seul tournoi ;
5. en cas d’égalité persistante, le plus grand nombre de participations pendant la période de la ligue.

Si l’égalité subsiste, CUTOFF peut organiser un tournoi de départage ou appliquer une autre procédure équitable et objective.

---

## 9. Le Package Marrakech

Le joueur qui termine premier parmi tous les joueurs remplissant les conditions remporte le Package Marrakech.

Le package comprend :

- un ticket pour le Main Event du Marrakech Poker Open (12 — 21 mars) ;
- l’hébergement ;
- les vols.

La valeur estimée s’élève à 2 000 € ; voir l’article 10 sur la portée de cette valeur.

Le package se compose uniquement des éléments décrits ci-dessus et dans la communication officielle de la ligue.

Sauf mention expresse contraire, le package ne comprend aucun frais supplémentaire, taxe, repas, transfert, assurance, dépense personnelle ou autre coût.

Le package est destiné à l’événement Marrakech Poker Open désigné et dépend :

- de la disponibilité de l’événement ;
- de ses dates officielles ;
- du règlement et des conditions de son organisateur ;
- des conditions d’inscription applicables ;
- des exigences de passeport, de visa et de voyage ;
- de la disponibilité des éléments d’hébergement et de transport compris dans le package.

---

## 10. Valeur estimée

Lorsqu’une valeur monétaire est communiquée pour le Package Marrakech, il s’agit d’une valeur estimée et non d’un prix en espèces.

Le package ne peut pas être converti en espèces à la seule demande du gagnant.

Sauf accord écrit de CUTOFF et/ou du fournisseur concerné, le gagnant ne peut pas réclamer la contre-valeur en espèces d’un élément non utilisé du package.

---

## 11. Incessibilité

Le Package Marrakech est attribué au vainqueur de la ligue ; il est en principe personnel et incessible.

Le gagnant ne peut ni vendre, ni mettre aux enchères, ni échanger, ni céder le package sans l’accord écrit préalable de CUTOFF et, le cas échéant, de l’organisateur ou du fournisseur concerné.

Toute cession doit respecter le règlement du Marrakech Poker Open et celui des fournisseurs concernés.

---

## 12. Voyage et hébergement

Lorsque des vols et/ou un hébergement sont compris, ils le sont sous réserve de disponibilité et aux conditions communiquées au gagnant.

CUTOFF n’est pas responsable des frais résultant :

- de problèmes de passeport ou de visa ;
- d’un départ non effectué ;
- de vols manqués ;
- de modifications personnelles de l’itinéraire ;
- de bagages supplémentaires ;
- de dépenses personnelles ;
- d’une assurance voyage ;
- de frais causés par le gagnant lui-même ou par le non-respect des exigences de voyage.

Les modalités exactes de voyage et d’hébergement seront communiquées au gagnant dès confirmation du package.

---

## 13. Annulation ou modification de l’événement

Le Marrakech Poker Open et les autres événements visés par le package sont organisés par des tiers.

CUTOFF ne maîtrise ni l’organisation, ni le calendrier, ni une annulation ou un report, ni le lieu, ni la structure des tournois, ni les autres décisions de cet organisateur.

Si l’événement désigné est annulé, reporté, modifié de manière substantielle ou devient indisponible pour des raisons échappant au contrôle raisonnable de CUTOFF, CUTOFF peut, dans la mesure du possible, proposer :

- une alternative équivalente ;
- un événement ou un package de remplacement ;
- une participation reportée ;
- ou une autre solution raisonnable.

Le vainqueur n’a pas automatiquement droit à un remboursement ou à une contre-valeur en espèces du seul fait de l’annulation ou de la modification d’un événement externe.

---

## 14. Fair-play et disqualification

Toute forme de triche, de collusion, de fraude, de manipulation intentionnelle des résultats, de falsification d’identité ou toute autre atteinte grave à l’intégrité des tournois peut entraîner :

- la perte de points de ligue ;
- l’annulation de résultats ;
- l’exclusion de la ligue ;
- la perte du droit au Package Marrakech.

CUTOFF peut intervenir lorsqu’il existe des motifs raisonnables de penser que l’intégrité de la ligue a été compromise.

---

## 15. Absences

Les joueurs ne sont pas tenus de participer à tous les tournois de la ligue.

Il leur appartient toutefois d’atteindre le minimum de 10 participations requis pour prétendre au Package Marrakech.

Aucun point n’est attribué pour les tournois auxquels un joueur ne participe pas.

---

## 16. Modifications de la ligue

CUTOFF ne modifiera pas arbitrairement le système de classement ni les conditions de participation dans le but d’avantager ou de désavantager un joueur.

Toute modification significative du règlement sera communiquée publiquement avant son entrée en vigueur.

Des modifications peuvent néanmoins s’imposer dans des circonstances exceptionnelles : exigences légales, erreurs techniques, force majeure, restrictions liées au lieu ou circonstances échappant au contrôle raisonnable de CUTOFF.

---

## 17. Force majeure

CUTOFF ne peut être tenu responsable de circonstances échappant à son contrôle raisonnable, notamment :

- des mesures gouvernementales ;
- des changements légaux ou réglementaires ;
- la fermeture ou l’indisponibilité du lieu ;
- des catastrophes naturelles ;
- des pannes techniques graves ;
- des perturbations des transports ;
- l’annulation d’événements externes ;
- la guerre, des troubles civils ou d’autres circonstances exceptionnelles.

CUTOFF mettra tout en œuvre pour trouver une solution appropriée lorsque cela est possible.

---

## 18. Vérification finale

Le Package Marrakech ne sera officiellement attribué qu’après que :

1. le dernier tournoi de ligue a été disputé ;
2. le classement final a été calculé ;
3. le nombre de participations valables du gagnant a été vérifié ;
4. toutes les conditions d’éligibilité ont été contrôlées ;
5. les litiges ou erreurs administratives en suspens ont été réglés.

L’annonce d’une première place provisoire ne vaut pas confirmation définitive.

---

## 19. Acceptation du règlement

La participation à un tournoi retenu de la CUTOFF Marrakech Poker League vaut acceptation du présent règlement.

Il appartient aux joueurs de prendre connaissance du règlement avant de participer.

La version applicable est celle publiée par CUTOFF CARDROOM via ses canaux officiels. Le présent règlement a été rédigé en anglais ; les textes néerlandais et français sont des traductions de lecture. En cas de divergence, le texte anglais prévaut.

---

## 20. Clause finale

La CUTOFF Marrakech Poker League entend être un championnat saisonnier équitable, transparent et compétitif, avec Marrakech comme point d’arrivée.

CUTOFF s’efforcera de gérer la ligue de manière cohérente, transparente et de bonne foi, en préservant l’intégrité de la compétition.

**CUTOFF CARDROOM**
*More than a position.*

Période officielle de la ligue : 7 octobre 2026 — 28 février 2027.$fr$;

  -- =========================================================================
  -- Engels — de versie die telt
  -- =========================================================================
  v_en := $en$**League period:** October 7, 2026 — February 28, 2027
**Organiser:** CUTOFF CARDROOM / CUTOFF ASBL
**Final destination:** Marrakech, Morocco

---

## 1. The concept

The CUTOFF Marrakech Poker League is a seasonal poker ranking competition organised by CUTOFF CARDROOM.

Players accumulate ranking points through eligible CUTOFF tournaments held during the official League Period.

The ultimate objective is to finish at the top of the League standings and qualify for the Marrakech Package, giving the winner the opportunity to participate in the designated Marrakech Poker Open event.

---

## 2. League period

The League officially starts on Wednesday, October 7, 2026 and ends after the final eligible tournament held on Sunday, February 28, 2027.

Only tournaments officially designated by CUTOFF as League tournaments will award League Points.

CUTOFF will publish the eligible tournaments and, where applicable, their respective point multipliers or special conditions.

---

## 3. Eligibility

The League is open to players who comply with the applicable rules of CUTOFF CARDROOM and the conditions applicable to each individual tournament.

A player must:

- provide accurate registration information;
- comply with the tournament rules;
- comply with the applicable age and legal requirements;
- play fairly and honestly;
- comply with the decisions of the tournament staff.

CUTOFF reserves the right to refuse participation or exclude a player where this is justified by the applicable rules, safety, fair play, legal requirements or serious misconduct.

---

## 4. Minimum participation requirement

**10 tournaments minimum.**

To be eligible to receive the Marrakech Package, a player must have participated in a minimum of 10 eligible League tournaments during the League Period.

A player who finishes first in the League standings but has participated in fewer than 10 eligible tournaments will not be eligible to receive the Marrakech Package.

In such a case, the package will pass to the highest-ranked player who:

1. has achieved the required minimum of 10 participations; and
2. otherwise satisfies all conditions of these Rules.

This requirement is a condition of eligibility for the package and not merely a ranking criterion.

---

## 5. League points

Each eligible tournament awards League Points according to the official CUTOFF League Points structure.

Points may be awarded according to:

- finishing position;
- participation;
- tournament buy-in/category;
- special League multipliers;
- other clearly announced sporting bonuses.

The exact points awarded for each tournament will be recorded by CUTOFF and reflected in the official League standings.

CUTOFF may use different point multipliers for different tournament categories in order to maintain a balanced and competitive League.

---

## 6. Best results count

To prevent participation volume alone from determining the final result, only a player's 15 best League results will count toward the final League ranking.

A player's total League score may therefore be higher during the season than the score ultimately used for the final ranking.

If a player participates in more than 15 eligible tournaments, the player's lowest-scoring eligible results may be discarded from the final calculation.

The participation requirement remains 10 actual eligible tournament participations, regardless of how many results ultimately count toward the final score.

---

## 7. Official League standings

CUTOFF will maintain and publish the League standings throughout the season.

The standings published by CUTOFF are provisional until the League has officially ended and all results and eligibility requirements have been verified.

CUTOFF may correct an administrative, calculation or recording error discovered in the standings.

The final official standings will be established after the final League tournament and after verification of all eligibility requirements.

---

## 8. Tie-break procedure

If two or more eligible players finish with the same number of final League Points, the following tie-break procedure will apply:

1. Highest number of tournament wins during the League.
2. If still tied, highest number of second-place finishes.
3. If still tied, highest number of third-place finishes.
4. If still tied, highest single tournament score.
5. If still tied, the player with the greater number of eligible tournament participations during the League Period.

If a tie remains after all of the above criteria, CUTOFF may organise a final tie-break tournament or another fair and objectively applicable procedure.

---

## 9. The Marrakech Package

The player who finishes first among all eligible players in the final League standings will be awarded the Marrakech Package.

The package consists of:

- a Main Event ticket for the Marrakech Poker Open (12 — 21 March);
- accommodation;
- flights.

The estimated value is € 2,000; see article 10 on what that value means.

The package consists only of the elements described above and in the official League communication.

Unless expressly stated otherwise, the package does not include any additional expenses, taxes, meals, transfers, insurance, personal expenses or other costs.

The package is intended for the designated Marrakech Poker Open event and is subject to:

- the availability of the event;
- the official dates of the event;
- the rules and conditions of the event organiser;
- any applicable tournament registration requirements;
- passport, visa and travel requirements;
- availability of the accommodation and travel components included in the package.

---

## 10. Estimated value

Where a monetary value is communicated for the Marrakech Package, such value is an estimated value and does not constitute a cash prize.

The package cannot be exchanged for cash solely at the request of the winner.

Unless otherwise agreed in writing by CUTOFF and/or the relevant package provider, the winner cannot demand the cash equivalent of any unused component of the package.

---

## 11. Non-transferability

The Marrakech Package is awarded to the eligible League winner and is generally personal and non-transferable.

The winner may not sell, auction, exchange or transfer the package to another person without the prior written approval of CUTOFF and, where applicable, the relevant event organiser or service provider.

Any transfer must comply with the rules of the Marrakech Poker Open and the relevant suppliers.

---

## 12. Travel and accommodation

Where flights and/or accommodation are included, they are subject to availability and the conditions communicated to the winner.

CUTOFF is not responsible for costs resulting from:

- passport or visa issues;
- failure to travel;
- missed flights;
- personal changes to travel arrangements;
- additional baggage;
- personal expenses;
- travel insurance;
- costs caused by the winner's own actions or failure to comply with travel requirements.

The exact travel and accommodation arrangements will be communicated to the winner once the package has been confirmed.

---

## 13. Event cancellation or changes

The Marrakech Poker Open and other events referred to in the package are organised by third parties.

CUTOFF does not control the organisation, scheduling, cancellation, postponement, venue, tournament structure or other operational decisions of the event organiser.

If the designated event is cancelled, postponed, materially changed or becomes unavailable for reasons outside CUTOFF's reasonable control, CUTOFF may, where reasonably possible, offer:

- an equivalent alternative;
- a replacement event or package;
- a rescheduled participation;
- or another reasonable solution.

The League winner shall not automatically be entitled to a cash refund or cash equivalent solely because an external event is cancelled or modified.

---

## 14. Fair play and disqualification

Any form of cheating, collusion, fraud, intentional manipulation of League results, falsification of identity or other serious breach of tournament integrity may result in:

- loss of League Points;
- cancellation of results;
- exclusion from the League;
- loss of eligibility for the Marrakech Package.

CUTOFF may take appropriate action where there is a reasonable basis to believe that the integrity of the League has been compromised.

---

## 15. Absences

Players are not required to participate in every League tournament.

However, players remain responsible for satisfying the minimum requirement of 10 eligible tournament participations in order to qualify for the Marrakech Package.

No additional points will be awarded for tournaments a player does not attend.

---

## 16. Changes to the League

CUTOFF will not arbitrarily modify the League's fundamental ranking system or eligibility conditions in order to favour or disadvantage an individual player.

Any significant modification to the League rules will be communicated publicly before it takes effect.

Changes may nevertheless be necessary in exceptional circumstances, including legal requirements, technical errors, force majeure, venue restrictions or circumstances beyond the reasonable control of CUTOFF.

---

## 17. Force majeure

CUTOFF shall not be held responsible for circumstances beyond its reasonable control, including but not limited to:

- government restrictions;
- legal or regulatory changes;
- closure or unavailability of the venue;
- natural disasters;
- serious technical failures;
- transportation disruption;
- cancellation of external events;
- war, civil unrest or other exceptional circumstances.

CUTOFF will make reasonable efforts to find an appropriate solution where possible.

---

## 18. Final verification

The Marrakech Package will only be officially awarded after:

1. the final League tournament has been completed;
2. the final League standings have been calculated;
3. the winner's total number of eligible participations has been verified;
4. all applicable eligibility requirements have been checked;
5. any outstanding disputes or administrative errors have been resolved.

The announcement of a provisional first-place player does not, by itself, constitute final confirmation of package eligibility.

---

## 19. Acceptance of the rules

Participation in an eligible CUTOFF Marrakech Poker League tournament constitutes acceptance of these Rules and Conditions.

Players are responsible for familiarising themselves with the League rules before participating.

The current official version of these Rules and Conditions is the version published by CUTOFF CARDROOM through its official communication channels. These Rules were drafted in English; the Dutch and French texts are reading translations. In the event of any discrepancy, the English text prevails.

---

## 20. Final clause

The purpose of the CUTOFF Marrakech Poker League is to create a fair, transparent and competitive seasonal poker championship leading to Marrakech.

CUTOFF will endeavour to administer the League consistently, transparently and in good faith while preserving the integrity of the competition.

**CUTOFF CARDROOM**
*More than a position.*

Official League Period: October 7, 2026 — February 28, 2027.$en$;

  -- =========================================================================
  -- Wegschrijven
  -- =========================================================================
  select id into v_id from club_pages where club_id = v_club and slug = c_pagina;

  if v_id is null then
    insert into club_pages (
      club_id, season_id, slug, is_published, sort_order, image_url,
      title_nl, body_nl, title_fr, body_fr, title_en, body_en)
    values (
      v_club, v_season, c_pagina, true, 0, c_afbeelding,
      v_titel_nl, v_nl, v_titel_fr, v_fr, v_titel_en, v_en);
    raise notice 'OK  pagina "/p/%" aangemaakt en gepubliceerd.', c_pagina;
  else
    update club_pages
    set season_id = coalesce(v_season, season_id),
        is_published = true,
        image_url = coalesce(c_afbeelding, image_url),
        title_nl = v_titel_nl, body_nl = v_nl,
        title_fr = v_titel_fr, body_fr = v_fr,
        title_en = v_titel_en, body_en = v_en
    where id = v_id;
    raise notice 'OK  pagina "/p/%" bestond al en is bijgewerkt.', c_pagina;
  end if;

  raise notice '---';
  raise notice 'Te zien op: https://cutoff.pokerleague.be/p/%', c_pagina;
  raise notice 'En als link onder het klassement van "%".', c_seizoen;
  if c_afbeelding is null then
    raise notice 'Er staat nog geen affiche bij. Die kan je toevoegen via Instellingen, Eigen pagina''s.';
  end if;
end $$;

-- ===========================================================================
-- Nakijken
-- ===========================================================================

select
  cp.slug,
  cp.is_published                        as gepubliceerd,
  s.name                                 as seizoen,
  cp.image_url                           as affiche,
  length(cp.body_nl)                     as tekens_nl,
  length(cp.body_fr)                     as tekens_fr,
  length(cp.body_en)                     as tekens_en,
  to_char(cp.updated_at, 'dd/mm/yyyy HH24:MI') as bijgewerkt
from club_pages cp
join clubs c on c.id = cp.club_id
left join seasons s on s.id = cp.season_id
where c.slug = 'cutoff'
order by cp.sort_order, cp.slug;
