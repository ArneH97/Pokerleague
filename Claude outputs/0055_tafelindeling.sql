-- Pokerleague — tafels, stoelen, en wie waar zit
--
-- De tabellen bestonden al: `tournament_tables` met een tafelnummer en een
-- aantal stoelen, en `table_no` / `seat_no` op de deelnemer. Er stond alleen
-- nooit iets in. Dit bestand maakt er een indeling van.
--
-- **De afspraak van deze zaal, en waar ze vandaan komt.**
--
--   * Tafels lopen één voor één vol. Pas als tafel 1 vol zit gaat tafel 2
--     open. Bij een rustige avond hoef je zo geen tweede tafel te zetten.
--   * Verplaatsen gebeurt nooit vanzelf. De databank rékent uit wie er zou
--     moeten verhuizen en waarheen, maar zet niemand in beweging: dat is een
--     voorstel dat de floor bevestigt. Aan een tafel waar net iemand all-in
--     zit, weet het scherm niet wat de zaal weet.
--   * En elk voorstel is te overschrijven. `floor_seat_player` zet wie dan ook
--     op welke vrije stoel dan ook, of wisselt twee spelers om als de stoel
--     bezet is. Er is geen toestand waarin de floor iets *moet* volgen; de
--     voorstellen zijn een rekenhulp, geen voogd.
--
-- **Waarom voorstellen jsonb teruggeven en niets bewaren.** Een voorstel dat
-- in een tabel staat, veroudert: er valt iemand af, er komt iemand bij, en het
-- voorstel wijst nog naar een stoel die intussen bezet is. Door het bij elke
-- vraag opnieuw te berekenen, is wat je op het scherm ziet altijd van dit
-- moment. Wat je bevestigt, gaat langs dezelfde controles als een handmatige
-- verplaatsing — er is geen achterdeur die de regels overslaat.
--
-- **Wat er niet in zit: de button.** `tournament_tables.button_seat` blijft
-- leeg. In een cardroom bepaalt de positie van de button wie er bij het
-- balanceren verhuist — je haalt de speler weg die anders meteen weer de big
-- blind zou betalen. Die regel eerlijk toepassen vraagt dat de zaal per hand
-- doorgeeft waar de button staat, en dat gaat een floor met drie tafels niet
-- doen. Het voorstel kiest daarom voorspelbaar (de hoogste stoel aan de
-- volste tafel) en zegt niet meer te weten dan het weet. De floor overschrijft
-- het met één tik als hij ziet dat die speler net gepost heeft.

-- ---------------------------------------------------------------------------
-- 1. Een stoel is van wie er nog speelt
-- ---------------------------------------------------------------------------
-- Wie afvalt, laat zijn stoel los. Zonder dit blijft er een naam op een stoel
-- staan die allang leeg is, en denkt de indeling dat de tafel nog vol zit.

create or replace function public.clear_seat_on_exit()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.status = 'eliminated' and old.status <> 'eliminated' then
    new.table_no := null;
    new.seat_no  := null;
  end if;
  return new;
end;
$$;

drop trigger if exists tournament_players_seat_release on tournament_players;
create trigger tournament_players_seat_release
  before update on tournament_players
  for each row execute function public.clear_seat_on_exit();

-- ---------------------------------------------------------------------------
-- 2. Tafels openen en sluiten
-- ---------------------------------------------------------------------------

create or replace function public.floor_open_table(p_tournament_id uuid)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  t     tournaments%rowtype;
  v_no  int;
