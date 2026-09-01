-- Pokerleague — een speler weer uit een tornooi halen
--
-- Er was tot nu één weg naar binnen en geen weg naar buiten. Voeg je aan de
-- deur de verkeerde man toe — twee mensen met dezelfde voornaam, of je tikt
-- door terwijl er iemand tegen je praat — dan staat hij er, met een inkoop in
-- het geldregister en straks een plaats in de uitslag. Wie dat probeerde recht
-- te zetten kwam bij "Uitschakelen" uit, want dat is de enige knop die op
-- weghalen lijkt. Daarmee word je eerste in een tornooi van één man, sta je op
-- de uitbetaallijst, en ben je nog steeds niet weg.
--
-- Vandaar `floor_remove_entry`: de deelname verdwijnt, met de inkoop erbij.
--
-- **Waarom dit mag en het geldregister toch klopt.** De regel was: nooit een
-- rij uit `buyins` halen, corrigeren doe je met een tegenboeking. Die regel
-- gaat over geld dat echt over de toog ging. Een deelname die er nooit had
-- mogen zijn is iets anders — er is niets betaald, er is niets terug te
-- betalen, en een tegenboeking van nul zou het register alleen langer maken.
-- Daarom is dit ook streng afgebakend: staat er méér dan de eerste inkoop, dan
-- gaat het niet door en moet de floor die inkopen eerst met de bestaande knop
-- terugdraaien. Zo blijft elke euro die ooit geboekt werd zichtbaar.
--
-- **En een tweede bug die hierbij bovenkwam.** `floor_undo_elimination`
-- verschoof de eindplaatsen de verkeerde kant op. Dat viel niet op zolang je
-- de laatste afvaller terugdraaide — dan is er niets te verschuiven — maar
-- draaide je er eentje terug van eerder op de avond, dan kregen twee spelers
-- dezelfde plaats en verdween er een. Zes spelers, drie afvallers (6, 5, 4),
-- de middelste terugdraaien: de vierde stond daarna op plaats 3, en bij het
-- afsluiten deelde hij die met iemand die nog aan tafel zat. Plaats bepaalt
-- prijzengeld én klassementspunten, dus dat is niet cosmetisch.
--
-- Het rekenwerk staat nu op één plek, `renumber_finish_positions`, en die telt
-- niet met plus en min maar herberekent de hele rij uit de volgorde waarin er
-- afgevallen is. Dat repareert meteen elke uitslag die al scheef stond.

-- ---------------------------------------------------------------------------
-- 1. De eindplaatsen, uit de feiten
-- ---------------------------------------------------------------------------
-- Wie als eerste afvalt wordt laatste. Met N deelnemers krijgt de eerste
-- afvaller plaats N, de volgende N-1, enzovoort. Actieve spelers hebben nog
-- geen plaats.
--
-- Vallen er twee op hetzelfde tijdstip af — dat gebeurt echt, `now()` staat
-- binnen één transactie stil — dan geeft de plaats die er al stond de
-- doorslag: wie een hoger nummer had, viel eerder. Zo blijft een volgorde die
-- ooit correct is vastgelegd behouden.

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
           row_number() over (
             order by tp.eliminated_at asc nulls last,
                      tp.finish_position desc nulls last,
                      tp.id asc
           ) as v_beurt
    from tournament_players tp
    where tp.tournament_id = p_tournament_id
      and tp.status = 'eliminated'
  )
  update tournament_players tp
  set finish_position = v_totaal - v.v_beurt + 1
  from volgorde v
  where tp.id = v.v_id
    and tp.finish_position is distinct from (v_totaal - v.v_beurt + 1);
end;
$$;

comment on function public.renumber_finish_positions(uuid) is
  'Herberekent de eindplaatsen van alle uitgeschakelde spelers uit de volgorde waarin ze afvielen. Zelfherstellend: een tornooi met een gat of een dubbele plaats staat er na één aanroep weer goed op.';

