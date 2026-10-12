-- Pokerleague — samen eerste worden
--
-- Drie spelers dealen voor hetzelfde bedrag en staan op. Wie van hen is er
-- dan eerste? Niemand. Ze zijn samen eerste, en dat is geen formaliteit: in
-- een league met een prijs aan het eind bepaalt die ene plaats het verschil
-- tussen 48 en 23 punten.
--
-- Tot nu kende het systeem dat niet. Na een deal werden de plaatsen alsnog op
-- fichestapel verdeeld, en kreeg wie toevallig de grootste stapel had de
-- volle winnaarspunten voor een overwinning die niemand gespeeld heeft.
--
-- ---------------------------------------------------------------------------
-- Hoe de punten verdeeld worden
-- ---------------------------------------------------------------------------
-- Wie samen eerste wordt met drie man, bezet samen de plaatsen 1, 2 en 3. De
-- punten van die drie plaatsen worden bij elkaar opgeteld en gelijk verdeeld:
--
--     (48 + 30 + 23) ÷ 3 = 34 punten elk
--
-- Daarmee geeft de avond exact evenveel punten weg als een avond zonder deal.
-- Dat is het hele punt. Zou iedereen de punten van de eerste plaats krijgen,
-- dan levert een deal met vijf man meer op dan een overwinning, en dan wordt
-- dealen een manier om het klassement te bespelen in plaats van een manier om
-- het geld te verdelen.
--
-- Het gemiddelde wordt genomen over de punten zoals ze gepubliceerd staan —
-- 48, 30 en 23, de hele getallen uit de tabel — en niet over de ruwe
-- tussenwaarden. Zo kan het klassementsscherm de som letterlijk tonen, en
-- klopt wat er staat met wat je zelf narekent.
--
-- ---------------------------------------------------------------------------
-- Hoe een gedeelde plaats ontstaat
-- ---------------------------------------------------------------------------
-- `tie_group` markeert welke spelers samen eindigen. Bij het afsluiten krijgen
-- ze dezelfde eindplaats, en de plaatsen die ze samen opgebruiken worden
-- overgeslagen: na drie keer "samen eerste" volgt plaats vier.
--
-- Een merkteken op de speler en niet simpelweg twee keer hetzelfde cijfer in
-- `finish_position`: de plaatsen worden tijdens een avond meermaals opnieuw
-- berekend — bij een terugdraaiing, bij een re-entry — en een afspraak die
-- zo'n herberekening niet overleeft, is geen afspraak.
--
-- `tournament_results.shared_with` onthoudt met hoeveel de plaats gedeeld
-- werd, zodat een seizoen dat later opnieuw doorgerekend wordt dezelfde
-- verdeling oplevert.

-- ---------------------------------------------------------------------------
-- 1. Punten voor een gedeelde plaats
-- ---------------------------------------------------------------------------

create or replace function public.calc_points_shared(
  p_method      ranking_method,
  p_params      jsonb,
  p_from        int,
  p_to          int,
  p_entries     int,
  p_knockouts   int default 0,
  p_buyin_cents int default 0,
  p_bonus_ko    numeric default 0,
  p_bonus_entry numeric default 0
)
returns numeric
language sql
immutable
as $$
  select round(avg(public.calc_points(
           p_method, p_params, plaats, p_entries,
           p_knockouts, p_buyin_cents, p_bonus_ko, p_bonus_entry)), 0)
  from generate_series(greatest(p_from, 1), greatest(p_to, p_from, 1)) as plaats;
$$;

comment on function public.calc_points_shared(ranking_method, jsonb, int, int, int, int, int, numeric, numeric) is
  'De punten voor een gedeelde eindplaats: het gemiddelde van de punten voor de plaatsen die samen bezet worden. Met p_from = p_to is dit gewoon calc_points.';

-- ---------------------------------------------------------------------------
-- 2. Wie samen eindigt
-- ---------------------------------------------------------------------------

alter table tournament_players
  add column if not exists tie_group int;

comment on column tournament_players.tie_group is
  'Spelers met hetzelfde nummer binnen één tornooi eindigen ex aequo: zij krijgen dezelfde eindplaats en delen de punten van de plaatsen die ze samen bezetten.';

alter table tournament_results
  add column if not exists shared_with int not null default 1;

comment on column tournament_results.shared_with is
  'Met hoeveel spelers deze eindplaats gedeeld werd. 1 is een gewone plaats; 3 betekent dat deze speler samen met twee anderen drie plaatsen bezette.';

create or replace function public.floor_set_tie(p_tournament_player_ids uuid[])
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_club  uuid;
  v_tour  uuid;
  v_groep int;
  v_n     int;