begin
  select * into t from tournaments where id = p_tournament_id;
  if not found then
    raise exception 'Tornooi bestaat niet';
  end if;

  if not public.is_service_context()
     and not public.has_club_role(t.club_id, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten' using errcode = 'insufficient_privilege';
  end if;

  -- Een gesloten tafel weer openen gaat voor op een nieuwe erbij: nummers die
  -- opnieuw gebruikt worden, blijven laag, en een zaal met tafel 1, 2 en 7 is
  -- een zaal waar niemand zijn tafel vindt.
  select table_no into v_no
  from tournament_tables
  where tournament_id = p_tournament_id and not is_open
  order by table_no
  limit 1;

  if v_no is not null then
    update tournament_tables set is_open = true
    where tournament_id = p_tournament_id and table_no = v_no;
    return v_no;
  end if;

  select coalesce(max(table_no), 0) + 1 into v_no
  from tournament_tables where tournament_id = p_tournament_id;

  insert into tournament_tables (club_id, tournament_id, table_no)
  values (t.club_id, p_tournament_id, v_no);

  return v_no;
end;
$$;

create or replace function public.floor_close_table(
  p_tournament_id uuid,
  p_table_no      int
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  t     tournaments%rowtype;
  v_bez int;
begin
  select * into t from tournaments where id = p_tournament_id;
  if not found then
    raise exception 'Tornooi bestaat niet';
  end if;

  if not public.is_service_context()
     and not public.has_club_role(t.club_id, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten' using errcode = 'insufficient_privilege';
  end if;

  select count(*) into v_bez
  from tournament_players
  where tournament_id = p_tournament_id
    and table_no = p_table_no
    and status in ('active', 'registered');

  if v_bez > 0 then
    raise exception 'Aan tafel % zitten nog % spelers. Zet die eerst elders.', p_table_no, v_bez
      using errcode = 'check_violation';
  end if;

  update tournament_tables set is_open = false
  where tournament_id = p_tournament_id and table_no = p_table_no;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Iemand op een stoel zetten — met de hand, en dus altijd het laatste woord
-- ---------------------------------------------------------------------------
-- Is de stoel bezet, dan wisselen de twee spelers van plaats. Dat is wat een
-- floor doet als hij zich vergist heeft, en het scheelt hem de omweg langs
-- "haal die eerst weg".

create or replace function public.floor_seat_player(
  p_tournament_player_id uuid,
  p_table_no             int,
  p_seat_no              int
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  tp     tournament_players%rowtype;
  t      tournaments%rowtype;
  tafel  tournament_tables%rowtype;
  v_ander uuid;
  v_oud_t int;
  v_oud_s int;
begin
  select * into tp from tournament_players where id = p_tournament_player_id;
  if not found then
    raise exception 'Deelnemer bestaat niet';
  end if;

  select * into t from tournaments where id = tp.tournament_id;

  if not public.is_service_context()
     and not public.has_club_role(tp.club_id, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten' using errcode = 'insufficient_privilege';
  end if;

  if tp.status not in ('active', 'registered') then
    raise exception 'Deze speler zit niet meer in het tornooi' using errcode = 'check_violation';
  end if;

  select * into tafel from tournament_tables
  where tournament_id = tp.tournament_id and table_no = p_table_no;

  if not found then
    raise exception 'Tafel % bestaat niet in dit tornooi', p_table_no using errcode = 'check_violation';
  end if;
  if not tafel.is_open then
    raise exception 'Tafel % is gesloten', p_table_no using errcode = 'check_violation';
  end if;
  if p_seat_no < 1 or p_seat_no > tafel.seats then
    raise exception 'Tafel % heeft stoelen 1 tot %', p_table_no, tafel.seats
      using errcode = 'check_violation';
  end if;

  v_oud_t := tp.table_no;
  v_oud_s := tp.seat_no;

  -- Zit er al iemand? Dan wisselen ze. Wie verplaatst wordt naar een bezette
  -- stoel had zelf misschien nog geen plaats; dan staat de ander gewoon op.
  select id into v_ander
  from tournament_players
  where tournament_id = tp.tournament_id
    and table_no = p_table_no and seat_no = p_seat_no
    and status in ('active', 'registered')
    and id <> tp.id;

  -- Eerst de stoel vrijmaken, anders botst de unieke index halverwege.
  if v_ander is not null then
    update tournament_players set table_no = null, seat_no = null where id = v_ander;
  end if;

  update tournament_players
  set table_no = p_table_no, seat_no = p_seat_no
  where id = tp.id;

  if v_ander is not null then
    update tournament_players
    set table_no = v_oud_t, seat_no = v_oud_s
    where id = v_ander;
  end if;
end;
$$;

create or replace function public.floor_unseat_player(p_tournament_player_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  tp tournament_players%rowtype;
begin
  select * into tp from tournament_players where id = p_tournament_player_id;
  if not found then
    raise exception 'Deelnemer bestaat niet';
  end if;

  if not public.is_service_context()
     and not public.has_club_role(tp.club_id, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten' using errcode = 'insufficient_privilege';
  end if;

  update tournament_players set table_no = null, seat_no = null where id = tp.id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Iedereen zonder stoel een plaats geven
-- ---------------------------------------------------------------------------
-- Tafels één voor één vol, en pas een nieuwe tafel openen als het niet anders
-- kan. Wie al zit, blijft zitten: dit deelt alleen in wat nog staat.

create or replace function public.floor_autoseat(p_tournament_id uuid)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  t      tournaments%rowtype;
  r      record;
  v_tafel int;
  v_stoel int;
  v_n    int := 0;
begin
  select * into t from tournaments where id = p_tournament_id;
  if not found then
    raise exception 'Tornooi bestaat niet';
  end if;

  if not public.is_service_context()
     and not public.has_club_role(t.club_id, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten' using errcode = 'insufficient_privilege';
  end if;

  -- Op volgorde van inschrijving, zodat wie eerst aan de deur stond ook eerst
  -- een stoel krijgt. Voorspelbaar is hier meer waard dan slim.
  for r in
    select id from tournament_players
    where tournament_id = p_tournament_id
      and status in ('active', 'registered')
      and (table_no is null or seat_no is null)
    order by registered_at, id
  loop
    -- De laagste vrije stoel aan de laagst genummerde open tafel.
    select tt.table_no, s.seat into v_tafel, v_stoel
    from tournament_tables tt
    cross join lateral generate_series(1, tt.seats) as s(seat)
    where tt.tournament_id = p_tournament_id
      and tt.is_open
      and not exists (
        select 1 from tournament_players x
        where x.tournament_id = p_tournament_id
          and x.table_no = tt.table_no and x.seat_no = s.seat
          and x.status in ('active', 'registered')
      )
    order by tt.table_no, s.seat
    limit 1;

    if v_tafel is null then
      v_tafel := public.floor_open_table(p_tournament_id);
      v_stoel := 1;
    end if;

    update tournament_players
    set table_no = v_tafel, seat_no = v_stoel
    where id = r.id;

    v_n := v_n + 1;
  end loop;

  return v_n;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Het plan: wie zit waar
-- ---------------------------------------------------------------------------

create or replace function public.seating_plan(p_tournament_id uuid)
returns table (
  table_no     int,
  seats        int,
  is_open      boolean,
  seat_no      int,
  tournament_player_id uuid,
  display_name text,
  chip_count   int
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    tt.table_no,
    tt.seats,
    tt.is_open,
    s.seat,
    tp.id,
    p.display_name,
    tp.chip_count
  from tournament_tables tt
  cross join lateral generate_series(1, tt.seats) as s(seat)
  left join tournament_players tp
    on tp.tournament_id = tt.tournament_id
   and tp.table_no = tt.table_no
   and tp.seat_no = s.seat
   and tp.status in ('active', 'registered')
  left join players p on p.id = tp.player_id
  where tt.tournament_id = p_tournament_id
    and public.can_view_tournament(p_tournament_id)
  order by tt.table_no, s.seat;
$$;

-- ---------------------------------------------------------------------------
-- 6. Het voorstel
-- ---------------------------------------------------------------------------
-- Twee soorten. Past iedereen op één tafel minder, dan is het voorstel om de
-- hoogste tafel te breken en die spelers te verdelen. Anders: zolang de volste
-- tafel er twee of meer heeft dan de leegste, schuift er iemand op.
--
-- Het rekent op een kopie in het geheugen en raakt de tabel niet aan. Wat
-- eruit komt is een lijst zetten; wie ze uitvoert is de floor.

create or replace function public.seating_proposal(p_tournament_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  t         tournaments%rowtype;
  v_open    int;
  v_spelers int;
  v_stoelen int;
  v_soort   text := 'none';
  v_zetten  jsonb := '[]'::jsonb;
  v_breek   int;
  r         record;
  v_van     int;
  v_naar    int;
  v_aantal  int;
  v_bezet   jsonb;
  v_ronde   int := 0;
begin
  select * into t from tournaments where id = p_tournament_id;
  if not found then
    raise exception 'Tornooi bestaat niet';
  end if;
  if not public.is_service_context() and not public.can_view_tournament(p_tournament_id) then
    raise exception 'Geen rechten' using errcode = 'insufficient_privilege';
  end if;

  select count(*) into v_open
  from tournament_tables where tournament_id = p_tournament_id and is_open;

  select count(*) into v_spelers
  from tournament_players
  where tournament_id = p_tournament_id and status in ('active','registered');

  if v_open = 0 or v_spelers = 0 then
    return jsonb_build_object('kind', 'none', 'moves', '[]'::jsonb);
  end if;

  -- Hoeveel stoelen er open staan als we de hoogste tafel wegdenken.
  select coalesce(sum(seats), 0) into v_stoelen
  from tournament_tables
  where tournament_id = p_tournament_id and is_open
    and table_no <> (
      select max(table_no) from tournament_tables
      where tournament_id = p_tournament_id and is_open);

  select max(table_no) into v_breek
  from tournament_tables where tournament_id = p_tournament_id and is_open;

  -- Bezetting per tafel, als werkblad.
  select coalesce(jsonb_object_agg(tt.table_no::text, jsonb_build_object(
           'seats', tt.seats,
           'bezet', (select count(*) from tournament_players x
                      where x.tournament_id = p_tournament_id
                        and x.table_no = tt.table_no
                        and x.status in ('active','registered'))
         )), '{}'::jsonb)
    into v_bezet
  from tournament_tables tt
  where tt.tournament_id = p_tournament_id and tt.is_open;

  -- ---------------------------------------------------------------- breken
  if v_open > 1 and v_spelers <= v_stoelen then
    v_soort := 'break';
    for r in
      select tp.id, p.display_name, tp.seat_no
      from tournament_players tp
      join players p on p.id = tp.player_id
      where tp.tournament_id = p_tournament_id
        and tp.table_no = v_breek
        and tp.status in ('active','registered')
      order by tp.seat_no
    loop
      select tt.table_no, s.seat into v_naar, v_aantal
      from tournament_tables tt
      cross join lateral generate_series(1, tt.seats) as s(seat)
      where tt.tournament_id = p_tournament_id
        and tt.is_open and tt.table_no <> v_breek
        and not exists (
          select 1 from tournament_players x
          where x.tournament_id = p_tournament_id
            and x.table_no = tt.table_no and x.seat_no = s.seat
            and x.status in ('active','registered'))
        and not (v_zetten @> jsonb_build_array(
              jsonb_build_object('to_table', tt.table_no, 'to_seat', s.seat)))
      order by (v_bezet -> tt.table_no::text ->> 'bezet')::int, tt.table_no, s.seat
      limit 1;

      exit when v_naar is null;

      v_zetten := v_zetten || jsonb_build_object(
        'tournament_player_id', r.id,
        'name', r.display_name,
        'from_table', v_breek, 'from_seat', r.seat_no,
        'to_table', v_naar,   'to_seat', v_aantal);

      v_bezet := jsonb_set(v_bezet, array[v_naar::text, 'bezet'],
        to_jsonb(((v_bezet -> v_naar::text ->> 'bezet')::int) + 1));
    end loop;

    return jsonb_build_object('kind', v_soort, 'break_table', v_breek, 'moves', v_zetten);
  end if;

  -- ------------------------------------------------------------ balanceren
  loop
    v_ronde := v_ronde + 1;
    exit when v_ronde > 20;   -- vangnet; twintig zetten is al een hele zaal

    select k::int into v_van
    from jsonb_object_keys(v_bezet) k
    order by (v_bezet -> k ->> 'bezet')::int desc, k::int
    limit 1;

    select k::int into v_naar
    from jsonb_object_keys(v_bezet) k
    order by (v_bezet -> k ->> 'bezet')::int, k::int
    limit 1;

    exit when v_van is null or v_naar is null or v_van = v_naar;
    exit when ((v_bezet -> v_van::text ->> 'bezet')::int)
            - ((v_bezet -> v_naar::text ->> 'bezet')::int) < 2;

    -- De hoogste bezette stoel aan de volste tafel, die nog niet verzet is.
    select tp.id, p.display_name, tp.seat_no into r
    from tournament_players tp
    join players p on p.id = tp.player_id
    where tp.tournament_id = p_tournament_id
      and tp.table_no = v_van
      and tp.status in ('active','registered')
      and not (v_zetten @> jsonb_build_array(jsonb_build_object('tournament_player_id', tp.id)))
    order by tp.seat_no desc
    limit 1;

    exit when r.id is null;

    select s.seat into v_aantal
    from tournament_tables tt
    cross join lateral generate_series(1, tt.seats) as s(seat)
    where tt.tournament_id = p_tournament_id and tt.table_no = v_naar
      and not exists (
        select 1 from tournament_players x
        where x.tournament_id = p_tournament_id
          and x.table_no = v_naar and x.seat_no = s.seat
          and x.status in ('active','registered'))
      and not (v_zetten @> jsonb_build_array(
            jsonb_build_object('to_table', v_naar, 'to_seat', s.seat)))
    order by s.seat
    limit 1;

    exit when v_aantal is null;

    v_soort := 'balance';
    v_zetten := v_zetten || jsonb_build_object(
      'tournament_player_id', r.id,
      'name', r.display_name,
      'from_table', v_van, 'from_seat', r.seat_no,
      'to_table', v_naar,  'to_seat', v_aantal);

    v_bezet := jsonb_set(v_bezet, array[v_van::text, 'bezet'],
      to_jsonb(((v_bezet -> v_van::text ->> 'bezet')::int) - 1));
    v_bezet := jsonb_set(v_bezet, array[v_naar::text, 'bezet'],
      to_jsonb(((v_bezet -> v_naar::text ->> 'bezet')::int) + 1));
  end loop;

  return jsonb_build_object('kind', v_soort, 'moves', v_zetten);
end;
$$;

comment on function public.seating_proposal(uuid) is
  'Rekent uit wat er met de tafels zou moeten gebeuren: een tafel breken als iedereen op minder tafels past, anders spelers verschuiven tot het verschil hoogstens één is. Verandert niets — de floor beslist.';

-- ---------------------------------------------------------------------------
-- 7. Een voorstel uitvoeren
-- ---------------------------------------------------------------------------
-- Langs dezelfde deur als een handmatige verplaatsing, zodat er geen tweede
-- set regels ontstaat. Eerst iedereen die verhuist van zijn stoel af, dan pas
-- neerzetten: anders botst de ene zet op de stoel die de volgende nog moet
-- verlaten.

create or replace function public.floor_apply_moves(
  p_tournament_id uuid,
  p_moves         jsonb
)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  t   tournaments%rowtype;
  z   jsonb;
  v_n int := 0;
begin
  select * into t from tournaments where id = p_tournament_id;
  if not found then
    raise exception 'Tornooi bestaat niet';
  end if;

  if not public.is_service_context()
     and not public.has_club_role(t.club_id, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten' using errcode = 'insufficient_privilege';
  end if;

  if p_moves is null or jsonb_typeof(p_moves) <> 'array' then
    raise exception 'Geef een lijst met zetten mee' using errcode = 'check_violation';
  end if;

  for z in select * from jsonb_array_elements(p_moves) loop
    update tournament_players
    set table_no = null, seat_no = null
    where id = (z ->> 'tournament_player_id')::uuid
      and tournament_id = p_tournament_id;
  end loop;

  for z in select * from jsonb_array_elements(p_moves) loop
    perform public.floor_seat_player(
      (z ->> 'tournament_player_id')::uuid,
      (z ->> 'to_table')::int,
      (z ->> 'to_seat')::int);
    v_n := v_n + 1;
  end loop;

  return v_n;
end;
$$;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function public.floor_open_table(uuid)                 to authenticated;
    grant execute on function public.floor_close_table(uuid, int)           to authenticated;
    grant execute on function public.floor_seat_player(uuid, int, int)      to authenticated;
    grant execute on function public.floor_unseat_player(uuid)              to authenticated;
    grant execute on function public.floor_autoseat(uuid)                   to authenticated;
    grant execute on function public.seating_plan(uuid)                     to authenticated;
    grant execute on function public.seating_proposal(uuid)                 to authenticated;
    grant execute on function public.floor_apply_moves(uuid, jsonb)         to authenticated;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 8. En de speler ziet waar hij zit
-- ---------------------------------------------------------------------------
-- Tafel en stoel op zijn eigen scherm. Dat scheelt de floor rondroepen, en na
-- een verplaatsing weet hij het voor jij bij hem bent.

drop function if exists public.my_live_tournaments();

create or replace function public.my_live_tournaments()
returns table (
  tournament_id        uuid,
  tournament_player_id uuid,
  name                 text,
  club_slug            text,
  club_name            text,
  logo_url             text,
  primary_color        text,
  currency             char(3),
  status               text,
  clock                text,
  level_idx            int,
  level_label          text,
  is_break             boolean,
  small_blind          int,
  big_blind            int,
  ante                 int,
  next_big_blind       int,
  my_chips             int,
  my_chips_by          text,
  my_chips_at          timestamptz,
  counts_frozen        boolean,
  my_table             int,
  my_seat              int,
  players_left         int,
  entries              int,
  avg_stack            int,
  chips_in_play        int,
  my_rank              int,
  ranked_players       int,
  paid_places          int,
  prize_pool_cents     bigint
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with me as (
    select id from players
    where auth_user_id = auth.uid() and merged_into_id is null
  ),
  mijn as (
    select tp.*
    from tournament_players tp
    join tournaments t on t.id = tp.tournament_id
    where tp.player_id = (select id from me)
      and t.status in ('running', 'paused')
      and tp.status in ('active', 'registered')
  )
  select
    t.id,
    m.id,
    t.name,
    c.slug,
    c.name,
    c.logo_url,
    c.primary_color,
    c.currency,
    t.status::text,
    t.clock::text,
    t.level_idx,
    (select l.label from blind_levels l
      where l.structure_id = t.structure_id and l.idx = t.level_idx),
    coalesce((select l.is_break from blind_levels l
      where l.structure_id = t.structure_id and l.idx = t.level_idx), false),
    coalesce((select l.small_blind from blind_levels l
      where l.structure_id = t.structure_id and l.idx >= t.level_idx and not l.is_break
      order by l.idx limit 1), 0),
    coalesce((select l.big_blind from blind_levels l
      where l.structure_id = t.structure_id and l.idx >= t.level_idx and not l.is_break
      order by l.idx limit 1), 0),
    coalesce((select l.ante from blind_levels l
      where l.structure_id = t.structure_id and l.idx >= t.level_idx and not l.is_break
      order by l.idx limit 1), 0),
    coalesce((select l.big_blind from blind_levels l
      where l.structure_id = t.structure_id and l.idx > t.level_idx and not l.is_break
      order by l.idx limit 1), 0),
    m.chip_count,
    m.chip_count_by::text,
    m.chip_count_updated_at,
    t.counts_frozen_at is not null,
    m.table_no,
    m.seat_no,
    (select count(*)::int from tournament_players x
      where x.tournament_id = t.id and x.status in ('active','registered')),
    (select count(*)::int from tournament_players x where x.tournament_id = t.id),
    (public.chips_in_play(t.id) / greatest(1, (
       select count(*)::int from tournament_players x
       where x.tournament_id = t.id and x.status in ('active','registered'))))::int,
    public.chips_in_play(t.id),
    case when m.chip_count is null then null else (
      select count(*)::int + 1
      from tournament_players x
      where x.tournament_id = t.id
        and x.status in ('active','registered')
        and x.chip_count is not null
        and x.chip_count > m.chip_count
    ) end,
    (select count(*)::int from tournament_players x
      where x.tournament_id = t.id
        and x.status in ('active','registered')
        and x.chip_count is not null),
    (select count(*)::int from public.tournament_prizes(t.id)),
    (select coalesce(sum(b.amount_cents), 0) from buyins b
      where b.tournament_id = t.id and not b.is_void)
  from mijn m
  join tournaments t on t.id = m.tournament_id
  join clubs c       on c.id = t.club_id
  order by t.scheduled_at desc;
$$;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function public.my_live_tournaments() to authenticated;
  end if;
end $$;
