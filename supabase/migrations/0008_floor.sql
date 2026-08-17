-- Pokerleague — handelingen van de floor tijdens een tornooi
--
-- Waarom dit in de database staat en niet in de browser: elke handeling
-- hieronder raakt meerdere tabellen tegelijk. Een speler toevoegen betekent
-- een profiel, een clublidmaatschap, een deelname én een inkoop. Doet de
-- browser dat in vier losse aanroepen en valt de wifi weg na de derde, dan
-- staat er iemand aan tafel die niet betaald heeft.
--
-- En de eindplaats bij een uitschakeling moet de server bepalen. Twee
-- toestellen die tegelijk iemand wegklikken zouden anders allebei dezelfde
-- plaats uitdelen, en dan klopt je hele uitslag niet meer.

-- ---------------------------------------------------------------------------
-- Speler toevoegen en meteen laten inkopen
-- ---------------------------------------------------------------------------
-- Geef ofwel een bestaande p_player_id mee, ofwel p_new_name voor iemand die
-- er voor het eerst is. Dat tweede geval is de rij aan de deur: enkel een
-- naam, geen account, geen formulier.

create or replace function public.floor_add_entry(
  p_tournament_id uuid,
  p_player_id     uuid default null,
  p_new_name      text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  t        tournaments%rowtype;
  v_player uuid;
  v_tp     uuid;
begin
  select * into t from tournaments where id = p_tournament_id;
  if not found then
    raise exception 'Tornooi bestaat niet';
  end if;

  if not public.is_service_context()
     and not public.has_club_role(t.club_id, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten om spelers toe te voegen'
      using errcode = 'insufficient_privilege';
  end if;

  if t.status in ('finished', 'cancelled') then
    raise exception 'Dit tornooi is afgelopen' using errcode = 'check_violation';
  end if;

  if p_player_id is not null then
    v_player := public.resolve_player(p_player_id);
  else
    if coalesce(trim(p_new_name), '') = '' then
      raise exception 'Geef een naam op' using errcode = 'check_violation';
    end if;
    insert into players (display_name) values (trim(p_new_name)) returning id into v_player;
  end if;

  insert into club_players (club_id, player_id, joined_on)
  values (t.club_id, v_player, current_date)
  on conflict (club_id, player_id) do nothing;

  -- Al ingeschreven? Dan niets dubbel boeken, gewoon teruggeven.
  select id into v_tp from tournament_players
  where tournament_id = p_tournament_id and player_id = v_player;

  if v_tp is not null then
    return v_tp;
  end if;

  insert into tournament_players (
    club_id, tournament_id, player_id, status, chip_count
  ) values (
    t.club_id, p_tournament_id, v_player, 'active', t.starting_stack
  )
  returning id into v_tp;

  insert into buyins (
    club_id, tournament_id, tournament_player_id, player_id,
    kind, amount_cents, fee_cents, bounty_cents, recorded_by
  ) values (
    t.club_id, p_tournament_id, v_tp, v_player,
    'buyin', t.buyin_cents, t.fee_cents,
    case when t.bounty_mode = 'none' then 0 else t.bounty_cents end,
    auth.uid()
  );

  -- Een inschrijving vooraf is nu een deelname geworden.
  update tournament_registrations
  set cancelled_at = coalesce(cancelled_at, now())
  where tournament_id = p_tournament_id and player_id = v_player and cancelled_at is null;

  return v_tp;
end;
$$;

-- ---------------------------------------------------------------------------
-- Opnieuw inkopen: re-entry, rebuy of addon
-- ---------------------------------------------------------------------------

create or replace function public.floor_rebuy(
  p_tournament_player_id uuid,
  p_kind                 buyin_kind default 'reentry'
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  tp tournament_players%rowtype;
  t  tournaments%rowtype;
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

  if p_kind = 'buyin' then
    raise exception 'Gebruik floor_add_entry voor de eerste inkoop' using errcode = 'check_violation';
  end if;

  insert into buyins (
    club_id, tournament_id, tournament_player_id, player_id,
    kind, amount_cents, fee_cents, bounty_cents, recorded_by
  ) values (
    tp.club_id, tp.tournament_id, tp.id, tp.player_id,
    p_kind,
    case when p_kind = 'addon' then coalesce(t.addon_cents, t.buyin_cents) else t.buyin_cents end,
    case when p_kind = 'addon' then 0 else t.fee_cents end,
    case when t.bounty_mode = 'none' or p_kind = 'addon' then 0 else t.bounty_cents end,
    auth.uid()
  );

  -- Een re-entry brengt een uitgeschakelde speler terug aan tafel; een rebuy
  -- of addon geeft alleen chips aan wie er al zit.
  update tournament_players
  set status          = case when p_kind = 'reentry' then 'active' else status end,
      finish_position = case when p_kind = 'reentry' then null else finish_position end,
      eliminated_at   = case when p_kind = 'reentry' then null else eliminated_at end,
      -- Een re-entry begint van nul af aan met een verse stack; een rebuy of
      -- addon legt chips bij wat er al ligt.
      chip_count      = case
                          when p_kind = 'reentry' then t.starting_stack
                          when p_kind = 'addon'
                            then coalesce(chip_count, 0) + coalesce(t.addon_stack, t.starting_stack)
                          else coalesce(chip_count, 0) + t.starting_stack
                        end
  where id = tp.id;

  -- Bij een re-entry schuift iedereen die na hem afviel een plaats op, anders
  -- staan er straks twee spelers op dezelfde eindplaats.
  if p_kind = 'reentry' and tp.finish_position is not null then
    update tournament_players
    set finish_position = finish_position - 1
    where tournament_id = tp.tournament_id
      and finish_position is not null
      and finish_position < tp.finish_position;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Uitschakelen
-- ---------------------------------------------------------------------------
-- De eindplaats wordt hier berekend en niet door de browser meegegeven: twee
-- toestellen die tegelijk iemand wegklikken moeten verschillende plaatsen
-- krijgen. De rijvergrendeling hieronder dwingt dat af.

create or replace function public.floor_eliminate(
  p_tournament_player_id uuid,
  p_by_tournament_player_id uuid default null
)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  tp       tournament_players%rowtype;
  t        tournaments%rowtype;
  v_pos    int;
  v_bounty int := 0;
begin
  select * into tp from tournament_players where id = p_tournament_player_id;
  if not found then
    raise exception 'Deelnemer bestaat niet';
  end if;

  if not public.is_service_context()
     and not public.has_club_role(tp.club_id, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten' using errcode = 'insufficient_privilege';
  end if;

  if tp.status = 'eliminated' then
    return tp.finish_position;
  end if;

  select * into t from tournaments where id = tp.tournament_id;

  -- Vergrendel het tornooi zodat twee gelijktijdige uitschakelingen netjes
  -- na elkaar gebeuren in plaats van dezelfde plaats te pakken.
  perform 1 from tournaments where id = tp.tournament_id for update;

  select count(*) into v_pos
  from tournament_players
  where tournament_id = tp.tournament_id and status in ('active', 'registered');

  -- De chipcount blijft staan. Dat een speler geen chips meer heeft volgt al
  -- uit zijn status; hem hier op nul zetten betekent dat een verkeerde klik
  -- die je meteen terugdraait zijn stack wel definitief wist.
  update tournament_players
  set status = 'eliminated', finish_position = v_pos, eliminated_at = now()
  where id = tp.id;

  if t.bounty_mode <> 'none' and p_by_tournament_player_id is not null then
    v_bounty := t.bounty_cents;
    update tournament_players
    set bounties_won = bounties_won + 1
    where id = p_by_tournament_player_id;
  end if;

  insert into eliminations (
    club_id, tournament_id, tournament_player_id, eliminated_by_id,
    position, bounty_cents, recorded_by
  ) values (
    tp.club_id, tp.tournament_id, tp.id, p_by_tournament_player_id,
    v_pos, v_bounty, auth.uid()
  );

  return v_pos;
end;
$$;

-- Uitschakeling terugdraaien. Gebeurt vaker dan je denkt: verkeerde naam
-- aangeklikt terwijl er drie mensen tegelijk iets vragen.
create or replace function public.floor_undo_elimination(p_tournament_player_id uuid)
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

  if tp.status <> 'eliminated' then
    return;
  end if;

  -- Iedereen die ná hem afviel schuift een plaats op.
  update tournament_players
  set finish_position = finish_position - 1
  where tournament_id = tp.tournament_id
    and finish_position is not null
    and finish_position < tp.finish_position;

  delete from eliminations
  where tournament_player_id = tp.id
    and position = tp.finish_position;

  update tournament_players
  set status = 'active', finish_position = null, eliminated_at = null
  where id = tp.id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Tornooi afsluiten
-- ---------------------------------------------------------------------------
-- Wie nog aan tafel zit krijgt de bovenste plaatsen, op chipcount gesorteerd.
-- Daarna berekent finalize_tournament prijzengeld en punten.

create or replace function public.floor_finish_tournament(p_tournament_id uuid)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  t     tournaments%rowtype;
  r     record;
  v_pos int;
begin
  select * into t from tournaments where id = p_tournament_id;
  if not found then
    raise exception 'Tornooi bestaat niet';
  end if;

  if not public.is_service_context()
     and not public.has_club_role(t.club_id, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten' using errcode = 'insufficient_privilege';
  end if;

  select count(*) into v_pos
  from tournament_players
  where tournament_id = p_tournament_id and status in ('active', 'registered');

  for r in
    select id from tournament_players
    where tournament_id = p_tournament_id and status in ('active', 'registered')
    order by coalesce(chip_count, 0) asc, registered_at desc
  loop
    update tournament_players
    set status = 'eliminated', finish_position = v_pos, eliminated_at = coalesce(eliminated_at, now())
    where id = r.id;
    v_pos := v_pos - 1;
  end loop;

  update tournaments set ended_at = coalesce(ended_at, now()) where id = p_tournament_id;

  return public.finalize_tournament(p_tournament_id);
end;
$$;
