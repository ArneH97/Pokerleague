-- Pokerleague — laten zien hoe iemand aan zijn punten komt
--
-- Een klassement met een prijs aan het eind roept één vraag op, en die wordt
-- elke speelavond gesteld: waarom heeft hij er meer dan ik. Zolang het
-- antwoord "dat rekent het systeem uit" is, is het klassement iets dat
-- gebeurt in plaats van iets waar je voor speelt.
--
-- Dus: klik op een naam en je ziet zijn avonden, van best naar slechtst, met
-- per avond wat die opleverde en waarom. En een streep onder de beste
-- vijftien, want daaronder telt het niet meer mee.
--
-- Twee functies, allebei publiek leesbaar zoals de rest van `club_public_*`:
-- de opbouw per speler, en de regels van het seizoen zodat het scherm de
-- formule kan uitleggen in plaats van hem te herhalen in code. Dat laatste is
-- het punt: staat de formule ook in de browser, dan drijft ze weg van wat de
-- database doet, en dan legt het scherm iets uit dat niet meer waar is.
--
-- Geen prijzengeld in beide, net als in de rest van de publieke kant. Wat
-- iemand won is een zaak tussen hem en de club.

-- ---------------------------------------------------------------------------
-- 1. De stand krijgt er een speler-id bij
-- ---------------------------------------------------------------------------
-- Zonder id kan je niet doorklikken, en doorklikken op een naam breekt zodra
-- er twee Jans zijn. Het id geeft niets prijs wat de stand zelf niet al
-- toont: dezelfde speler, dezelfde publieke naam, dezelfde cijfers.

drop function if exists public.club_public_season_standings(text, uuid);

