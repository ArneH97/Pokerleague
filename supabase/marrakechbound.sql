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
-- **De puntentelling.** multiplier 10, exponent 0,75, drie punten voor wie
-- komt opdagen, en dertig euro als ijkpunt voor de inleg. Bij twintig spelers
-- op een avond van dertig euro:
--
--     1e  48   2e  30   3e  23   5e  16   10e  11   laatste  8
--
-- Winnen is zes keer zoveel als laatste worden, en ongeveer evenveel als zes
-- avonden komen opdagen.
--
-- **De inleg weegt mee.** Hetzelfde veld op een avond van vijftig euro:
--
--     1e  61   2e  37   5e  20   laatste  9
--
-- Vijftig euro is dus 29 procent meer waard dan dertig — de wortel van de
-- verhouding. Genoeg om de grote avond te laten tellen, te weinig om de
-- goedkope avond zinloos te maken: wie alleen de dertig-eurotornooien speelt,
-- blijft meedoen voor het pakket.
--
-- Het veld telt mee via √N: een avond met dertig spelers is voor de winnaar
-- een vijfde meer waard dan een avond met twintig — genoeg om drukke avonden
-- te laten tellen, te weinig om één zondag de league te laten beslissen.
--
-- **Beste vijftien resultaten tellen.** Bij ongeveer veertig speelavonden tot
-- eind februari mag je er dus ruim de helft laten vallen. Wie een maand niet
-- kan, ligt daarmee niet uit de race — en wie élke avond komt, bouwt geen
-- voorsprong meer op louter aanwezigheid.
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
      jsonb_build_object('multiplier', 10, 'exponent', 0.75,
                         'buyin_ref', 30, 'buyin_weight', 0.5),
      0,      -- geen bonus per knockout: dat is een aparte competitie
      3,      -- deelname levert iets op, maar weinig
      15,     -- beste vijftien resultaten tellen
      10)     -- minstens tien avonden om mee te dingen
    returning id into v_rc;
    raise notice 'Puntentelling "%" aangemaakt.', c_seizoen;
  else
    update ranking_configs
    set method = 'sqrt_ratio',
        params = jsonb_build_object('multiplier', 10, 'exponent', 0.75,
                                    'buyin_ref', 30, 'buyin_weight', 0.5),
        bonus_per_ko = 0,
        bonus_entry = 3,
        count_best_n = 15,
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

  -- ------------------------------------------- en één klassement in plaats van drie
  -- Tot eind februari is er één competitie. De jaar- en maandstand ernaast
  -- zetten drie lijstjes met drie verschillende namen bovenaan, en dan is de
  -- vraag "wie staat er eerst" niet meer te beantwoorden. Dit is een
  -- instelling en geen verwijdering: zet hem na februari terug af en de
  -- jaarstand is er weer, met alles wat er intussen gespeeld is.
  update clubs set standings_seasons_only = true where id = v_club;
  raise notice 'OK  het klassement toont voortaan alleen seizoenen, ook voor de spelers.';

  raise notice '---';
  raise notice 'Klaar. Het klassementsscherm toont voortaan "%" als eerste seizoen.', c_seizoen;
  raise notice 'Nieuwe tornooien: kies dit seizoen in het aanmaakscherm, of draai dit script opnieuw — dan worden ze alsnog gekoppeld.';
end $$;

-- ===========================================================================
-- Nakijken
-- ===========================================================================

-- Welke avonden hangen er aan de league, en wat weegt elke avond?
--
-- `weging` is de factor waarmee de inleg meetelt: 1,00 bij dertig euro, 1,29
-- bij vijftig. `winnaar_bij_20` is wat een overwinning tegen twintig spelers
-- op die avond oplevert. Kijk die kolom na: staat er bij een avond een
-- verrassend getal, dan staat de inleg in het tornooi anders dan je dacht —
-- de weging kijkt naar het bedrag dat naar de pot gaat, zonder rake.
select
  to_char(t.scheduled_at, 'dd/mm/yyyy') as gepland,
  t.name                                 as tornooi,
  t.status,
  round(t.buyin_cents / 100.0, 2)        as inleg,
  round(t.fee_cents  / 100.0, 2)         as rake,
  round(least(2.0, greatest(0.5,
    sqrt((t.buyin_cents / 100.0) / 30))), 2)                              as weging,
  public.calc_points('sqrt_ratio',
    jsonb_build_object('multiplier', 10, 'exponent', 0.75,
                       'buyin_ref', 30, 'buyin_weight', 0.5),
    1, 20, 0, t.buyin_cents, 0, 3)                                        as winnaar_bij_20,
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
