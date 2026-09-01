-- ===========================================================================
--  P O K E R L E A G U E   —   S C H O N E   L E I ,   N U
-- ===========================================================================
--
--  Dit bestand heeft GEEN schakelaar. Draaien is doen.
--
--  De vorige versie deed standaard niets en vroeg om een `false` naar `true`
--  te zetten. Bedoeld als veiligheid, in de praktijk twee keer de reden dat
--  er niets gebeurde. Wat je wil is duidelijk genoeg om er geen tussenstap
--  meer voor te vragen.
--
-- ---------------------------------------------------------------------------
--  WAT ER BLIJFT
--
--    * de club Cutoff, met logo, kleuren, adres en instellingen
--    * haar medewerkers — jouw toegang dus
--    * haar blindstructuren, uitbetalingsschema's, puntensysteem en seizoen
--    * één avond: die met de naam hieronder. Standaard het Grand Opening
--      Event. Hij blijft leeg — deelnemers, inkopen en inschrijvingen die er
--      tijdens het testen aan hingen, gaan eruit.
--
--      Op naam en niet op "alles wat nog moet komen". Dat laatste stond er
--      eerst, en het spaarde precies het verkeerde: het demoscript zet naast
--      acht afgelopen avonden óók twee gepláánde avonden in de agenda, en
--      `seed_cutoff` liet er ook nog eentje achter. Die drie zagen er in de
--      kalender uit als echte avonden en bleven staan. Dát is wat je nog zag.
--    * elk account in Supabase Auth. Daar raakt dit bestand niet aan.
--
--  WAT ER WEGGAAT
--
--    * elke andere club, volledig — met alles wat eraan hangt
--    * elke andere avond, overal: uitslagen, inkopen, uitschakelingen, deals
--    * elk spelersprofiel, elk lidmaatschap, elke uitnodiging en aanvraag
--
--  Bewust niet op naam van 'aalst' of 'cutoff' geschreven maar op "alles
--  behalve Cutoff". Zit er een club in de database die ik niet ken — een
--  restant van een test, een tweede keer aangemaakt onder een andere naam —
--  dan gaat die ook mee. Dat is precies het geval dat je niet ziet wanneer je
--  per naam opruimt.
--
--  NA DIT SCRIPT: `aalst.pokerleague.be` weghalen in Vercel → Settings →
--  Domains, en het CNAME-record `aalst` bij EasyHost.
-- ===========================================================================

do $$
declare
  c_blijft  text := 'cutoff';
  c_avond   text := 'Grand Opening Event';   -- de enige avond die blijft

  v_club   uuid;
  v_n      int;
  v_houden uuid[];
