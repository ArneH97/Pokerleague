-- Pokerleague — de komende levels bijstellen terwijl de avond loopt
--
-- Een tornooi loopt uit, of de finaletafel gaat te snel, of er moet een pauze
-- bij. Dan wil de floor aan de blindstructuur kunnen zonder eerst een nieuwe
-- structuur te bouwen en die om te wisselen — dat laatste kan trouwens niet
-- eens meer zodra de klok gelopen heeft, en met reden.
--
-- **Het probleem dat dit oplost, en waarom het niet triviaal is.** Een
-- blindstructuur is van de *club*, niet van de avond. "Blinds Sunday Opening"
-- hangt aan elke zondag. Wie er tijdens het spelen twee levels bij plakt omdat
-- het vanavond uitloopt, verandert daarmee stilzwijgend ook de structuur van
-- volgende week — en dat merkt niemand tot die week er is.
--
-- Vandaar: bij de eerste wijziging tijdens een avond krijgt die avond zijn
-- eigen kopie. De kopie draagt de naam van de avond, is identiek op het moment
-- van kopiëren (dus de klok staat waar hij stond), en vanaf dan is elke
-- aanpassing van deze avond alleen. Het clubsjabloon blijft ongemoeid.
--
-- **Wat er niet mag: het verleden.** Levels die al gespeeld zijn, liggen vast.
-- Hun duur is wat de klok gebruikt heeft om te komen waar hij staat; die
-- achteraf veranderen zou de klok verschuiven naar een moment dat de zaal niet
-- heeft meegemaakt. De functie weigert dat, en het scherm zet die rijen op
-- slot.
--
-- **Wat er wél mag:** het level waar je nu in zit en alles erna. Blinds, ante,
-- duur, pauzes ertussen, en levels achteraan bijzetten. Dat laatste heeft zijn
-- eigen knop, want "het loopt uit" is de meest voorkomende reden om hier te
-- zijn en dan wil je één tik, geen formulier.

-- ---------------------------------------------------------------------------
-- 1. Een eigen structuur voor deze avond
-- ---------------------------------------------------------------------------

