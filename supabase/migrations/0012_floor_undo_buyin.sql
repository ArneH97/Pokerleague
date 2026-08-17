-- Pokerleague — een verkeerd geboekte inkoop terugdraaien
--
-- Aanleiding: de knoppen voor rebuy, addon en uitschakelen staan naast
-- elkaar op hetzelfde rijtje. Een uitschakeling was al terug te draaien, een
-- inkoop niet — en dat is nu net de klik die geld kost. Eén misser en er
-- staat twintig euro extra in de prijzenpot die niemand betaald heeft, en de
-- uitbetaling aan het eind van de avond klopt niet meer.
--
-- Geen rij verwijderen maar op is_void zetten. Het geldregister is de
-- verantwoording tegenover het gedoogbeleid: daar hoort een fout in te staan
-- mét de reden waarom hij is rechtgezet, niet uit te verdwijnen. De teller
-- van sync_entry_counters kijkt al naar `not is_void`, dus die corrigeert
-- zichzelf zodra de rij geschrapt is.

-- ---------------------------------------------------------------------------
-- 1. Onthouden wat er op tafel lag vóór een re-entry
-- ---------------------------------------------------------------------------
-- Een re-entry overschrijft de chipcount met een verse startstack. Zonder de
-- oude waarde ergens te bewaren is terugdraaien verlieslatend: je krijgt de
-- speler wel terug op zijn plaats, maar zijn stapel van vóór de bust is weg.

alter table tournament_players
  add column if not exists stack_before_reentry int;

comment on column tournament_players.stack_before_reentry is
  'De chipcount van vlak voor de laatste re-entry. Enkel bedoeld om die re-entry ongedaan te kunnen maken.';

-- ---------------------------------------------------------------------------
-- 2. floor_rebuy bewaart die waarde
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
    -- Elke inkoop gaat voluit naar de prijzenpot. Een addon kan een ander
    -- bedrag hebben dan de buy-in; staat dat niet ingesteld, dan geldt de
    -- buy-in. Een rebuy en een re-entry kosten altijd de buy-in.
    case when p_kind = 'addon' then coalesce(t.addon_cents, t.buyin_cents) else t.buyin_cents end,
    -- De clubbijdrage betaal je één keer, bij je eerste inkoop van de avond.
    -- Bij een re-entry stap je opnieuw in en betaal je hem opnieuw; bij een
    -- addon niet, want je zat er al.
    case when p_kind = 'addon' then 0 else t.fee_cents end,
    case when t.bounty_mode = 'none' or p_kind = 'addon' then 0 else t.bounty_cents end,
    auth.uid()
  );

  update tournament_players
  set status          = case when p_kind = 'reentry' then 'active' else status end,
      finish_position = case when p_kind = 'reentry' then null else finish_position end,
      eliminated_at   = case when p_kind = 'reentry' then null else eliminated_at end,
      -- Bewaren wat er lag, zodat de re-entry terug te draaien is.
      stack_before_reentry = case when p_kind = 'reentry' then chip_count else stack_before_reentry end,
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
-- 3. De laatste inkoop terugdraaien
-- ---------------------------------------------------------------------------
-- Draait alleen de láátste terug, en enkel een rebuy, addon of re-entry. De
-- eerste inkoop van een speler hoort bij zijn deelname: die verwijder je niet
-- los, dan zou er iemand aan tafel zitten zonder betaald te hebben.

create or replace function public.floor_undo_last_buyin(p_tournament_player_id uuid)
returns buyin_kind
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  tp    tournament_players%rowtype;
  t     tournaments%rowtype;
  b     buyins%rowtype;
  v_pos int;
begin
  select * into tp from tournament_players where id = p_tournament_player_id;
  if not found then
    raise exception 'Deelnemer bestaat niet';
  end if;

  if not public.is_service_context()
     and not public.has_club_role(tp.club_id, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten' using errcode = 'insufficient_privilege';
  end if;

  select * into b
  from buyins
  where tournament_player_id = tp.id
    and not is_void
    and kind <> 'buyin'
  order by occurred_at desc, id desc
  limit 1;

  if not found then
    raise exception 'Er is geen inkoop om terug te draaien'
      using errcode = 'check_violation';
  end if;

  select * into t from tournaments where id = tp.tournament_id;

  update buyins
  set is_void = true,
      voided_reason = 'teruggedraaid door de floor'
  where id = b.id;

  if b.kind = 'reentry' then
    -- Terug naar uitgeschakeld, met de stapel van vóór de re-entry. De plaats
    -- laten we opnieuw berekenen in plaats van de oude te hergebruiken: er
    -- kan ondertussen iemand anders afgevallen zijn.
    select count(*) into v_pos
    from tournament_players
    where tournament_id = tp.tournament_id
      and status in ('active', 'registered')
      and id <> tp.id;

    update tournament_players
    set status               = 'eliminated',
        finish_position      = v_pos + 1,
        eliminated_at        = coalesce(eliminated_at, now()),
        chip_count           = coalesce(stack_before_reentry, 0),
        stack_before_reentry = null
    where id = tp.id;
  else
    update tournament_players
    set chip_count = greatest(
      0,
      coalesce(chip_count, 0) - case
        when b.kind = 'addon' then coalesce(t.addon_stack, t.starting_stack)
        else t.starting_stack
      end)
    where id = tp.id;
  end if;

  return b.kind;
end;
$$;
