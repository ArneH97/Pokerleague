-- Pokerleague — Marrakechbound opzetten bij Cutoff
--
-- Eén league van 1 oktober 2026 tot en met 28 februari 2027, met het
-- Marrakech-pakket voor de winnaar.
--
-- **Hoe een "reset" hier werkt, en waarom dat beter is dan wissen.** Het
-- klassement wordt niet leeggemaakt. In plaats daarvan krijgt deze periode een
-- eigen seizoen, en het klassementsscherm toont standaard het nieuwste
-- seizoen. Vanaf 1 oktober begint iedereen dus op nul, terwijl de avonden
-- daarvoor gewoon blijven bestaan — met hun uitslagen, hun prijzengeld en hun
-- punten. Niemand verliest zijn geschiedenis omdat er een nieuwe competitie
-- begint, en jij kan achteraf nog altijd zien wie er in september won.
--
-- **De puntentelling.** multiplier 10, exponent 0,75, en drie punten voor wie
-- komt opdagen. Bij twintig spelers:
--
--     1e  47,7   2e  29,6   3e  22,6   5e  16,4   10e  11,0   laatste  7,7
--
-- Winnen is zes keer zoveel als laatste worden. Het veld telt mee via √N: een
-- avond met dertig spelers is voor de winnaar een vijfde meer waard dan een
-- avond met twintig — genoeg om drukke avonden te laten tellen, te weinig om
-- één zondag de league te laten beslissen.
--
-- **Beste twintig resultaten tellen.** Bij ongeveer veertig speelavonden tot
-- eind februari mag je er dus de helft laten vallen. Wie een paar weken niet
-- kan, ligt daarmee niet uit de race.
--
-- **Minstens tien avonden om mee te dingen.** Anders staat er iemand bovenaan
-- die twee keer kwam en er één won.
--
-- Twee keer draaien doet niets dubbel: bestaat het seizoen al, dan worden
-- alleen zijn instellingen bijgewerkt.

do $$
declare
  c_slug     text := 'cutoff';
  c_seizoen  text := 'Marrakechbound';
  c_van      date := date '2026-10-01';
  c_tot      date := date '2027-02-28';

  v_club     uuid;
  v_rc       uuid;
  v_season   uuid;
  v_gekoppeld int;
  v_herrekend int;
  r          record;
begin
  select id into v_club from clubs where slug = c_slug;
  if v_club is null then
    raise exception 'Geen club met slug %.', c_slug;
  end if;

  -- ------------------------------------------------------- de puntentelling
  select id into v_rc from ranking_configs
   where club_id = v_club and name = c_seizoen;

  if v_rc is null then
    insert into ranking_configs (
      club_id, name, method, params, bonus_per_ko, bonus_entry,
      count_best_n, min_tournaments)
    values (
      v_club, c_seizoen, 'sqrt_ratio',
      jsonb_build_object('multiplier', 10, 'exponent', 0.75),
      0,      -- geen bonus per knockout: dat is een aparte competitie
      3,      -- deelname levert iets op, maar weinig
      20,     -- beste twintig resultaten tellen
      10)     -- minstens tien avonden om mee te dingen
    returning id into v_rc;
    raise notice 'Puntentelling "%" aangemaakt.', c_seizoen;
  else
    update ranking_configs
    set method = 'sqrt_ratio',
        params = jsonb_build_object('multiplier', 10, 'exponent', 0.75),
        bonus_per_ko = 0,
        bonus_entry = 3,
        count_best_n = 20,
        min_tournaments = 10
    where id = v_rc;
    raise notice 'Puntentelling "%" bestond al en is bijgewerkt.', c_seizoen;
  end if;

  -- ------------------------------------------------------------ het seizoen
  select id into v_season from seasons
   where club_id = v_club and name = c_seizoen;

  if v_season is null then
    insert into seasons (club_id, name, starts_on, ends_on, ranking_config_id, is_active)
    values (v_club, c_seizoen, c_van, c_tot, v_rc, true)
    returning id into v_season;
    raise notice 'Seizoen "%" aangemaakt: % tot en met %.', c_seizoen, c_van, c_tot;
  else
    update seasons
    set starts_on = c_van, ends_on = c_tot, ranking_config_id = v_rc, is_active = true
    where id = v_season;
    raise notice 'Seizoen "%" bestond al en is bijgewerkt.', c_seizoen;
  end if;

  -- Oudere seizoenen op non-actief: er loopt er maar één tegelijk.
  update seasons set is_active = false
   where club_id = v_club and id <> v_season and is_active;

  -- ------------------------------------- alle avonden in de periode erbij
  -- Op geplande datum en niet op afsluitdatum: een avond hoort bij de maand
  -- waarin hij gespeeld is, ook als de floor hem pas de dag erna afsloot.
  update tournaments t
  set season_id = v_season
  where t.club_id = v_club
    and t.season_id is distinct from v_season
    and (t.scheduled_at at time zone coalesce(
          (select timezone from clubs where id = v_club), 'Europe/Brussels'))::date
        between c_van and c_tot;
  get diagnostics v_gekoppeld = row_count;
  raise notice 'OK  % tornooi(en) in de periode hangen nu aan dit seizoen.', v_gekoppeld;

  -- De uitslagen die er al staan, horen mee te verhuizen. Anders telt een
  -- avond van vorige week niet mee in zijn eigen league.
  update tournament_results res
  set season_id = v_season
  from tournaments t
  where t.id = res.tournament_id
    and t.season_id = v_season
    and res.season_id is distinct from v_season;

  -- ------------------------------------------ en opnieuw doorrekenen
  -- Punten worden vastgelegd bij het afsluiten van een avond. Is er in
  -- oktober al gespeeld vóór dit script liep, dan dragen die uitslagen nog de
  -- oude, vlakke punten. Dit zet ze gelijk.
  v_herrekend := public.season_recompute_points(v_season);
  raise notice 'OK  % uitslagregel(s) opnieuw doorgerekend met de nieuwe telling.', v_herrekend;

  raise notice '---';
  raise notice 'Klaar. Het klassementsscherm toont voortaan "%" als eerste seizoen.', c_seizoen;
  raise notice 'Nieuwe tornooien: kies dit seizoen in het aanmaakscherm, of draai dit script opnieuw — dan worden ze alsnog gekoppeld.';
end $$;

-- ===========================================================================
-- Nakijken
-- ===========================================================================

-- Welke avonden hangen er aan de league?
select
  to_char(t.scheduled_at, 'dd/mm/yyyy') as gepland,
  t.name                                 as tornooi,
  t.status,
  (select count(*) from tournament_results r where r.tournament_id = t.id) as uitslagregels
from tournaments t
join seasons s on s.id = t.season_id
join clubs   c on c.id = t.club_id
where c.slug = 'cutoff' and s.name = 'Marrakechbound'
order by t.scheduled_at;

-- En de stand zoals het scherm hem toont. `gekwalificeerd` zegt of iemand aan
-- de drempel van tien avonden voldoet; wie daar nog onder zit staat er wel in
-- maar dingt nog niet mee naar het pakket.
select
  row_number() over (order by st.points desc, st.best_position asc) as plaats,
  st.display_name                        as speler,
  st.points                              as punten,
  st.tournaments                         as avonden,
  st.best_position                       as beste,
  st.cashes,
  round(st.total_prize / 100.0, 2)       as prijzengeld
from clubs c
join seasons s on s.club_id = c.id and s.name = 'Marrakechbound'
cross join lateral public.season_standings(s.id) st
where c.slug = 'cutoff'
order by plaats;