create or replace function public.club_public_season_standings(
  p_club_slug text,
  p_season_id uuid default null
)
returns table (
  player_id     uuid,
  player_name   text,
  tournaments   int,
  counted       int,
  points        numeric,
  best_position int,
  cashes        int,
  knockouts     int,
  qualified     boolean,
  min_required  int
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_season uuid;
  v_best_n int;
  v_min    int;
begin
  v_season := p_season_id;
  if v_season is null then
    select s.id into v_season
    from public.club_public_seasons(p_club_slug) s
    limit 1;
  end if;
  if v_season is null then
    return;
  end if;

  select rc.count_best_n, rc.min_tournaments
    into v_best_n, v_min
  from seasons s
  join clubs c on c.id = s.club_id
  left join ranking_configs rc on rc.id = s.ranking_config_id
  where s.id = v_season and c.slug = p_club_slug and c.is_active;

  if not found then
    return;
  end if;

  return query
  with zichtbaar as (
    select r.*,
           public.public_name(p.display_name, p.username, p.id,
                              p.public_listing, p.public_profile, c.public_names) as naam,
           row_number() over (partition by r.player_id order by r.points desc) as rn
    from tournament_results r
    join tournaments t on t.id = r.tournament_id
    join clubs c       on c.id = t.club_id
    join players p     on p.id = r.player_id
    where r.season_id = v_season
      and c.slug = p_club_slug
      and c.is_active
      and t.player_visibility = 'public'
      and t.status = 'finished'
  ),
  agg as (
    select z.player_id,
           min(z.naam)                                                     as naam,
           count(*)::int                                                   as tournaments,
           count(*) filter (where v_best_n is null or z.rn <= v_best_n)::int as counted,
           sum(z.points) filter (where v_best_n is null or z.rn <= v_best_n) as points,
           min(z.position)::int                                            as best_position,
           count(*) filter (where z.prize_cents > 0)::int                   as cashes,
           sum(z.knockouts)::int                                           as knockouts
    from zichtbaar z
    group by z.player_id
  )
  select a.player_id, a.naam, a.tournaments, a.counted,
         round(coalesce(a.points, 0), 0),
         a.best_position, a.cashes, a.knockouts,
         a.tournaments >= coalesce(v_min, 0),
         coalesce(v_min, 0)
  from agg a
  order by 5 desc, a.best_position asc;
end;
$$;

comment on function public.club_public_season_standings(text, uuid) is
  'De stand van een seizoen voor de zaal: dezelfde beste-N-regel en drempel als aan de clubkant, met de naamregeling van de club en zonder prijzengeld. Zonder seizoen meegegeven het nieuwste met publieke uitslagen.';

-- ---------------------------------------------------------------------------
-- 2. De avonden van één speler, van best naar slechtst
-- ---------------------------------------------------------------------------
-- `counted` zegt of die avond binnen de beste N valt. De volgorde is die van
-- de telling zelf — op punten, hoogste eerst — zodat de streep onder de
-- vijftiende regel precies de streep is die de database trekt.

create or replace function public.club_public_player_season(
  p_club_slug text,
  p_player_id uuid,
  p_season_id uuid default null
)
returns table (
  player_name   text,
  tournament_id uuid,
  tournament    text,
  played_on     timestamptz,
  /** `place` en niet `position`: dat laatste is een gereserveerd woord. */
  place         int,
  entries       int,
  knockouts     int,
  /** Wat er die avond per inkoop op het spel stond: pot plus bounty. */
  stake_cents   int,
  points        numeric,
  /** Valt deze avond binnen de beste N van dit seizoen? */
  counted       boolean
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_season uuid;
  v_best_n int;
begin
  v_season := p_season_id;
  if v_season is null then
    select s.id into v_season
    from public.club_public_seasons(p_club_slug) s
    limit 1;
  end if;
  if v_season is null then
    return;
  end if;

  select rc.count_best_n into v_best_n
  from seasons s
  join clubs c on c.id = s.club_id
  left join ranking_configs rc on rc.id = s.ranking_config_id
  where s.id = v_season and c.slug = p_club_slug and c.is_active;

  if not found then
    return;
  end if;

  return query
  with zichtbaar as (
    select r.id, r.tournament_id, t.name as tornooi, r.finished_at,
           r.position, r.entries_total, r.knockouts, r.points,
           public.stake_cents(t.buyin_cents, t.bounty_cents, t.bounty_mode) as inzet,
           public.public_name(p.display_name, p.username, p.id,
                              p.public_listing, p.public_profile, c.public_names) as naam,
           row_number() over (order by r.points desc, r.finished_at desc) as rn
    from tournament_results r
    join tournaments t on t.id = r.tournament_id
    join clubs c       on c.id = t.club_id
    join players p     on p.id = r.player_id
    where r.season_id = v_season
      and r.player_id = p_player_id
      and c.slug = p_club_slug
      and c.is_active
      and t.player_visibility = 'public'
      and t.status = 'finished'
  )
  select z.naam, z.tournament_id, z.tornooi, z.finished_at,
         z.position, z.entries_total, z.knockouts, z.inzet, z.points,
         (v_best_n is null or z.rn <= v_best_n)
  from zichtbaar z
  order by z.rn;
end;
$$;

comment on function public.club_public_player_season(text, uuid, uuid) is
  'De avonden van één speler in een seizoen, van best naar slechtst, met per avond het veld, de inzet en de punten. counted zegt of die avond binnen de beste N valt. Zonder prijzengeld.';

-- ---------------------------------------------------------------------------
-- 3. De regels van het seizoen, zodat het scherm ze kan uitleggen
-- ---------------------------------------------------------------------------
-- Alleen de puntentelling en de twee drempels. Niet de hele ranking_config:
-- daar hangt een club_id aan en een naam die de club voor zichzelf koos.

create or replace function public.club_public_season_rules(
  p_club_slug text,
  p_season_id uuid default null
)
returns table (
  season_id       uuid,
  season_name     text,
  starts_on       date,
  ends_on         date,
  method          text,
  multiplier      numeric,
  exponent        numeric,
  buyin_ref       numeric,
  buyin_weight    numeric,
  bonus_entry     numeric,
  bonus_per_ko    numeric,
  count_best_n    int,
  min_tournaments int
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_season uuid;
begin
  v_season := p_season_id;
  if v_season is null then
    select s.id into v_season
    from public.club_public_seasons(p_club_slug) s
    limit 1;
  end if;
  if v_season is null then
    return;
  end if;

  return query
  select s.id, s.name, s.starts_on, s.ends_on,
         rc.method::text,
         coalesce((rc.params->>'multiplier')::numeric, 10),
         -- Dezelfde grenzen als calc_points, zodat het scherm niet iets
         -- uitlegt wat de database vervolgens anders doet.
         least(1.5, greatest(0.5, coalesce((rc.params->>'exponent')::numeric, 0.5))),
         (rc.params->>'buyin_ref')::numeric,
         least(1.5, greatest(0, coalesce((rc.params->>'buyin_weight')::numeric, 0.5))),
         coalesce(rc.bonus_entry, 0),
         coalesce(rc.bonus_per_ko, 0),
         rc.count_best_n,
         coalesce(rc.min_tournaments, 0)
  from seasons s
  join clubs c on c.id = s.club_id
  left join ranking_configs rc on rc.id = s.ranking_config_id
  where s.id = v_season and c.slug = p_club_slug and c.is_active;
end;
$$;

comment on function public.club_public_season_rules(text, uuid) is
  'De puntentelling van een seizoen in leesbare vorm, zodat een scherm kan uitleggen hoe de punten tot stand komen zonder de formule in code te herhalen.';

-- ---------------------------------------------------------------------------
-- 4. Rechten
-- ---------------------------------------------------------------------------

do $$
declare
  r text;
begin
  foreach r in array array['anon', 'authenticated'] loop
    if exists (select 1 from pg_roles where rolname = r) then
      execute format('grant execute on function public.club_public_season_standings(text,uuid) to %I', r);
      execute format('grant execute on function public.club_public_player_season(text,uuid,uuid) to %I', r);
      execute format('grant execute on function public.club_public_season_rules(text,uuid) to %I', r);
    end if;
  end loop;
end $$;
