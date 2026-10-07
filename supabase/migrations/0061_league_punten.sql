-- Pokerleague — een puntentelling waarin winnen écht telt
--
-- **Waarom de bestaande telling niet volstaat voor een league met een prijs.**
-- `sqrt_ratio` geeft `multiplier × √N / √plaats`. Bij twintig spelers levert dat
-- de winnaar 44,7 punten en de allerlaatste 10 — een verhouding van nog geen
-- vier op één. Over veertig avonden wint dan niet de beste speler maar de
-- trouwste bezoeker. Dat is prima voor een huisklassement en onbruikbaar als er
-- aan het eind een reis naar Marrakech aan hangt.
--
-- **Wat er verandert.** De macht waarmee de plaats meetelt wordt instelbaar:
--
--     punten = multiplier × √N ÷ plaats^exponent   (+ bonussen)
--
-- Zonder `exponent` in de parameters blijft het exact ½, en dus exact wat het
-- was. Elke bestaande clubinstelling rekent door alsof er niets gebeurd is;
-- dat is met opzet, want dit raakt de geschiedenis van elke club die het
-- platform ooit gebruikt.
--
-- Bij exponent 0,75 en twintig spelers: winnaar 44,7 · tweede 26,6 · vijfde
-- 13,4 · laatste 4,7. Winnen is dan zes keer zoveel als laatste worden, en een
-- overwinning staat ongeveer gelijk aan zes avonden komen opdagen.
--
-- Het veld blijft met √N meetellen: een avond met dertig spelers is voor de
-- winnaar een vijfde meer waard dan een avond met twintig. Niet lineair, want
-- dan zou één drukke zondag de hele league kunnen beslissen.
--
-- ---------------------------------------------------------------------------
-- En het stuk dat niemand vraagt tot het misgaat
-- ---------------------------------------------------------------------------
-- Punten worden berekend op het moment dat een avond wordt afgesloten en
-- daarna opgeslagen in `tournament_results`. Dat is bewust: een uitslag die je
-- bij elk bezoek opnieuw uitrekent, verandert zodra iemand de instellingen
-- aanpast, en dan klopt de avond van vorige maand ineens niet meer met wat er
-- die avond is uitbetaald.
--
-- Maar het betekent ook dat een nieuwe puntentelling alleen geldt voor wat
-- hierna gespeeld wordt. Wie halverwege oktober een league begint die op 1
-- oktober had moeten starten, zou de eerste avonden met de oude punten in zijn
-- klassement houden. Vandaar `season_recompute_points`: één keer draaien, en
-- alle avonden van dat seizoen rekenen opnieuw volgens de instelling die er nu
-- aan hangt.

-- ---------------------------------------------------------------------------
-- 1. De plaats mag zwaarder wegen
-- ---------------------------------------------------------------------------

create or replace function public.calc_points(
  p_method      ranking_method,
  p_params      jsonb,
  p_position    int,
  p_entries     int,
  p_knockouts   int default 0,
  p_buyin_cents int default 0,
  p_bonus_ko    numeric default 0,
  p_bonus_entry numeric default 0
)
returns numeric
language plpgsql
immutable
as $$
declare
  v_pts   numeric := 0;
  v_tbl   jsonb;
  v_mult  numeric;
  v_base  numeric;
  v_dec   numeric;
  v_floor numeric;
  v_exp   numeric;
begin
  if p_position is null or p_position < 1 or p_entries is null or p_entries < 1 then
    return 0;
  end if;

  case p_method
    when 'fixed_table' then
      v_tbl := coalesce(p_params->'table', '[]'::jsonb);
      if p_position <= jsonb_array_length(v_tbl) then
        v_pts := (v_tbl->>(p_position - 1))::numeric;
      else
        v_pts := coalesce((p_params->>'tail')::numeric, 0);
      end if;

    when 'linear' then
      v_base  := coalesce((p_params->>'base')::numeric, 100);
      v_dec   := coalesce((p_params->>'decrement')::numeric, 5);
      v_floor := coalesce((p_params->>'floor')::numeric, 1);
      v_pts   := greatest(v_base - (p_position - 1) * v_dec, v_floor);

    when 'sqrt_ratio' then
      v_mult := coalesce((p_params->>'multiplier')::numeric, 10);
      -- Zonder exponent is dit letterlijk de oude formule. Tussen 0,5 en 1,5
      -- geklemd: lager dan een halve maakt de plaats bijna betekenisloos,
      -- hoger dan anderhalf krijgt alleen de winnaar nog punten en heeft de
      -- rest van de tafel niets meer te spelen.
      v_exp  := least(1.5, greatest(0.5, coalesce((p_params->>'exponent')::numeric, 0.5)));
      v_pts  := v_mult * sqrt(p_entries::numeric) / power(p_position::numeric, v_exp);

    when 'pokerstars' then
      v_mult := coalesce((p_params->>'multiplier')::numeric, 10);
      v_pts  := v_mult
                * (sqrt(p_entries::numeric) / sqrt(p_position::numeric))
                * log(10, 1 + (p_buyin_cents::numeric / 100.0));
  end case;

  v_pts := v_pts + (coalesce(p_knockouts, 0) * coalesce(p_bonus_ko, 0)) + coalesce(p_bonus_entry, 0);
  -- Hele getallen, zoals migratie 0022 vastlegde: een klassement met
  -- komma's leest als een berekening en telt niet meer op.
  return round(greatest(v_pts, 0), 0);
end;
$$;