-- ---------------------------------------------------------------------------
-- 2. Uitschakeling terugdraaien — nu zonder rekenfout
-- ---------------------------------------------------------------------------

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

  delete from eliminations
  where tournament_player_id = tp.id
    and position = tp.finish_position;

  update tournament_players
  set status = 'active', finish_position = null, eliminated_at = null
  where id = tp.id;

  -- Iedereen die ná hem afviel schuift een plaats naar achter: er staat weer
  -- iemand meer aan tafel, dus wie na hem uitging werd niet zesde maar vijfde.
  perform public.renumber_finish_positions(tp.tournament_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Een inkoop terugdraaien houdt de plaatsen ook recht
-- ---------------------------------------------------------------------------
-- Een re-entry terugdraaien zet iemand terug op uitgeschakeld en rekende zijn
-- plaats zelf uit. Dat klopte, maar het is dezelfde som op een tweede plek.
-- Nu berekent hij hem één keer, hier.

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

-- ---------------------------------------------------------------------------
-- 4. De deelname weghalen
-- ---------------------------------------------------------------------------
-- Vier sloten, en elk ervan heeft een reden:
--
--   * Alleen staf van de club. Zelfde regel als bij toevoegen.
--   * Niet op een afgelopen tornooi. Daar liggen de uitslagen vast, staan er
--     punten in het klassement en is er geld verdeeld. Wie daar iets aan wil
--     veranderen hoort dat te merken, niet stilzwijgend gedaan te krijgen.
--   * Niet als er meer dan de eerste inkoop op zijn naam staat. Dan is er geld
--     geteld dat hier niet zomaar mag verdwijnen; draai die inkopen eerst
--     terug met de knop die daarvoor bestaat.
--   * Niet terwijl er een dealvoorstel op tafel ligt. Daar staan namen en
--     bedragen in die zouden gaan wijzen naar iemand die niet meer bestaat.
--
-- Wat er wél meegaat: de inkoop, de uitschakeling en de uitbetaalmarkering —
-- die hangen aan de deelname en verdwijnen met de rij. Wat blijft staan: de
-- speler zelf, en zijn lidmaatschap van de club. Iemand per ongeluk aan een
-- tornooi toevoegen is geen reden om hem uit het ledenbestand te gooien.

create or replace function public.floor_remove_entry(p_tournament_player_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  tp      tournament_players%rowtype;
  t       tournaments%rowtype;
  v_extra int;
begin
  select * into tp from tournament_players where id = p_tournament_player_id;
  if not found then
    raise exception 'Deelnemer bestaat niet';
  end if;

  if not public.is_service_context()
     and not public.has_club_role(tp.club_id, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten' using errcode = 'insufficient_privilege';
  end if;

  select * into t from tournaments where id = tp.tournament_id;

  if t.status in ('finished', 'cancelled') then
    raise exception 'Dit tornooi is afgelopen. Een deelname weghalen zou de uitslag veranderen.'
      using errcode = 'check_violation';
  end if;

  select count(*) into v_extra
  from buyins
  where tournament_player_id = tp.id
    and not is_void
    and kind <> 'buyin';

  if v_extra > 0 then
    raise exception 'Er staan nog % extra inkopen op deze speler. Draai die eerst terug.', v_extra
      using errcode = 'check_violation';
  end if;

  if exists (
    select 1 from tournament_deals d
    where d.tournament_id = tp.tournament_id and d.status = 'proposed'
  ) then
    raise exception 'Er ligt een dealvoorstel op tafel. Beslis daar eerst over.'
      using errcode = 'check_violation';
  end if;

  -- Zelfde vergrendeling als bij uitschakelen: twee toestellen die tegelijk
  -- aan de eindplaatsen rekenen, komen netjes na elkaar.
  perform 1 from tournaments where id = tp.tournament_id for update;

  -- Was hij vooraf ingeschreven, dan zette het toevoegen die inschrijving op
  -- ingetrokken. Halen we de deelname weg, dan hoort hij weer op de lijst van
  -- wie er verwacht wordt. Alleen wat bij het toevoegen is ingetrokken: een
  -- afzegging van eerder die week blijft een afzegging.
  update tournament_registrations
  set cancelled_at = null
  where tournament_id = tp.tournament_id
    and player_id = tp.player_id
    and cancelled_at is not null
    and cancelled_at >= tp.registered_at;

  -- De inkopen en de uitschakeling hangen er met `on delete cascade` aan.
  delete from tournament_players where id = tp.id;

  perform public.renumber_finish_positions(tp.tournament_id);

  -- Sloeg hij iemand eruit, dan wijst die uitschakeling nu naar niemand. De
  -- knock-outtellers halen we daarom opnieuw uit de feiten in plaats van ze
  -- bij te stellen: dan klopt het ook als er ooit iets anders scheef ging.
  update tournament_players x
  set bounties_won = (
    select count(*) from eliminations e where e.eliminated_by_id = x.id
  )
  where x.tournament_id = tp.tournament_id
    and x.bounties_won is distinct from (
      select count(*) from eliminations e where e.eliminated_by_id = x.id
    );
end;
$$;

comment on function public.floor_remove_entry(uuid) is
  'Haalt een deelname helemaal weg, inclusief de eerste inkoop. Voor iemand die per ongeluk werd toegevoegd. Weigert op een afgelopen tornooi, bij extra inkopen en bij een openstaand dealvoorstel.';

-- ---------------------------------------------------------------------------
-- 5. Rechten
-- ---------------------------------------------------------------------------
-- `renumber_finish_positions` krijgt geen grant: die wordt alleen van
-- binnenuit aangeroepen, en losse toegang tot een functie die eindplaatsen
-- herschrijft heeft niemand nodig.

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function public.floor_remove_entry(uuid) to authenticated;
    grant execute on function public.floor_undo_elimination(uuid) to authenticated;
    grant execute on function public.floor_undo_last_buyin(uuid) to authenticated;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 6. Wat er nu al scheef stond, rechtzetten
-- ---------------------------------------------------------------------------
-- Elk tornooi dat nog loopt, één keer door de hernummering. Afgelopen
-- tornooien blijven eraf: daar staan de uitslagen en de punten al vast, en die
-- horen niet te veranderen omdat er een migratie langskomt.

do $$
declare
  r record;
  v_n int := 0;
begin
  for r in
    select id from tournaments where status not in ('finished', 'cancelled')
  loop
    perform public.renumber_finish_positions(r.id);
    v_n := v_n + 1;
  end loop;

  raise notice 'Eindplaatsen nagerekend voor % lopende tornooien.', v_n;
end $$;
