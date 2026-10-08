-- Pokerleague — wie opnieuw inkoopt, blijft op zijn stoel
--
-- **Wat er nu gebeurt.** Een speler gaat blut. De floor schakelt hem uit, de
-- stoel komt vrij — terecht, want anders blijft een lege plaats bezet terwijl
-- er iemand aan de deur staat. Daarna koopt hij zich terug in en staat hij
-- zonder tafel en zonder stoel in de lijst, terwijl hij letterlijk nog op
-- diezelfde stoel zit. De floor moet hem dan opnieuw gaan seaten, en tot dat
-- gebeurt klopt de tafelindeling niet met de zaal.
--
-- Aan tafel gebeurt er namelijk niets: hij schuift zijn stoel niet achteruit,
-- hij legt geld neer en krijgt nieuwe fiches.
--
-- **Hoe dit het oplost.** Bij het uitschakelen onthouden we welke stoel het
-- was, naast het leegmaken. Koopt hij zich binnen dezelfde avond terug in, dan
-- gaat hij op die stoel terug — maar alleen als niemand anders er intussen is
-- gaan zitten. Is de plaats bezet, dan blijft hij ongeseat en ziet de floor
-- hem in de stoelsuggestie opduiken, zoals bij elke nieuwe speler. Dat is de
-- juiste uitkomst: twee mensen op één stoel zetten is erger dan één keer
-- opnieuw moeten seaten.
--
-- Bij een rechtstreekse rebuy verandert de status niet en blijft de stoel
-- sowieso staan. Dat werkte al; dit maakt de andere weg daaraan gelijk.

alter table tournament_players
  add column if not exists seat_before_exit  int,
  add column if not exists table_before_exit int;

comment on column tournament_players.seat_before_exit is
  'De stoel waar deze speler zat toen hij uitgeschakeld werd, zodat een re-entry hem terugzet op zijn eigen plaats als die nog vrij is.';

-- ---------------------------------------------------------------------------
-- 1. Bij het uitschakelen: stoel vrijgeven, maar onthouden welke het was
-- ---------------------------------------------------------------------------

create or replace function public.clear_seat_on_exit()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.status = 'eliminated' and old.status <> 'eliminated' then
    -- Eerst bewaren, dan pas vrijgeven. De volgorde is het hele punt.
    new.table_before_exit := old.table_no;
    new.seat_before_exit  := old.seat_no;
    new.table_no := null;
    new.seat_no  := null;
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Bij een re-entry: terug op dezelfde stoel, als die nog vrij is
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
  tp      tournament_players%rowtype;
  t       tournaments%rowtype;
  v_pot   int;
  v_fee   int;
  v_tafel int;
  v_stoel int;
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

  -- Geen slot op een verouderde telling: zie migratie 0060.

  if p_kind = 'addon' then
    v_pot := coalesce(t.addon_cents, t.buyin_cents);
    v_fee := coalesce(t.addon_fee_cents, 0);
  else
    v_pot := coalesce(t.rebuy_cents, t.buyin_cents);
    v_fee := coalesce(t.rebuy_fee_cents, t.fee_cents);
  end if;

  insert into buyins (
    club_id, tournament_id, tournament_player_id, player_id,
    kind, amount_cents, fee_cents, bounty_cents, recorded_by
  ) values (
    tp.club_id, tp.tournament_id, tp.id, tp.player_id,
    p_kind, v_pot, v_fee,
    case when t.bounty_mode = 'none' or p_kind = 'addon' then 0 else t.bounty_cents end,
    auth.uid()
  );

  -- Zijn oude plaats, als hij er een had en er niemand anders zit. Alleen bij
  -- een re-entry: bij een rebuy is hij nooit opgestaan en staat zijn stoel er
  -- gewoon nog.
  v_tafel := null;
  v_stoel := null;
  if p_kind = 'reentry'
     and tp.table_before_exit is not null and tp.seat_before_exit is not null then
    if not exists (
      select 1 from tournament_players x
      where x.tournament_id = tp.tournament_id
        and x.id <> tp.id
        and x.table_no = tp.table_before_exit
        and x.seat_no  = tp.seat_before_exit
    ) then
      v_tafel := tp.table_before_exit;
      v_stoel := tp.seat_before_exit;
    end if;
  end if;

  update tournament_players
  set status          = case when p_kind = 'reentry' then 'active' else status end,
      finish_position = case when p_kind = 'reentry' then null else finish_position end,
      eliminated_at   = case when p_kind = 'reentry' then null else eliminated_at end,
      table_no        = case when p_kind = 'reentry' and v_tafel is not null
                             then v_tafel else table_no end,
      seat_no         = case when p_kind = 'reentry' and v_stoel is not null
                             then v_stoel else seat_no end,
      -- Opgebruikt: hij zit weer, dus er valt niets meer terug te geven.
      table_before_exit = case when p_kind = 'reentry' then null else table_before_exit end,
      seat_before_exit  = case when p_kind = 'reentry' then null else seat_before_exit end,
      stack_before_reentry = case
                               when p_kind in ('reentry', 'rebuy') then chip_count
                               else stack_before_reentry
                             end,
      chip_count      = case
                          when p_kind in ('reentry', 'rebuy') then t.starting_stack
                          else coalesce(chip_count, 0) + coalesce(t.addon_stack, t.starting_stack)
                        end
  where id = tp.id;

  if p_kind = 'reentry' and tp.finish_position is not null then
    perform public.renumber_finish_positions(tp.tournament_id);
  end if;
end;
$$;

comment on function public.floor_rebuy(uuid, buyin_kind) is
  'Een nieuwe inkoop voor wie al meedeed. Rebuy en re-entry zetten de stapel op de startstapel zonder voorinschrijfbonus; een addon telt erbij op. Een re-entry zet de speler terug op zijn eigen stoel als die nog vrij is. Weigert nooit op basis van de laatst doorgegeven telling.';
