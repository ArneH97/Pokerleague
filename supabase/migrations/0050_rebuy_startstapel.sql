-- Pokerleague — een rebuy zet je terug op de startstapel
--
-- Tot nu telde een rebuy er een startstapel bíj: wie met 8.000 overbleef en
-- opnieuw inkocht, zat daarna aan 48.000. Bij Cutoff — en bij de meeste clubs
-- die met een rebuy werken — is de afspraak een andere: je koopt geen extra
-- chips, je koopt een nieuwe stapel. Je begint opnieuw op 40.000, wat er ook
-- nog voor je lag.
--
-- **En daarom telt de bonus van de voorinschrijving niet mee.** Wie zich
-- vooraf inschreef begon met 45.000: de startstapel plus 5.000 cadeau omdat
-- hij zijn plaats had vastgezet. Dat cadeau hoort bij het begin van de avond
-- en niet bij elke inkoop erna. Door hier op `starting_stack` te zetten en
-- niet op wat er bij de eerste inschrijving werd toegekend, valt de bonus er
-- vanzelf buiten — één keer, zoals bedoeld.
--
-- **Een rebuy weigert nu als iemand al meer heeft dan de startstapel.** Onder
-- de nieuwe afspraak zou zo'n rebuy zijn stapel namelijk *verkleinen*, en dat
-- is nooit wat de floor bedoelt als hij op een geldknop drukt. Een club die
-- rebuys ook boven de startstapel toestaat, heeft aan die knop toch niets:
-- niemand betaalt om chips in te leveren.
--
-- Een addon blijft optellen. Dat is het verschil tussen de twee: een addon is
-- een extra portie chips bovenop wat je hebt, een rebuy is een nieuwe start.
-- Een re-entry stond al goed — die geeft een verse startstapel aan iemand die
-- er af lag.
--
-- **Bijkomend rechtgezet: de eindplaatsen na een re-entry.** Dezelfde
-- rekenfout als in `floor_undo_elimination` (zie 0048) stond ook hier: wie
-- terugkwam in het veld liet de plaatsen van de anderen de verkeerde kant op
-- schuiven. Zeven deelnemers, twee afvallers op 7 en 6, de laatste komt terug
-- met een re-entry: de overblijvende afvaller kwam op plaats 5 terecht terwijl
-- hij van zeven deelnemers de laatste is. Ook hier rekent nu
-- `renumber_finish_positions` het opnieuw uit in plaats van er eentje af te
-- trekken.

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
  tp    tournament_players%rowtype;
  t     tournaments%rowtype;
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

  -- Een rebuy zet de stapel terug op de startstapel. Heeft iemand er al meer,
  -- dan zou dat hem chips kosten — dus dan gaat het niet door.
  if p_kind = 'rebuy' and coalesce(tp.chip_count, 0) > t.starting_stack then
    raise exception 'Deze speler heeft % chips, meer dan de startstapel van %. Een rebuy zou zijn stapel verkleinen.',
      tp.chip_count, t.starting_stack
      using errcode = 'check_violation';
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
      -- Wat er vóór deze inkoop lag, bewaren we nu ook bij een rebuy. Anders
      -- is de stapel niet meer terug te vinden als de floor zich vergist:
      -- vroeger kon `floor_undo_last_buyin` er gewoon een startstapel van
      -- aftrekken, maar een rebuy die de stapel overschrijft laat niets over
      -- om van af te trekken.
      stack_before_reentry = case
                               when p_kind in ('reentry', 'rebuy') then chip_count
                               else stack_before_reentry
                             end,
      chip_count      = case
                          -- Een verse stapel, zonder de bonus van de
                          -- voorinschrijving: die gold voor het begin.
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
  'Boekt een rebuy, re-entry of addon. Een rebuy en een re-entry zetten de stapel op de startstapel — zonder de bonus van de voorinschrijving, die telt maar één keer. Een addon telt erbij op. Een rebuy weigert als de speler al meer heeft dan de startstapel.';

comment on column public.tournament_players.stack_before_reentry is
  'De stapel van vlak vóór de laatste re-entry of rebuy, zodat een verkeerde klik terug te draaien is. Leeg zodra die inkoop teruggedraaid of afgehandeld is.';

-- ---------------------------------------------------------------------------
-- Een rebuy terugdraaien
-- ---------------------------------------------------------------------------
-- Zolang een rebuy chips bíj de stapel telde, was terugdraaien eenvoudig: er
-- weer een startstapel van aftrekken. Nu een rebuy de stapel overschrijft, is
-- er niets meer om van af te trekken — dus zetten we terug wat er stond.

create or replace function public.floor_undo_last_buyin(p_tournament_player_id uuid)
returns buyin_kind
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  tp tournament_players%rowtype;
  t  tournaments%rowtype;
  b  buyins%rowtype;
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
    -- laat de hernummering bepalen; die kijkt naar wanneer hij afviel en niet
    -- naar wat er toevallig nog in het veld staat.
    update tournament_players
    set status               = 'eliminated',
        eliminated_at        = coalesce(eliminated_at, now()),
        chip_count           = coalesce(stack_before_reentry, 0),
        stack_before_reentry = null
    where id = tp.id;

    perform public.renumber_finish_positions(tp.tournament_id);

  elsif b.kind = 'rebuy' then
    -- De stapel van vóór de rebuy terug. Staat die er niet — een rebuy van
    -- vóór deze migratie — dan valt hij terug op wat er vroeger gebeurde.
    update tournament_players
    set chip_count           = coalesce(stack_before_reentry,
                                        greatest(0, coalesce(chip_count, 0) - t.starting_stack)),
        stack_before_reentry = null
    where id = tp.id;

  else
    update tournament_players
    set chip_count = greatest(
      0,
      coalesce(chip_count, 0) - coalesce(t.addon_stack, t.starting_stack))
    where id = tp.id;
  end if;

  return b.kind;
end;
$$;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function public.floor_rebuy(uuid, buyin_kind) to authenticated;
    grant execute on function public.floor_undo_last_buyin(uuid) to authenticated;
  end if;
end $$;
