-- Pokerleague — wat "de inleg" is bij een bountytornooi
--
-- Migratie 0063 liet de inleg meewegen in de league: een avond van vijftig
-- euro telt zwaarder dan een van dertig. Als inleg nam die het bedrag dat
-- naar de prijzenpot gaat, `buyin_cents`.
--
-- Bij een freezeout klopt dat. Bij een bountytornooi niet.
--
-- The Hunt bij Cutoff is twintig euro pot, twintig euro bounty en tien euro
-- rake. Aan de deur betaal je vijftig. In de weging telde alleen die eerste
-- twintig mee, en dus gold de duurste avond van de kalender als een
-- goedkope: factor 0,82 tegenover een gewone avond van dertig. De winnaar
-- kreeg 32 punten waar een €30-freezeout er 39 opleverde.
--
-- **Wat er nu meetelt: pot plus bounty.** Alles wat de spelers kunnen
-- terugwinnen. De bounty is geen bijkomstigheid maar de helft van het spel —
-- je betaalt hem bij het inkopen en je verdient hem terug door koppen te
-- pakken, en wie hem niet pakt is hem kwijt aan wie hem wél pakt. Dat is
-- precies wat inzet betekent.
--
-- **Wat niet meetelt: de rake.** Die gaat naar de club en komt nooit meer op
-- tafel. Zou ze meewegen, dan maakte een club zijn eigen avonden zwaarder
-- door zijn marge te verhogen, en daar hoort een klassement niet op te
-- reageren.
--
-- Voor een freezeout verandert er niets: geen bounty, dus dezelfde inleg als
-- voorheen. Alleen bountytornooien schuiven op, en alleen naar boven.
--
-- Let op: `pokerstars` als methode gebruikt hetzelfde bedrag in zijn
-- logaritme. Ook daar is "wat er op het spel staat" de juiste lezing, en ook
-- daar verandert er niets voor een freezeout.

-- ---------------------------------------------------------------------------
-- 1. Eén plek die zegt wat de inzet is
-- ---------------------------------------------------------------------------
-- Een functie en geen uitdrukking die op drie plaatsen herhaald wordt. Zo'n
-- herhaling loopt uit elkaar zodra iemand er één aanpast, en dan rekent het
-- afsluiten van een avond anders dan het herrekenen ervan.

create or replace function public.stake_cents(
  p_buyin  int,
  p_bounty int,
  p_mode   bounty_mode
)
returns int
language sql
immutable
as $$
  select coalesce(p_buyin, 0)
       + case when p_mode = 'none' then 0 else coalesce(p_bounty, 0) end;
$$;

comment on function public.stake_cents(int, int, bounty_mode) is
  'Wat er per inkoop op het spel staat: de prijzenpot plus de bounty, zonder rake. Dit is het bedrag waarmee de league-weging rekent.';

-- ---------------------------------------------------------------------------
-- 2. Bij het afsluiten van een avond
-- ---------------------------------------------------------------------------
-- Alleen de regel met `t.buyin_cents` verandert. De rest staat hier omdat
-- create or replace de hele functie wil, niet omdat er meer aan veranderd is.

create or replace function public.finalize_tournament(p_tournament_id uuid)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  t             tournaments%rowtype;
  v_entries     int;
  v_rc          ranking_configs%rowtype;
  v_written     int := 0;
  r             record;
  v_prize       int;
