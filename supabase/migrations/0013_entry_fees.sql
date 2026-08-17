-- Pokerleague — per soort inkoop bepalen wat er naar de club gaat
--
-- Tot nu toe was er één clubbijdrage die gold voor de buy-in én voor elke
-- rebuy of re-entry, en een addon droeg nooit iets bij. Dat is één club-
-- afspraak hard in de software gegoten, en clubs doen dit niet allemaal
-- hetzelfde: de ene vraagt op een rebuy geen bijdrage omdat de speler al
-- betaald heeft, de andere net wel omdat hij opnieuw een stapel krijgt, en
-- op een addon zit soms een klein bedrag voor de zaal.
--
-- Vanaf hier stelt de club het per soort in. Elke kolom mag leeg blijven;
-- dan geldt wat er vroeger gebeurde, zodat bestaande tornooien niet van
-- prijs veranderen omdat er een migratie langskwam.

alter table tournaments
  add column if not exists rebuy_cents     int,
  add column if not exists rebuy_fee_cents int,
  add column if not exists addon_fee_cents int;

comment on column tournaments.rebuy_cents is
  'Wat een rebuy of re-entry in de prijzenpot legt. Leeg = hetzelfde als de buy-in.';
comment on column tournaments.rebuy_fee_cents is
  'Clubbijdrage op een rebuy of re-entry. Leeg = dezelfde bijdrage als bij de buy-in.';
comment on column tournaments.addon_fee_cents is
  'Clubbijdrage op een addon. Leeg = geen bijdrage.';

-- ---------------------------------------------------------------------------
-- floor_rebuy rekent met de juiste bedragen
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
  v_pot int;
  v_fee int;
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

  if p_kind = 'addon' then
    v_pot := coalesce(t.addon_cents, t.buyin_cents);
    v_fee := coalesce(t.addon_fee_cents, 0);
  else
    -- Rebuy én re-entry volgen dezelfde afspraak: je koopt opnieuw in.
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

  update tournament_players
  set status          = case when p_kind = 'reentry' then 'active' else status end,
      finish_position = case when p_kind = 'reentry' then null else finish_position end,
      eliminated_at   = case when p_kind = 'reentry' then null else eliminated_at end,
      stack_before_reentry = case when p_kind = 'reentry' then chip_count else stack_before_reentry end,
      chip_count      = case
                          when p_kind = 'reentry' then t.starting_stack
                          when p_kind = 'addon'
                            then coalesce(chip_count, 0) + coalesce(t.addon_stack, t.starting_stack)
                          else coalesce(chip_count, 0) + t.starting_stack
                        end
  where id = tp.id;

  if p_kind = 'reentry' and tp.finish_position is not null then
    update tournament_players
    set finish_position = finish_position - 1
    where tournament_id = tp.tournament_id
      and finish_position is not null
      and finish_position < tp.finish_position;
  end if;
end;
$$;