create or replace function public.tournament_own_structure(p_tournament_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  t       tournaments%rowtype;
  v_bron  blind_structures%rowtype;
  v_nieuw uuid;
  v_gedeeld boolean;
begin
  select * into t from tournaments where id = p_tournament_id;
  if not found then
    raise exception 'Tornooi bestaat niet';
  end if;
  if t.structure_id is null then
    raise exception 'Deze avond heeft nog geen blindstructuur' using errcode = 'check_violation';
  end if;

  select * into v_bron from blind_structures where id = t.structure_id;

  -- Gedeeld als het een platformsjabloon is, of als er nog een andere avond
  -- aan hangt. Anders is hij al van deze avond alleen en hoeft er niets.
  v_gedeeld := v_bron.club_id is null
    or exists (
      select 1 from tournaments x
      where x.structure_id = t.structure_id and x.id <> p_tournament_id);

  if not v_gedeeld then
    return t.structure_id;
  end if;

  insert into blind_structures (club_id, name, description)
  values (
    t.club_id,
    left(v_bron.name || ' — ' || t.name, 120),
    'Eigen structuur van deze avond, gekopieerd tijdens het spelen. Wijzigingen hier raken het clubsjabloon niet.')
  returning id into v_nieuw;

  insert into blind_levels (structure_id, idx, is_break, label, small_blind, big_blind, ante, duration_s)
  select v_nieuw, l.idx, l.is_break, l.label, l.small_blind, l.big_blind, l.ante, l.duration_s
  from blind_levels l
  where l.structure_id = t.structure_id;

  update tournaments set structure_id = v_nieuw where id = p_tournament_id;

  return v_nieuw;
end;
$$;

comment on function public.tournament_own_structure(uuid) is
  'Geeft de blindstructuur van deze avond terug, en maakt er eerst een eigen kopie van als hij met andere avonden gedeeld wordt. Zo raakt bijstellen tijdens het spelen nooit het clubsjabloon.';

-- ---------------------------------------------------------------------------
-- 2. De komende levels vervangen
-- ---------------------------------------------------------------------------
-- `p_from_idx` is het eerste level dat vervangen wordt; alles daarvoor blijft
-- staan zoals het was. De lijst die je meegeeft komt daarachter, op volgorde.

create or replace function public.floor_set_upcoming_levels(
  p_tournament_id uuid,
  p_from_idx      int,
  p_levels        jsonb
)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  t       tournaments%rowtype;
  v_str   uuid;
  v_nu    int;
  v_lvl   jsonb;
  v_idx   int;
  v_n     int := 0;
begin
  select * into t from tournaments where id = p_tournament_id;
  if not found then
    raise exception 'Tornooi bestaat niet';
  end if;

  if not public.is_service_context()
     and not public.has_club_role(t.club_id, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten' using errcode = 'insufficient_privilege';
  end if;

  if t.status in ('finished', 'cancelled') then
    raise exception 'Dit tornooi is afgelopen' using errcode = 'check_violation';
  end if;

  if jsonb_typeof(p_levels) <> 'array' then
    raise exception 'Geef een lijst met levels mee' using errcode = 'check_violation';
  end if;

  -- Waar de klok werkelijk staat, niet wat er in het veld staat: dat laatste
  -- loopt achter zodra er geen floorscherm openstaat.
  select k.level_idx into v_nu from public.clock_position(p_tournament_id) k;
  v_nu := coalesce(v_nu, t.level_idx);

  if p_from_idx < v_nu then
    raise exception 'Level % is al gespeeld. Je kan vanaf het huidige level (%) bijstellen.',
      p_from_idx + 1, v_nu + 1
      using errcode = 'check_violation';
  end if;

  if p_from_idx = 0 and jsonb_array_length(p_levels) = 0 then
    raise exception 'Een structuur moet minstens één level bevatten' using errcode = 'check_violation';
  end if;

  v_str := public.tournament_own_structure(p_tournament_id);

  delete from blind_levels where structure_id = v_str and idx >= p_from_idx;

  v_idx := p_from_idx;
  for v_lvl in select * from jsonb_array_elements(p_levels) loop
    insert into blind_levels (
      structure_id, idx, is_break, label, small_blind, big_blind, ante, duration_s
    ) values (
      v_str,
      v_idx,
      coalesce((v_lvl ->> 'is_break')::boolean, false),
      nullif(trim(coalesce(v_lvl ->> 'label', '')), ''),
      greatest(0, coalesce((v_lvl ->> 'small_blind')::int, 0)),
      greatest(0, coalesce((v_lvl ->> 'big_blind')::int, 0)),
      greatest(0, coalesce((v_lvl ->> 'ante')::int, 0)),
      greatest(60, coalesce((v_lvl ->> 'duration_s')::int, 1200))
    );
    v_idx := v_idx + 1;
    v_n := v_n + 1;
  end loop;

  return v_n;
end;
$$;

comment on function public.floor_set_upcoming_levels(uuid, int, jsonb) is
  'Vervangt de levels vanaf p_from_idx door de meegegeven lijst. Levels die al gespeeld zijn blijven onaangeroerd. Maakt zo nodig eerst een eigen structuur voor deze avond, zodat het clubsjabloon niet verandert.';

-- ---------------------------------------------------------------------------
-- 3. Er eentje bijzetten omdat het uitloopt
-- ---------------------------------------------------------------------------
-- Eén tik, want dit is de reden waarom je hier bent. Het nieuwe level volgt de
-- sprong van de laatste twee: gingen de blinds van 4.000 naar 6.000, dan wordt
-- de volgende 9.000. Is er maar één level, dan verdubbelt hij. Alles wordt
-- afgerond op iets wat je met fiches kan betalen.

create or replace function public.floor_append_level(
  p_tournament_id uuid,
  p_is_break      boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  t        tournaments%rowtype;
  v_str    uuid;
  v_laatste blind_levels%rowtype;
  v_voor   blind_levels%rowtype;
  v_bb     int;
  v_sb     int;
  v_ante   int;
  v_factor numeric := 1.5;
  v_idx    int;
begin
  select * into t from tournaments where id = p_tournament_id;
  if not found then
    raise exception 'Tornooi bestaat niet';
  end if;

  if not public.is_service_context()
     and not public.has_club_role(t.club_id, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten' using errcode = 'insufficient_privilege';
  end if;

  if t.status in ('finished', 'cancelled') then
    raise exception 'Dit tornooi is afgelopen' using errcode = 'check_violation';
  end if;

  v_str := public.tournament_own_structure(p_tournament_id);

  select * into v_laatste from blind_levels
  where structure_id = v_str and not is_break order by idx desc limit 1;

  if not found then
    raise exception 'Deze structuur heeft nog geen speelniveau om op verder te bouwen'
      using errcode = 'check_violation';
  end if;

  select * into v_voor from blind_levels
  where structure_id = v_str and not is_break and idx < v_laatste.idx
  order by idx desc limit 1;

  if found and v_voor.big_blind > 0 then
    v_factor := greatest(1.2, least(2.0, v_laatste.big_blind::numeric / v_voor.big_blind));
  else
    v_factor := 2.0;
  end if;

  -- Afronden op iets wat aan tafel te betalen is: honderdtallen zolang het
  -- klein is, daarna grovere stappen.
  v_bb := (round((v_laatste.big_blind * v_factor)
             / greatest(100, power(10, floor(log(greatest(10, v_laatste.big_blind * v_factor))) - 1)))
           * greatest(100, power(10, floor(log(greatest(10, v_laatste.big_blind * v_factor))) - 1)))::int;
  v_bb := greatest(v_laatste.big_blind + 100, v_bb);
  v_sb := (v_bb / 2)::int;
  v_ante := case when v_laatste.ante > 0 then v_bb else 0 end;

  select coalesce(max(idx), -1) + 1 into v_idx from blind_levels where structure_id = v_str;

  insert into blind_levels (structure_id, idx, is_break, label, small_blind, big_blind, ante, duration_s)
  values (
    v_str, v_idx, p_is_break,
    case when p_is_break then 'Pauze' else null end,
    case when p_is_break then 0 else v_sb end,
    case when p_is_break then 0 else v_bb end,
    case when p_is_break then 0 else v_ante end,
    case when p_is_break then 600 else v_laatste.duration_s end
  );

  return jsonb_build_object(
    'idx', v_idx, 'small_blind', case when p_is_break then 0 else v_sb end,
    'big_blind', case when p_is_break then 0 else v_bb end,
    'is_break', p_is_break);
end;
$$;

comment on function public.floor_append_level(uuid, boolean) is
  'Zet er achteraan één level of één pauze bij, in het verlengde van de sprong die de structuur al maakte. Voor een avond die uitloopt.';

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function public.tournament_own_structure(uuid)                    to authenticated;
    grant execute on function public.floor_set_upcoming_levels(uuid, int, jsonb)       to authenticated;
    grant execute on function public.floor_append_level(uuid, boolean)                 to authenticated;
  end if;
end $$;