begin
  select id into v_club from clubs where slug = c_blijft;
  if v_club is null then
    raise exception 'Er is geen club met slug %. Controleer de naam bovenaan.', c_blijft;
  end if;

  -- Precies die ene avond, op naam. Vindt hij er geen, dan stopt het script
  -- vóór er iets weg is — beter een script dat niets doet dan een script dat
  -- de avond wist die je wilde houden.
  select coalesce(array_agg(id), '{}') into v_houden
  from tournaments
  where club_id = v_club and name = c_avond;

  if coalesce(array_length(v_houden, 1), 0) = 0 then
    raise exception 'Geen avond met de naam "%" bij %. Er is niets verwijderd. De avonden die er wél staan, zie je met: select name, scheduled_at, status from tournaments;', c_avond, c_blijft;
  end if;

  raise notice 'Vooraf: % clubs, % avonden, % spelers, % uitslagen.',
    (select count(*) from clubs),
    (select count(*) from tournaments),
    (select count(*) from players),
    (select count(*) from tournament_results);
  raise notice 'Te sparen: % avond(en) met de naam "%".', array_length(v_houden, 1), c_avond;

  -- 1. Alle avonden behalve die ene. Deelnames, inkopen, uitschakelingen,
  --    inschrijvingen, deals en uitslagen gaan via de cascade mee.
  delete from tournaments where not (id = any(v_houden));
  get diagnostics v_n = row_count;
  raise notice '% avonden verwijderd.', v_n;

  -- 2. De avond die blijft, wordt leeggemaakt. Die rijen hangen aan het
  --    tornooi en niet aan de club, dus ze overleven stap 1.
  delete from buyins                  where tournament_id = any(v_houden);
  delete from tournament_registrations where tournament_id = any(v_houden);
  delete from tournament_players      where tournament_id = any(v_houden);
  delete from tournament_tables       where tournament_id = any(v_houden);

  -- 3. Alles wat een mens is, overal.
  delete from player_invites;
  delete from player_signups;
  delete from club_players;
  delete from players;
  get diagnostics v_n = row_count;
  raise notice '% spelersprofielen verwijderd.', v_n;

  -- 4. En elke club behalve deze. Medewerkers, structuren, niveaus,
  --    uitbetalingen, seizoenen, puntensystemen, het auditspoor en de
  --    facturatieregel hangen er met een cascade aan.
  delete from clubs where id <> v_club;
  get diagnostics v_n = row_count;
  raise notice '% andere club(s) verwijderd.', v_n;

  select count(*) into v_n from club_members where club_id = v_club;
  if v_n = 0 then
    raise warning 'LET OP: % heeft geen enkele medewerker meer. Niemand kan de clubomgeving nog openen.', c_blijft;
  else
    raise notice '% heeft nog % medewerker(s) met toegang.', c_blijft, v_n;
  end if;
end $$;

-- ===========================================================================
--  H E T   O O R D E E L
-- ===========================================================================
-- Eén regel. "LEEG" betekent: alleen Cutoff en haar geplande avond staan er
-- nog. Staat er iets anders, dan zegt dat woord wat er nog is.

select
  case
    when (select count(*) from clubs) <> 1              then 'ER STAAT NOG EEN ANDERE CLUB'
    when (select count(*) from tournaments) <> 1        then 'ER STAAN NOG ANDERE AVONDEN'
    when (select count(*) from players) > 0             then 'ER STAAN NOG SPELERSPROFIELEN'
    when (select count(*) from tournament_results) > 0  then 'ER STAAN NOG UITSLAGEN'
    when (select count(*) from buyins) > 0              then 'ER STAAN NOG INKOPEN'
    when (select count(*) from club_players) > 0        then 'ER STAAN NOG LEDEN'
    else 'LEEG'
  end                                              as oordeel,
  (select count(*) from clubs)                     as clubs,
  (select count(*) from tournaments)               as avonden,
  (select count(*) from players)                   as spelers,
  (select count(*) from tournament_results)        as uitslagen,
  (select count(*) from buyins)                    as inkopen,
  (select count(*) from tournament_registrations)  as inschrijvingen;

-- Wat er van Cutoff overblijft. De avond hoort hier te staan, de rest ook.
select t.name as avond, t.scheduled_at, t.status
from tournaments t join clubs c on c.id = t.club_id
where c.slug = 'cutoff'
order by t.scheduled_at;

select
  (select count(*) from club_members m     join clubs c on c.id = m.club_id  where c.slug = 'cutoff') as medewerkers,
  (select count(*) from blind_structures s join clubs c on c.id = s.club_id  where c.slug = 'cutoff') as structuren,
  (select count(*) from payout_templates p join clubs c on c.id = p.club_id  where c.slug = 'cutoff') as uitbetalingen,
  (select count(*) from seasons se         join clubs c on c.id = se.club_id where c.slug = 'cutoff') as seizoenen;

-- Wie er nog toegang heeft tot de clubomgeving. Hier hoor jij in te staan.
select u.email, m.role
from club_members m
join clubs c      on c.id = m.club_id
join auth.users u on u.id = m.user_id
where c.slug = 'cutoff'
order by m.role, u.email;

-- De accounts blijven bestaan; die haalt dit bestand niet weg.
select count(*) as accounts_in_auth from auth.users;