comment on function public.calc_points(ranking_method, jsonb, int, int, int, int, numeric, numeric) is
  'Punten voor één uitslag. Bij sqrt_ratio bepaalt params.exponent hoe zwaar de plaats weegt: 0,5 is de oude, vlakke telling, 0,75 laat winnen zes keer zwaarder wegen dan laatste worden. Ontbreekt de exponent, dan verandert er niets.';

-- ---------------------------------------------------------------------------
-- 2. Een seizoen opnieuw doorrekenen
-- ---------------------------------------------------------------------------

create or replace function public.season_recompute_points(p_season_id uuid)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  s        seasons%rowtype;
  v_rc     ranking_configs%rowtype;
  v_n      int := 0;
  r        record;
begin
  select * into s from seasons where id = p_season_id;
  if not found then
    raise exception 'Seizoen bestaat niet';
  end if;

  if not public.is_service_context()
     and not public.has_club_role(s.club_id, array['owner','admin']::club_role[]) then
    raise exception 'Geen rechten' using errcode = 'insufficient_privilege';
  end if;

  if s.ranking_config_id is null then
    raise exception 'Aan dit seizoen hangt geen puntentelling' using errcode = 'check_violation';
  end if;
  select * into v_rc from ranking_configs where id = s.ranking_config_id;

  for r in
    select res.id, res.position, res.entries_total, res.knockouts, t.buyin_cents
    from tournament_results res
    join tournaments t on t.id = res.tournament_id
    where res.season_id = p_season_id
  loop
    update tournament_results
    set points = public.calc_points(
          v_rc.method, v_rc.params, r.position, r.entries_total,
          r.knockouts, r.buyin_cents, v_rc.bonus_per_ko, v_rc.bonus_entry)
    where id = r.id;
    v_n := v_n + 1;
  end loop;

  return v_n;
end;
$$;

comment on function public.season_recompute_points(uuid) is
  'Rekent de punten van alle uitslagen in een seizoen opnieuw uit volgens de puntentelling die nu aan dat seizoen hangt. Voor wie een league begint nadat er al gespeeld is, of de telling onderweg bijstelt.';

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function public.season_recompute_points(uuid) to authenticated;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 3. De drempel bepaalt de prijs, niet of je in het klassement staat
-- ---------------------------------------------------------------------------
-- `min_tournaments` filterde spelers volledig uit de stand. Op een huisranking
-- zonder prijs valt dat niet op. Bij een league die in oktober begint met een
-- drempel van tien avonden wél: dan is het klassement leeg tot eind december,
-- precies in de maanden dat de race zichtbaar moet zijn om mensen te laten
-- komen. Een lege tabel motiveert niemand.
--
-- Dus iedereen staat erin, en er komt een vlag bij die zegt of iemand aan de
-- drempel voldoet. Wie er nog onder zit, ziet zijn punten meetellen én dat hij
-- nog een paar avonden te gaan heeft. Dat is informatie die je naar de club
-- trekt in plaats van je eruit te houden.

drop function if exists public.season_standings(uuid);

create or replace function public.season_standings(p_season_id uuid)
returns table (
  player_id      uuid,
  display_name   text,
  tournaments    int,
  counted        int,
  points         numeric,
  best_position  int,
  cashes         int,
  total_prize    int,
  knockouts      int,
  /** Voldoet deze speler aan het minimum aantal avonden van dit seizoen? */
  qualified      boolean,
  /** Het minimum zelf, zodat het scherm kan zeggen hoeveel er nog te gaan zijn. */
  min_required   int
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_club   uuid;
  v_best_n int;
  v_min    int;
begin
  select s.club_id, rc.count_best_n, rc.min_tournaments
    into v_club, v_best_n, v_min
  from seasons s
  left join ranking_configs rc on rc.id = s.ranking_config_id
  where s.id = p_season_id;

  if v_club is null then
    return;
  end if;

  if not public.is_service_context()
     and not public.is_club_member(v_club)
     and not public.is_club_player(v_club)
  then
    raise exception 'Geen rechten op het klassement van deze club'
      using errcode = 'insufficient_privilege';
  end if;

  return query
  with ranked as (
    select r.*,
           row_number() over (partition by r.player_id order by r.points desc) as rn
    from tournament_results r
    where r.season_id = p_season_id
  ),
  agg as (
    select ranked.player_id,
           count(*)::int                                                as tournaments,
           count(*) filter (where v_best_n is null or rn <= v_best_n)::int as counted,
           sum(ranked.points) filter (where v_best_n is null or rn <= v_best_n) as points,
           min(ranked.position)::int                                    as best_position,
           count(*) filter (where ranked.prize_cents > 0)::int          as cashes,
           sum(ranked.prize_cents + ranked.bounty_cents)::int           as total_prize,
           sum(ranked.knockouts)::int                                   as knockouts
    from ranked
    group by ranked.player_id
  )
  select a.player_id, p.display_name, a.tournaments, a.counted,
         round(coalesce(a.points, 0), 2), a.best_position, a.cashes,
         a.total_prize, a.knockouts,
         a.tournaments >= coalesce(v_min, 0),
         coalesce(v_min, 0)
  from agg a
  join players p on p.id = a.player_id
  order by 5 desc, a.best_position asc;
end;
$$;

comment on function public.season_standings(uuid) is
  'De stand van een seizoen. Iedereen staat erin; qualified zegt of iemand het minimum aantal avonden gehaald heeft. Dat minimum bepaalt wie er voor de prijs in aanmerking komt, niet wie er zichtbaar is.';

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function public.season_standings(uuid) to authenticated;
  end if;
end $$;