begin
  select * into t from tournaments where id = p_tournament_id;
  if not found then
    raise exception 'Tornooi % bestaat niet', p_tournament_id;
  end if;

  if not public.is_service_context()
     and not public.has_club_role(t.club_id, array['owner','admin','floor']::club_role[])
  then
    raise exception 'Geen rechten om dit tornooi af te sluiten'
      using errcode = 'insufficient_privilege';
  end if;

  select count(distinct player_id) into v_entries
  from tournament_players where tournament_id = p_tournament_id;

  if v_entries = 0 then
    return 0;
  end if;

  select rc.* into v_rc
  from seasons s
  join ranking_configs rc on rc.id = s.ranking_config_id
  where s.id = t.season_id;

  delete from tournament_results where tournament_id = p_tournament_id;

  for r in
    select tp.player_id,
           tp.finish_position,
           coalesce((select count(*) from eliminations e
                     where e.eliminated_by_id = tp.id), 0)::int as knockouts,
           coalesce((select sum(b.amount_cents + b.fee_cents + b.bounty_cents)
                     from buyins b
                     where b.tournament_player_id = tp.id and not b.is_void), 0)::int as invested,
           coalesce((select sum(e.bounty_cents) from eliminations e
                     where e.eliminated_by_id = tp.id), 0)::int as bounty_won
    from tournament_players tp
    where tp.tournament_id = p_tournament_id
      and tp.finish_position is not null
  loop
    select coalesce(tp2.amount_cents, 0) into v_prize
    from public.tournament_prizes(p_tournament_id) tp2
    where tp2.place = r.finish_position;

    insert into tournament_results (
      club_id, tournament_id, season_id, player_id, position, entries_total,
      prize_cents, bounty_cents, invested_cents, knockouts, points, finished_at
    ) values (
      t.club_id, p_tournament_id, t.season_id, r.player_id, r.finish_position, v_entries,
      coalesce(v_prize, 0), r.bounty_won, r.invested, r.knockouts,
      public.calc_points(
        coalesce(v_rc.method, 'sqrt_ratio'),
        coalesce(v_rc.params, '{}'::jsonb),
        r.finish_position,
        v_entries,
        r.knockouts,
        public.stake_cents(t.buyin_cents, t.bounty_cents, t.bounty_mode),
        coalesce(v_rc.bonus_per_ko, 0),
        coalesce(v_rc.bonus_entry, 0)
      ),
      now()
    );
    v_written := v_written + 1;
  end loop;

  update tournaments set status = 'finished', ended_at = coalesce(ended_at, now())
  where id = p_tournament_id;

  return v_written;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Bij het herrekenen van een seizoen
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
    select res.id, res.position, res.entries_total, res.knockouts,
           public.stake_cents(t.buyin_cents, t.bounty_cents, t.bounty_mode) as inzet
    from tournament_results res
    join tournaments t on t.id = res.tournament_id
    where res.season_id = p_season_id
  loop
    update tournament_results
    set points = public.calc_points(
          v_rc.method, v_rc.params, r.position, r.entries_total,
          r.knockouts, r.inzet, v_rc.bonus_per_ko, v_rc.bonus_entry)
    where id = r.id;
    v_n := v_n + 1;
  end loop;

  return v_n;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. En bij het verzetten van een avond naar een ander seizoen
-- ---------------------------------------------------------------------------

create or replace function public.tournament_set_season(
  p_tournament_id uuid,
  p_season_id     uuid
)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  t        tournaments%rowtype;
  v_rc     ranking_configs%rowtype;
  v_n      int := 0;
  r        record;
begin
  select * into t from tournaments where id = p_tournament_id;
  if not found then
    raise exception 'Tornooi bestaat niet';
  end if;

  if not public.is_service_context()
     and not public.has_club_role(t.club_id, array['owner','admin']::club_role[]) then
    raise exception 'Geen rechten' using errcode = 'insufficient_privilege';
  end if;

  if p_season_id is not null
     and not exists (select 1 from seasons s
                     where s.id = p_season_id and s.club_id = t.club_id) then
    raise exception 'Dat seizoen hoort niet bij deze club' using errcode = 'check_violation';
  end if;

  if t.season_id is not distinct from p_season_id then
    return 0;
  end if;

  update tournaments set season_id = p_season_id where id = p_tournament_id;
  update tournament_results set season_id = p_season_id where tournament_id = p_tournament_id;

  if p_season_id is null then
    return 0;
  end if;

  select rc.* into v_rc
  from seasons s
  join ranking_configs rc on rc.id = s.ranking_config_id
  where s.id = p_season_id;

  for r in
    select res.id, res.position, res.entries_total, res.knockouts
    from tournament_results res
    where res.tournament_id = p_tournament_id
  loop
    update tournament_results
    set points = public.calc_points(
          coalesce(v_rc.method, 'sqrt_ratio'),
          coalesce(v_rc.params, '{}'::jsonb),
          r.position, r.entries_total, r.knockouts,
          public.stake_cents(t.buyin_cents, t.bounty_cents, t.bounty_mode),
          coalesce(v_rc.bonus_per_ko, 0), coalesce(v_rc.bonus_entry, 0))
    where id = r.id;
    v_n := v_n + 1;
  end loop;

  return v_n;
end;
$$;

comment on function public.calc_points(ranking_method, jsonb, int, int, int, int, numeric, numeric) is
  'Punten voor één uitslag. p_buyin_cents is wat er per inkoop op het spel staat — pot plus bounty, zonder rake; zie stake_cents(). Bij sqrt_ratio bepaalt params.exponent hoe zwaar de plaats weegt en laten params.buyin_ref en params.buyin_weight die inzet meewegen tegenover een ijkpunt in euro.';

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function public.stake_cents(int, int, bounty_mode) to authenticated;
  end if;
end $$;
