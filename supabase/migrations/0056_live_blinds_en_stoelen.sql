-- Pokerleague — de blinds op de gsm van de speler kloppen altijd
--
-- Op `/ik` stonden de verkeerde blinds, en daarmee ook het verkeerde aantal
-- big blinds. De oorzaak zit niet in de berekening maar in wat er berekend
-- werd: `my_live_tournaments` las `tournaments.level_idx`, en dat veld loopt
-- achter.
--
-- **Waarom dat veld achterloopt.** De klok tikt nergens. Wat er in de databank
-- staat is het vertrekpunt — op welk level, sinds wanneer, met hoeveel tijd al
-- opgebouwd — en elk scherm rekent daaruit uit hoe laat het is. Loopt een
-- level af, dan rolt het floorscherm door en schrijft de nieuwe stand weg.
-- Staat dat scherm dicht, dan gebeurt dat niet: in de databank staat nog level
-- 3 terwijl de zaal al op level 5 speelt. De floor merkt er niets van (zijn
-- scherm rekent het zelf uit), maar de speler kreeg het rauwe veld te zien.
--
-- Vanaf hier rekent de databank het zelf uit, met dezelfde regel als de
-- schermen: de opgebouwde tijd plus, als de klok loopt, wat er sinds het
-- laatste vertrekpunt verstreken is. Dat getal wordt tegen de niveaus
-- afgelopen tot het past. Geen enkel scherm hoeft er nog iets voor te doen —
-- ook een speler die om vier uur 's nachts zijn gsm bovenhaalt terwijl er geen
-- floorscherm meer openstaat, ziet de juiste blinds.
--
-- Er komt ook bij hoeveel tijd dit niveau nog heeft, zodat de spelerspagina
-- kan aftellen in plaats van te wachten op het volgende bezoek.

-- ---------------------------------------------------------------------------
-- 1. Waar de klok werkelijk staat
-- ---------------------------------------------------------------------------

