-- Pokerleague — de demogegevens uit Aalst Poker Club halen
--
-- Vóór de eerste échte avond moet dit weg. Niet omdat het stuk gaat — de
-- demo-avonden zijn gewone avonden en de app rekent er correct mee — maar
-- omdat ze meetellen. Het klassement van het seizoen, het gemiddelde veld, de
-- ledenlijst: overal staan dertien verzonnen mensen tussen. De eerste speler
-- die vanavond zijn naam in de ranking zoekt, vindt zichzelf onderaan achter
-- acht avonden die nooit gespeeld zijn.
--
-- Wat eruit gaat is precies wat het demoscript erin zette, en niets anders:
-- alles met `Demo ·` in de naam en alle spelers op `@demo.pokerleague.be`.
-- Echte spelers, echte avonden en jouw eigen profiel blijven staan. Dat is
-- ook waarom er hier geen `delete from tournaments where club_id = ...` staat
-- zonder meer: één zo'n regel op de verkeerde avond en de uitslag is weg.
--
-- HOE GEBRUIK JE DIT
--
--   1. Draai het bestand zoals het is. Er wordt dan nog niets verwijderd —
--      je krijgt te zien wát er zou verdwijnen.
--   2. Klopt dat, zet `c_echt_doen` op `true` en draai het opnieuw.
--
-- Die tussenstap staat er met opzet in. Dit is een script dat gegevens weggooit
-- in een echte database, en het wordt gedraaid op de avond zelf — het uur
-- waarop je het minst zin hebt om na te denken.

do $$
declare
  -- Zet dit op true om echt te verwijderen.
  c_echt_doen boolean := false;
  c_slug      text    := 'aalst';

  v_club     uuid;
  v_tornooi  int;
  v_spelers  int;
  v_leden    int;
  v_uitslag  int;
  v_struct   int;
  v_pay      int;
begin
  select id into v_club from clubs where slug = c_slug;
  if v_club is null then
    raise exception 'Geen club met slug %.', c_slug;
  end if;

  -- Eerst tellen. Ook in de echte doorloop: dan staat in de melding wat er
  -- weg is, en niet alleen dat er iets weg is.
  select count(*) into v_tornooi
    from tournaments where club_id = v_club and name like 'Demo ·%';

  select count(*) into v_uitslag
    from tournament_results r
    join tournaments t on t.id = r.tournament_id
   where t.club_id = v_club and t.name like 'Demo ·%';

  select count(*) into v_leden
    from club_players cp
    join players p on p.id = cp.player_id
   where cp.club_id = v_club and p.email like '%@demo.pokerleague.be';

  select count(*) into v_spelers
    from players where email like '%@demo.pokerleague.be';

  select count(*) into v_struct
    from blind_structures where club_id = v_club and name like 'Demo ·%';

  select count(*) into v_pay
    from payout_templates where club_id = v_club and name like 'Demo ·%';

  raise notice 'Bij %: % demo-avonden met % uitslagen, % demoleden (% demospelers in totaal), % structuren, % uitbetalingsschema''s.',
    c_slug, v_tornooi, v_uitslag, v_leden, v_spelers, v_struct, v_pay;

  if not c_echt_doen then
    raise notice 'PROEFDRAAI — er is niets verwijderd. Zet c_echt_doen op true en draai opnieuw.';
    return;
  end if;

  -- De avonden. Deelnemers, inkopen, uitschakelingen en uitslagen gaan mee
  -- via de cascade-regels op de tabellen.
  delete from tournaments
   where club_id = v_club and name like 'Demo ·%';

  delete from player_invites
   where player_id in (select id from players where email like '%@demo.pokerleague.be');

  delete from club_players
   where club_id = v_club
     and player_id in (select id from players where email like '%@demo.pokerleague.be');

  -- Alleen spelers die daarna nergens meer voorkomen. Speelde een demospeler
  -- ook bij een andere club mee, dan blijft hij bestaan — zijn rij weghalen
  -- zou daar een uitslag breken.
  delete from players p
   where p.email like '%@demo.pokerleague.be'
     and not exists (select 1 from tournament_results r  where r.player_id  = p.id)
     and not exists (select 1 from tournament_players tp where tp.player_id = p.id)
     and not exists (select 1 from club_players cp       where cp.player_id = p.id);

  delete from blind_structures  where club_id = v_club and name like 'Demo ·%';
  delete from payout_templates  where club_id = v_club and name like 'Demo ·%';

  raise notice 'Weg. % is nu leeg op de echte gegevens na.', c_slug;
end $$;

-- Nakijken wat er overblijft. Hier hoort na het opruimen niets meer te staan
-- met "Demo ·" erin, en de ledenlijst hoort alleen echte mensen te bevatten.
select t.name, t.scheduled_at::date as datum, t.status
from tournaments t
join clubs c on c.id = t.club_id
where c.slug = 'aalst'
order by t.scheduled_at desc;

select p.display_name, p.email, p.link_state
from club_players cp
join clubs c   on c.id = cp.club_id
join players p on p.id = cp.player_id
where c.slug = 'aalst'
order by p.display_name;