begin
  if p_tournament_player_ids is null or array_length(p_tournament_player_ids, 1) < 2 then
    raise exception 'Een gedeelde plaats heeft minstens twee spelers nodig'
      using errcode = 'check_violation';
  end if;

  -- min() bestaat niet voor uuid; vandaar de omweg via een geordende
  -- aggregatie. Het gaat er alleen om dát ze in hetzelfde tornooi zitten.
  select count(distinct tp.tournament_id),
         (array_agg(tp.tournament_id))[1],
         (array_agg(tp.club_id))[1]
    into v_n, v_tour, v_club
  from tournament_players tp where tp.id = any(p_tournament_player_ids);

  if v_tour is null then
    raise exception 'Die deelnemers bestaan niet';
  end if;
  if v_n > 1 then
    raise exception 'Die spelers zitten niet in hetzelfde tornooi' using errcode = 'check_violation';
  end if;

  if not public.is_service_context()
     and not public.has_club_role(v_club, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten' using errcode = 'insufficient_privilege';
  end if;

  select coalesce(max(tie_group), 0) + 1 into v_groep
  from tournament_players where tournament_id = v_tour;

  update tournament_players
  set tie_group = v_groep
  where id = any(p_tournament_player_ids);
  get diagnostics v_n = row_count;

  perform public.renumber_finish_positions(v_tour);
  return v_n;
end;
$$;

comment on function public.floor_set_tie(uuid[]) is
  'Markeert spelers als ex aequo geëindigd: ze krijgen dezelfde eindplaats en delen de punten van de plaatsen die ze samen bezetten.';

create or replace function public.floor_clear_tie(p_tournament_player_ids uuid[])
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_club uuid;
  v_tour uuid;
  v_n    int;
begin
  select (array_agg(tp.club_id))[1], (array_agg(tp.tournament_id))[1]
    into v_club, v_tour
  from tournament_players tp where tp.id = any(p_tournament_player_ids);
  if v_tour is null then
    return 0;
  end if;

  if not public.is_service_context()
     and not public.has_club_role(v_club, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten' using errcode = 'insufficient_privilege';
  end if;

  update tournament_players set tie_group = null where id = any(p_tournament_player_ids);
  get diagnostics v_n = row_count;

  perform public.renumber_finish_positions(v_tour);
  return v_n;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. De eindplaatsen, met gedeelde plaatsen erin
-- ---------------------------------------------------------------------------
-- Herberekent de plaatsen van wie al afviel. Spelers met hetzelfde tie_group
-- krijgen de beste plaats die ze samen halen; de plaatsen eronder worden
-- opgebruikt en overgeslagen.

create or replace function public.renumber_finish_positions(p_tournament_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_totaal int;
begin
  select count(*) into v_totaal
  from tournament_players
  where tournament_id = p_tournament_id;

  with volgorde as (
    select tp.id as v_id,
           tp.tie_group,
           row_number() over (
             order by tp.eliminated_at asc nulls last,
                      tp.finish_position desc nulls last,
                      tp.id asc
           ) as v_beurt
    from tournament_players tp
    where tp.tournament_id = p_tournament_id
      and tp.status = 'eliminated'
  ),
  met_plaats as (
    -- De beurt telt van achteren: wie als eerste afviel, wordt laatste. Bij
    -- een gedeelde plaats telt de hoogste beurt van de groep, want dat is de
    -- beste plaats die ze samen bereikten.
    select v.v_id,
           v_totaal - case
             when v.tie_group is null then v.v_beurt
             else max(v.v_beurt) over (partition by v.tie_group)
           end + 1 as v_plaats
    from volgorde v
  )
  update tournament_players tp
  set finish_position = m.v_plaats
  from met_plaats m
  where tp.id = m.v_id
    and tp.finish_position is distinct from m.v_plaats;
end;
$$;

comment on function public.renumber_finish_positions(uuid) is
  'Herberekent de eindplaatsen van alle uitgeschakelde spelers uit de volgorde waarin ze afvielen, met gedeelde plaatsen voor wie ex aequo eindigde. Zelfherstellend: een tornooi met een gat staat er na één aanroep weer goed op.';

-- ---------------------------------------------------------------------------
-- 4. Afsluiten: wie nog zit krijgt zijn plaats, gedeeld waar dat hoort
-- ---------------------------------------------------------------------------

create or replace function public.floor_finish_tournament(p_tournament_id uuid)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  t tournaments%rowtype;
begin
  select * into t from tournaments where id = p_tournament_id;
  if not found then
    raise exception 'Tornooi bestaat niet';
  end if;

  if not public.is_service_context()
     and not public.has_club_role(t.club_id, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten' using errcode = 'insufficient_privilege';
  end if;

  -- Wie nog zit, bezet de plaatsen 1 tot en met N: de grootste stapel vooraan.
  -- Spelers die samen eindigen krijgen allemaal de beste plaats van hun
  -- groep, en de plaatsen daaronder worden overgeslagen.
  with volgorde as (
    select tp.id, tp.tie_group,
           row_number() over (
             order by coalesce(tp.chip_count, 0) desc, tp.registered_at asc, tp.id asc
           ) as rij
    from tournament_players tp
    where tp.tournament_id = p_tournament_id
      and tp.status in ('active', 'registered')
  ),
  met_plaats as (
    select v.id,
           case when v.tie_group is null then v.rij
                else min(v.rij) over (partition by v.tie_group)
           end as plaats
    from volgorde v
  )
  update tournament_players tp
  set status = 'eliminated',
      finish_position = m.plaats,
      eliminated_at = coalesce(tp.eliminated_at, now())
  from met_plaats m
  where tp.id = m.id;

  update tournaments set ended_at = coalesce(ended_at, now()) where id = p_tournament_id;

  return public.finalize_tournament(p_tournament_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. De uitslag wegschrijven, met gedeelde punten
-- ---------------------------------------------------------------------------

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
           -- Met hoeveel deze plaats gedeeld wordt. Eén betekent: gewoon.
           (select count(*) from tournament_players x
            where x.tournament_id = p_tournament_id
              and x.finish_position = tp.finish_position)::int as gedeeld,
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
    -- Het prijzengeld van de gedeelde plaatsen gaat ook samen op en wordt
    -- gelijk verdeeld. Bij een deal wordt dit meteen daarna overschreven met
    -- de bedragen waar de tafel het over eens werd; zonder deal is dit het
    -- enige eerlijke antwoord op "wie van ons krijgt de eerste prijs".
    select coalesce(round(avg(tp2.amount_cents)), 0) into v_prize
    from public.tournament_prizes(p_tournament_id) tp2
    where tp2.place between r.finish_position and r.finish_position + r.gedeeld - 1;

    insert into tournament_results (
      club_id, tournament_id, season_id, player_id, position, entries_total,
      prize_cents, bounty_cents, invested_cents, knockouts, points, shared_with, finished_at
    ) values (
      t.club_id, p_tournament_id, t.season_id, r.player_id, r.finish_position, v_entries,
      coalesce(v_prize, 0), r.bounty_won, r.invested, r.knockouts,
      public.calc_points_shared(
        coalesce(v_rc.method, 'sqrt_ratio'),
        coalesce(v_rc.params, '{}'::jsonb),
        r.finish_position,
        r.finish_position + r.gedeeld - 1,
        v_entries,
        r.knockouts,
        public.stake_cents(t.buyin_cents, t.bounty_cents, t.bounty_mode),
        coalesce(v_rc.bonus_per_ko, 0),
        coalesce(v_rc.bonus_entry, 0)
      ),
      r.gedeeld,
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
-- 6. Herrekenen houdt de gedeelde plaatsen aan
-- ---------------------------------------------------------------------------

create or replace function public.season_recompute_points(p_season_id uuid)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  s    seasons%rowtype;
  v_rc ranking_configs%rowtype;
  v_n  int := 0;
  r    record;
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
           greatest(coalesce(res.shared_with, 1), 1) as gedeeld,
           public.stake_cents(t.buyin_cents, t.bounty_cents, t.bounty_mode) as inzet
    from tournament_results res
    join tournaments t on t.id = res.tournament_id
    where res.season_id = p_season_id
  loop
    update tournament_results
    set points = public.calc_points_shared(
          v_rc.method, v_rc.params,
          r.position, r.position + r.gedeeld - 1,
          r.entries_total, r.knockouts, r.inzet,
          v_rc.bonus_per_ko, v_rc.bonus_entry)
    where id = r.id;
    v_n := v_n + 1;
  end loop;

  return v_n;
end;
$$;

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
  t    tournaments%rowtype;
  v_rc ranking_configs%rowtype;
  v_n  int := 0;
  r    record;
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
    select res.id, res.position, res.entries_total, res.knockouts,
           greatest(coalesce(res.shared_with, 1), 1) as gedeeld
    from tournament_results res
    where res.tournament_id = p_tournament_id
  loop
    update tournament_results
    set points = public.calc_points_shared(
          coalesce(v_rc.method, 'sqrt_ratio'),
          coalesce(v_rc.params, '{}'::jsonb),
          r.position, r.position + r.gedeeld - 1,
          r.entries_total, r.knockouts,
          public.stake_cents(t.buyin_cents, t.bounty_cents, t.bounty_mode),
          coalesce(v_rc.bonus_per_ko, 0), coalesce(v_rc.bonus_entry, 0))
    where id = r.id;
    v_n := v_n + 1;
  end loop;

  return v_n;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Een deal die op een gedeelde plaats uitkomt
-- ---------------------------------------------------------------------------
-- Standaard beslist het geld: krijgt iedereen in de deal hetzelfde bedrag,
-- dan eindigen ze ex aequo. Een ICM-deal verdeelt ongelijk omdat de stapels
-- ongelijk zijn, en dan is de volgorde wél gespeeld.
--
-- De floor kan het overrulen, want er zijn tafels die om acht uur 's avonds
-- iets afspreken dat geen formule kent.

drop function if exists public.deal_accept(uuid);

create or replace function public.deal_accept(
  p_tournament_id uuid,
  p_ex_aequo      boolean default null
)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  t       tournaments%rowtype;
  d       tournament_deals%rowtype;
  v_rows  int;
  r       record;
  v_ids   uuid[];
  v_zelfde boolean;
begin
  select * into t from tournaments where id = p_tournament_id;
  if not found then
    raise exception 'Tornooi bestaat niet';
  end if;

  if not public.is_service_context()
     and not public.has_club_role(t.club_id, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten om deze deal te bevestigen'
      using errcode = 'insufficient_privilege';
  end if;

  select * into d from tournament_deals
  where tournament_id = p_tournament_id and status = 'proposed';

  if not found then
    raise exception 'Er ligt geen voorstel op tafel' using errcode = 'check_violation';
  end if;

  update tournament_deals
  set status = 'accepted', decided_at = now()
  where id = d.id;

  -- Wie zit er in de deal, en krijgen ze allemaal hetzelfde?
  select array_agg((s->>'tournament_player_id')::uuid),
         count(distinct (s->>'agreed_cents')::int) = 1
    into v_ids, v_zelfde
  from jsonb_array_elements(d.shares) s
  where (s->>'agreed_cents')::int > 0;

  if coalesce(p_ex_aequo, v_zelfde, false)
     and v_ids is not null and array_length(v_ids, 1) >= 2 then
    perform public.floor_set_tie(v_ids);
  end if;

  v_rows := public.floor_finish_tournament(p_tournament_id);

  -- Prijzengeld overschrijven voor wie meedeed aan de deal.
  for r in
    select (s->>'tournament_player_id')::uuid as tp_id,
           (s->>'agreed_cents')::int          as cents
    from jsonb_array_elements(d.shares) s
  loop
    update tournament_results tr
    set prize_cents = r.cents
    from tournament_players tp
    where tp.id = r.tp_id
      and tr.tournament_id = p_tournament_id
      and tr.player_id = tp.player_id;
  end loop;

  return v_rows;
end;
$$;

comment on function public.deal_accept(uuid, boolean) is
  'Bevestigt de deal en sluit het tornooi af. Krijgt iedereen hetzelfde bedrag, dan eindigen ze ex aequo en delen ze de punten van de plaatsen die ze samen bezetten; p_ex_aequo overrulet die keuze.';

-- ---------------------------------------------------------------------------
-- 8. En het scherm mag het laten zien
-- ---------------------------------------------------------------------------

drop function if exists public.club_public_player_season(text, uuid, uuid);

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
  place         int,
  /** Met hoeveel spelers die plaats gedeeld werd. 1 is een gewone plaats. */
  shared_with   int,
  entries       int,
  knockouts     int,
  stake_cents   int,
  points        numeric,
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
    select s.id into v_season from public.club_public_seasons(p_club_slug) s limit 1;
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
           r.position, greatest(coalesce(r.shared_with, 1), 1) as gedeeld,
           r.entries_total, r.knockouts, r.points,
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
         z.position, z.gedeeld, z.entries_total, z.knockouts, z.inzet, z.points,
         (v_best_n is null or z.rn <= v_best_n)
  from zichtbaar z
  order by z.rn;
end;
$$;

do $$
declare
  r text;
begin
  foreach r in array array['anon', 'authenticated'] loop
    if exists (select 1 from pg_roles where rolname = r) then
      execute format('grant execute on function public.club_public_player_season(text,uuid,uuid) to %I', r);
    end if;
  end loop;

  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function public.floor_set_tie(uuid[])   to authenticated;
    grant execute on function public.floor_clear_tie(uuid[]) to authenticated;
    grant execute on function public.deal_accept(uuid, boolean) to authenticated;
  end if;
end $$;