create or replace function public.clock_position(p_tournament_id uuid)
returns table (
  level_idx     int,
  remaining_ms  bigint,
  finished      boolean
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  t        tournaments%rowtype;
  v_idx    int;
  v_ms     bigint;
  v_duur   bigint;
  v_laatste int;
begin
  select * into t from tournaments where id = p_tournament_id;
  if not found then
    return;
  end if;

  select max(l.idx) into v_laatste
  from blind_levels l where l.structure_id = t.structure_id;

  if v_laatste is null then
    level_idx := t.level_idx; remaining_ms := 0; finished := true;
    return next; return;
  end if;

  v_idx := greatest(0, least(t.level_idx, v_laatste));

  -- De opgebouwde tijd. Alleen bij een lopende klok telt de tijd sinds het
  -- vertrekpunt mee; een pauze van een uur schuift dus geen enkel niveau op.
  v_ms := coalesce(t.level_elapsed_ms, 0)
        + case
            when t.clock = 'running' and t.level_started_at is not null
              then greatest(0, (extract(epoch from (now() - t.level_started_at)) * 1000)::bigint)
            else 0
          end;

  loop
    select (l.duration_s::bigint * 1000) into v_duur
    from blind_levels l
    where l.structure_id = t.structure_id and l.idx = v_idx;

    exit when v_duur is null;
    exit when v_ms < v_duur;
    -- Een niveau van nul seconden zou hier eeuwig blijven lussen.
    exit when v_duur = 0 and v_idx >= v_laatste;

    if v_duur = 0 then
      v_idx := v_idx + 1;
    else
      v_ms := v_ms - v_duur;
      v_idx := v_idx + 1;
    end if;

    if v_idx > v_laatste then
      level_idx := v_laatste; remaining_ms := 0; finished := true;
      return next; return;
    end if;
  end loop;

  select (l.duration_s::bigint * 1000) into v_duur
  from blind_levels l where l.structure_id = t.structure_id and l.idx = v_idx;

  level_idx    := v_idx;
  remaining_ms := greatest(0, coalesce(v_duur, 0) - v_ms);
  finished     := false;
  return next;
end;
$$;

comment on function public.clock_position(uuid) is
  'Waar de klok van een tornooi werkelijk staat: het niveau en hoeveel tijd dat niveau nog heeft. Rekent de opgebouwde tijd door de niveaus heen, net als de schermen doen, zodat een speler de juiste blinds ziet ook als er geen floorscherm openstaat.';

-- ---------------------------------------------------------------------------
-- 2. Een stoel voorstellen, en er iemand op zetten
-- ---------------------------------------------------------------------------
-- Voor aan de deur: je tikt iemand in, en dan hoor je meteen te weten waar hij
-- gaat zitten. Het voorstel is de laagste vrije stoel aan de laagst genummerde
-- open tafel — dezelfde regel als het indelen. Zit alles vol, dan zegt het
-- voorstel welke tafel erbij komt.

create or replace function public.seating_suggestion(p_tournament_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  t       tournaments%rowtype;
  v_tafel int;
  v_stoel int;
begin
  select * into t from tournaments where id = p_tournament_id;
  if not found then
    raise exception 'Tornooi bestaat niet';
  end if;
  if not public.is_service_context() and not public.can_view_tournament(p_tournament_id) then
    raise exception 'Geen rechten' using errcode = 'insufficient_privilege';
  end if;

  select tt.table_no, s.seat into v_tafel, v_stoel
  from tournament_tables tt
  cross join lateral generate_series(1, tt.seats) as s(seat)
  where tt.tournament_id = p_tournament_id
    and tt.is_open
    and not exists (
      select 1 from tournament_players x
      where x.tournament_id = p_tournament_id
        and x.table_no = tt.table_no and x.seat_no = s.seat
        and x.status in ('active', 'registered'))
  order by tt.table_no, s.seat
  limit 1;

  if v_tafel is not null then
    return jsonb_build_object('table_no', v_tafel, 'seat_no', v_stoel, 'opens_table', false);
  end if;

  -- Alles vol, of er staat nog geen tafel. Dan komt er een bij.
  select coalesce(max(table_no), 0) + 1 into v_tafel
  from tournament_tables where tournament_id = p_tournament_id;

  return jsonb_build_object('table_no', v_tafel, 'seat_no', 1, 'opens_table', true);
end;
$$;

create or replace function public.floor_seat_next(p_tournament_player_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  tp      tournament_players%rowtype;
  v_sug   jsonb;
  v_tafel int;
begin
  select * into tp from tournament_players where id = p_tournament_player_id;
  if not found then
    raise exception 'Deelnemer bestaat niet';
  end if;

  if not public.is_service_context()
     and not public.has_club_role(tp.club_id, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten' using errcode = 'insufficient_privilege';
  end if;

  v_sug := public.seating_suggestion(tp.tournament_id);

  if (v_sug ->> 'opens_table')::boolean then
    v_tafel := public.floor_open_table(tp.tournament_id);
  else
    v_tafel := (v_sug ->> 'table_no')::int;
  end if;

  perform public.floor_seat_player(p_tournament_player_id, v_tafel, (v_sug ->> 'seat_no')::int);

  return jsonb_build_object('table_no', v_tafel, 'seat_no', (v_sug ->> 'seat_no')::int);
end;
$$;

comment on function public.floor_seat_next(uuid) is
  'Zet één speler op de eerstvolgende vrije stoel en opent zo nodig een tafel. Voor aan de deur: iemand toevoegen en meteen weten waar hij zit.';

-- ---------------------------------------------------------------------------
-- 3. De spelerspagina, nu met de klok van dit moment
-- ---------------------------------------------------------------------------

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
  level_remaining_ms   bigint,
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
    k.level_idx,
    (select l.label from blind_levels l
      where l.structure_id = t.structure_id and l.idx = k.level_idx),
    coalesce((select l.is_break from blind_levels l
      where l.structure_id = t.structure_id and l.idx = k.level_idx), false),
    coalesce((select l.small_blind from blind_levels l
      where l.structure_id = t.structure_id and l.idx >= k.level_idx and not l.is_break
      order by l.idx limit 1), 0),
    coalesce((select l.big_blind from blind_levels l
      where l.structure_id = t.structure_id and l.idx >= k.level_idx and not l.is_break
      order by l.idx limit 1), 0),
    coalesce((select l.ante from blind_levels l
      where l.structure_id = t.structure_id and l.idx >= k.level_idx and not l.is_break
      order by l.idx limit 1), 0),
    coalesce((select l.big_blind from blind_levels l
      where l.structure_id = t.structure_id and l.idx > k.level_idx and not l.is_break
      order by l.idx limit 1), 0),
    k.remaining_ms,
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
  cross join lateral public.clock_position(t.id) k
  order by t.scheduled_at desc;
$$;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function public.clock_position(uuid)       to authenticated;
    grant execute on function public.seating_suggestion(uuid)   to authenticated;
    grant execute on function public.floor_seat_next(uuid)      to authenticated;
    grant execute on function public.my_live_tournaments()      to authenticated;
  end if;
  if exists (select 1 from pg_roles where rolname = 'anon') then
    grant execute on function public.clock_position(uuid) to anon;
  end if;
end $$;
