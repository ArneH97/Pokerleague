-- Pokerleague — migraties 0048 tot en met 0059, in volgorde.


-- ===========================================================================
-- 0048_speler_verwijderen.sql
-- ===========================================================================
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

-- ===========================================================================
-- 0049_tornooi_bewerken.sql
-- ===========================================================================
-- Pokerleague — een tornooi bijstellen nadat het is aangemaakt
--
-- Tot nu was aanmaken een eenrichtingsstraat: je koos de blindstructuur, de
-- inleg en het prijzenschema in het aanmaakscherm, en daarna kon er niets meer
-- bij. Eén tikfout in de buy-in, of een structuur die pas ná het aanmaken werd
-- gebouwd, en er moest SQL aan te pas komen.
--
-- **Waarom één functie met een jsonb en geen achttien parameters.** Een
-- tornooi heeft twintig instelbare velden en er komen er nog bij. Een functie
-- met achttien argumenten moet bij elk nieuw veld opnieuw gedropt en
-- aangemaakt worden, en elke oproeper moet mee. Met een patch stuurt het
-- scherm alleen wat er veranderde, en blijft de rest onaangeroerd.
--
-- Dat kan hier veilig omdat de patch niet rechtstreeks in de tabel gaat:
-- `jsonb_populate_record` legt hem eerst over de bestaande rij, en daarna
-- schrijven we uitsluitend de kolommen die hieronder met naam genoemd staan.
-- Een sleutel die daar niet bij hoort — `club_id`, `status`, `level_idx` —
-- geeft een foutmelding in plaats van dat hij stilletjes genegeerd wordt. Wie
-- zich vertikt in een veldnaam hoort dat te merken.
--
-- **Wat er niet meer mag wijzigen, en waarom.**
--
--   * De blindstructuur, zodra de klok gelopen heeft. Een tornooi onthoudt op
--     welk levelnummer het staat, niet welke blinds daarbij horen. Verwissel
--     je de structuur halverwege, dan springt de zaal naar level 7 van de
--     nieuwe structuur — met andere blinds dan wat er op tafel ligt.
--   * Alles behalve de naam, de notitie en de zichtbaarheid, zodra de avond
--     afgelopen is. Daar zijn de uitslagen berekend, de punten toegekend en
--     het geld verdeeld. Wie dáár nog aan wil rekenen, hoort dat niet via een
--     bewerkscherm te doen.
--
-- **Wat wél mag terwijl er al spelers zitten.** De inleg bijstellen. Dat
-- klinkt gevaarlijk en is het niet: elke inkoop staat als eigen rij in
-- `buyins` met het bedrag van dát moment. De prijzenpot is de som van die
-- rijen, niet een herberekening achteraf. Wie om acht uur merkt dat er € 35
-- staat in plaats van € 40, zet het recht voor de rest van de avond zonder dat
-- de eerste vier spelers ineens iets anders betaald blijken te hebben.

create or replace function public.update_tournament(
  p_tournament_id uuid,
  p_patch         jsonb
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  t       tournaments%rowtype;
  v_new   tournaments%rowtype;
  v_sleutel text;
  v_klok  boolean;

  -- Wat een mens mag bijstellen. Alles wat hier niet in staat, hoort bij de
  -- floor (de klok, de status) of bij de databank (de club, het id).
  c_toegestaan constant text[] := array[
    'name', 'notes', 'scheduled_at', 'player_visibility',
    'season_id', 'structure_id', 'payout_template_id',
    'buyin_cents', 'fee_cents', 'rebuy_cents', 'rebuy_fee_cents',
    'addon_cents', 'addon_fee_cents', 'addon_stack',
    'bounty_mode', 'bounty_cents',
    'starting_stack', 'max_reentries', 'late_reg_level',
    'prereg_bonus_stack'
  ];
  -- En hiervan blijft er ná afloop nog iets over: een verkeerd gespelde naam
  -- mag je altijd rechtzetten.
  c_na_afloop constant text[] := array['name', 'notes', 'player_visibility'];
begin
  select * into t from tournaments where id = p_tournament_id;
  if not found then
    raise exception 'Tornooi bestaat niet';
  end if;

  if not public.is_service_context()
     and not public.has_club_role(t.club_id, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten om dit tornooi te wijzigen'
      using errcode = 'insufficient_privilege';
  end if;

  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then
    raise exception 'Geef een object mee met de velden die moeten wijzigen'
      using errcode = 'check_violation';
  end if;

  for v_sleutel in select jsonb_object_keys(p_patch) loop
    if not (v_sleutel = any(c_toegestaan)) then
      raise exception 'Het veld "%" kan hier niet gewijzigd worden.', v_sleutel
        using errcode = 'check_violation';
    end if;
    if t.status in ('finished', 'cancelled') and not (v_sleutel = any(c_na_afloop)) then
      raise exception 'Deze avond is afgelopen. Alleen de naam en de zichtbaarheid kunnen nog wijzigen, "%" niet.', v_sleutel
        using errcode = 'check_violation';
    end if;
  end loop;

  -- De patch over de bestaande rij leggen. Wat niet in de patch staat, houdt
  -- zijn huidige waarde.
  v_new := jsonb_populate_record(t, p_patch);

  v_klok := t.started_at is not null or t.level_idx > 0;
  if v_new.structure_id is distinct from t.structure_id and v_klok then
    raise exception 'De klok van deze avond heeft al gelopen. De blindstructuur wisselen zou de zaal naar een ander level sturen dan wat er op tafel ligt.'
      using errcode = 'check_violation';
  end if;

  if v_new.starting_stack <= 0 then
    raise exception 'De startstapel moet groter zijn dan nul' using errcode = 'check_violation';
  end if;

  if least(
       v_new.buyin_cents, v_new.fee_cents, v_new.bounty_cents,
       coalesce(v_new.rebuy_cents, 0), coalesce(v_new.rebuy_fee_cents, 0),
       coalesce(v_new.addon_cents, 0), coalesce(v_new.addon_fee_cents, 0),
       v_new.prereg_bonus_stack, v_new.max_reentries
     ) < 0 then
    raise exception 'Bedragen en aantallen kunnen niet negatief zijn' using errcode = 'check_violation';
  end if;

  update tournaments set
    name               = v_new.name,
    notes              = v_new.notes,
    scheduled_at       = v_new.scheduled_at,
    player_visibility  = v_new.player_visibility,
    season_id          = v_new.season_id,
    structure_id       = v_new.structure_id,
    payout_template_id = v_new.payout_template_id,
    buyin_cents        = v_new.buyin_cents,
    fee_cents          = v_new.fee_cents,
    rebuy_cents        = v_new.rebuy_cents,
    rebuy_fee_cents    = v_new.rebuy_fee_cents,
    addon_cents        = v_new.addon_cents,
    addon_fee_cents    = v_new.addon_fee_cents,
    addon_stack        = v_new.addon_stack,
    bounty_mode        = v_new.bounty_mode,
    bounty_cents       = v_new.bounty_cents,
    starting_stack     = v_new.starting_stack,
    max_reentries      = v_new.max_reentries,
    late_reg_level     = v_new.late_reg_level,
    prereg_bonus_stack = v_new.prereg_bonus_stack
  where id = p_tournament_id;
end;
$$;

comment on function public.update_tournament(uuid, jsonb) is
  'Stelt een bestaand tornooi bij. Alleen staf van de club; alleen de velden uit de witte lijst; de blindstructuur niet meer zodra de klok gelopen heeft; na afloop enkel nog naam, notitie en zichtbaarheid.';

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function public.update_tournament(uuid, jsonb) to authenticated;
  end if;
end $$;

-- ===========================================================================
-- 0050_rebuy_startstapel.sql
-- ===========================================================================
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

-- ===========================================================================
-- 0051_chips_in_spel.sql
-- ===========================================================================
-- Pokerleague — hoeveel chips er écht in spel zijn
--
-- Op het zaalscherm en in het dealpaneel staat "chips in spel". Dat getal werd
-- geraden uit de tellers: elke inkoop, rebuy en re-entry één startstapel, elke
-- addon een addonstapel. Sinds vanmiddag klopt dat op twee punten niet meer.
--
--   * **De bonus van de voorinschrijving stond er nooit in.** Wie vooraf
--     inschrijft begint met 45.000 en niet met 40.000. Met twintig van die
--     spelers zit er 100.000 aan chips op tafel die het scherm niet kent — en
--     dan lijkt het alsof er een fiches-la verdwenen is terwijl alles klopt.
--   * **Een rebuy legt niet langer een startstapel bíj.** Hij zet de stapel op
--     de startstapel (zie 0050). Wie met 8.000 opnieuw inkocht, brengt er dus
--     32.000 bij en geen 40.000.
--
-- Raden is hier ook niet nodig, want elke inkoop staat al als eigen rij in het
-- geldregister. Er ontbrak alleen een kolom: hoeveel chips die inkoop op tafel
-- legde. Vanaf nu staat dat erbij, en is "chips in spel" gewoon de som van die
-- kolom — even hard als de prijzenpot, en met dezelfde herkomst.
--
-- **Waarom een trigger en niet een regel in elke functie.** De twee functies
-- die inkopen boeken zijn de drukste van de avond en samen driehonderd regels.
-- Ze allebei herschrijven om er één berekening in te weven, daags voor een
-- opening, is precies het soort verandering waarvan je 's nachts wakker ligt.
-- Een trigger op `buyins` heeft alles wat hij nodig heeft — het tornooi en de
-- stapel van de speler op dat moment — en laat die functies met rust.
--
-- Dat werkt omdat beide functies dezelfde volgorde aanhouden. Bij een eerste
-- inkoop bestaat de deelnemersrij al, mét de bonus erin; bij een rebuy is de
-- stapel nog die van vóór de inkoop. Precies wat er nodig is.

alter table buyins
  add column if not exists chips_delta int;

comment on column public.buyins.chips_delta is
  'Hoeveel chips deze inkoop op tafel legde. Bij een eerste inkoop de startstapel plus een eventuele bonus voor voorinschrijving; bij een rebuy het verschil met wat de speler nog had; bij een re-entry een verse startstapel; bij een addon de addonstapel. De som over alle niet-geschrapte rijen is het aantal chips in spel.';

-- ---------------------------------------------------------------------------
-- 1. De berekening, één keer, op de rand van de tabel
-- ---------------------------------------------------------------------------

create or replace function public.set_buyin_chip_delta()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  t  tournaments%rowtype;
  tp tournament_players%rowtype;
begin
  -- Wie het zelf meegeeft, weet het beter. Laat staan.
  if new.chips_delta is not null then
    return new;
  end if;

  select * into t  from tournaments        where id = new.tournament_id;
  select * into tp from tournament_players where id = new.tournament_player_id;

  new.chips_delta := case new.kind
    -- De eerste inkoop: de stapel die de speler zojuist kreeg, bonus en al.
    when 'buyin'   then coalesce(tp.chip_count, t.starting_stack)
    -- Een addon is een extra portie bovenop wat er ligt.
    when 'addon'   then coalesce(t.addon_stack, t.starting_stack)
    -- Een rebuy vervangt de stapel: er komt bij wat het verschil is met wat
    -- de speler nog had liggen.
    when 'rebuy'   then greatest(0, t.starting_stack - coalesce(tp.chip_count, 0))
    -- Een re-entry: de speler lag eruit en zijn chips telden al niet meer mee,
    -- dus dit is een volle verse stapel.
    else t.starting_stack
  end;

  return new;
end;
$$;

drop trigger if exists buyins_chip_delta on buyins;
create trigger buyins_chip_delta
  before insert on buyins
  for each row execute function public.set_buyin_chip_delta();

-- ---------------------------------------------------------------------------
-- 2. Wat er al geboekt is
-- ---------------------------------------------------------------------------
-- Bestaande rijen krijgen wat er destijds gebeurde, en niet wat er vandaag zou
-- gebeuren: tot 0050 legde een rebuy wél een volle startstapel bij. Een oude
-- avond hoort achteraf niet van cijfers te veranderen.

update buyins b
set chips_delta = case b.kind
  when 'addon' then coalesce(t.addon_stack, t.starting_stack)
  else t.starting_stack
end
from tournaments t
where t.id = b.tournament_id
  and b.chips_delta is null;

-- ---------------------------------------------------------------------------
-- 3. Het getal zelf
-- ---------------------------------------------------------------------------
-- Voor de zaalklok en het dealpaneel. Leesbaar voor wie het tornooi mag zien —
-- dit is een totaal en geen bedrag, en het staat op het scherm in de zaal.

create or replace function public.chips_in_play(p_tournament_id uuid)
returns int
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(sum(b.chips_delta), 0)::int
  from buyins b
  where b.tournament_id = p_tournament_id
    and not b.is_void
    and public.can_view_tournament(p_tournament_id);
$$;

comment on function public.chips_in_play(uuid) is
  'Hoeveel chips er in spel horen te zijn, uit het geldregister en niet uit wat spelers doorgeven. IJkpunt bij het tellen aan de finaletafel.';

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function public.chips_in_play(uuid) to authenticated;
  end if;
  if exists (select 1 from pg_roles where rolname = 'anon') then
    grant execute on function public.chips_in_play(uuid) to anon;
  end if;
end $$;

-- ===========================================================================
-- 0052_stapels_bevriezen.sql
-- ===========================================================================
-- Pokerleague — de ingave van spelers bevriezen, en zien wie wat intikte
--
-- Aan het einde van de avond komt het moment waarop de chipcounts ineens
-- zwaar wegen: daar hangt een deal aan, of de bepaling van wie er in het geld
-- valt. Op dat moment wil de floor rondgaan, de stapels tellen en ze zelf
-- invullen — en wil hij niet dat er ondertussen nog iemand op zijn gsm een
-- getal verzet. Vandaar een grendel.
--
-- **De grendel geldt alleen voor spelers.** De floor blijft invullen, want dat
-- is precies wat hij aan het doen is. Het is geen slot op de tabel maar een
-- slot op één weg ernaartoe.
--
-- **En hij staat op de avond, niet op de speler.** Bevriezen is een moment in
-- het verloop van het tornooi ("we gaan tellen"), geen eigenschap van iemand.
-- We bewaren het tijdstip en niet enkel ja/nee, zodat het scherm kan zeggen
-- sinds wanneer — en zodat je achteraf ziet dat er geteld is vóór de deal.
--
-- **Wat er al werd bijgehouden.** Elke wijziging van een chipcount stempelt al
-- wie hem zette (`floor` of `player`) en wanneer. Dat stond nergens op het
-- scherm. Het hoort er wel: een stapel die de speler zelf twintig minuten
-- geleden intikte, is iets anders dan eentje die de floor net geteld heeft, en
-- dat verschil bepaalt of je gaat rondlopen of niet.

alter table tournaments
  add column if not exists counts_frozen_at timestamptz;

comment on column public.tournaments.counts_frozen_at is
  'Sinds wanneer spelers hun eigen chipcount niet meer mogen wijzigen. Leeg = ingave staat open. De floor blijft altijd invullen.';

-- ---------------------------------------------------------------------------
-- 1. De bewaking van de chipcount kent de grendel
-- ---------------------------------------------------------------------------

create or replace function public.guard_player_chip_update()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_is_staff boolean;
  v_is_self  boolean;
  v_frozen   timestamptz;
begin
  if public.is_service_context() then
    return new;
  end if;

  v_is_staff := public.has_club_role(new.club_id, array['owner','admin','floor']::club_role[]);
  if v_is_staff then
    if new.chip_count is distinct from old.chip_count then
      new.chip_count_updated_at := now();
      new.chip_count_by := 'floor';
    end if;
    return new;
  end if;

  select exists (
    select 1 from players p
    where p.id = new.player_id and p.auth_user_id = auth.uid()
  ) into v_is_self;

  if not v_is_self then
    raise exception 'Geen rechten om deze deelnemer bij te werken'
      using errcode = 'insufficient_privilege';
  end if;

  if old.status <> 'active' then
    raise exception 'Je kan geen stack meer ingeven: je bent niet meer actief in dit tornooi'
      using errcode = 'check_violation';
  end if;

  -- De grendel. Alleen voor de speler zelf; de floor is hierboven al langs.
  select t.counts_frozen_at into v_frozen
  from tournaments t where t.id = new.tournament_id;

  if v_frozen is not null and new.chip_count is distinct from old.chip_count then
    raise exception 'De floor is de stapels aan het tellen. Je kan je aantal nu niet wijzigen.'
      using errcode = 'check_violation';
  end if;

  -- Alles behalve het chipaantal moet gelijk blijven.
  if (new.status, new.table_no, new.seat_no, new.finish_position,
      new.reentries_used, new.rebuys_used, new.addons_used, new.bounties_won,
      new.player_id, new.tournament_id, new.club_id)
     is distinct from
     (old.status, old.table_no, old.seat_no, old.finish_position,
      old.reentries_used, old.rebuys_used, old.addons_used, old.bounties_won,
      old.player_id, old.tournament_id, old.club_id)
  then
    raise exception 'Je kan alleen je eigen chipaantal aanpassen'
      using errcode = 'insufficient_privilege';
  end if;

  if new.chip_count is not null and (new.chip_count < 0 or new.chip_count > 1000000000) then
    raise exception 'Onmogelijk chipaantal' using errcode = 'check_violation';
  end if;

  new.chip_count_updated_at := now();
  new.chip_count_by := 'player';
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. De knop
-- ---------------------------------------------------------------------------

create or replace function public.floor_freeze_counts(
  p_tournament_id uuid,
  p_frozen        boolean
)
returns timestamptz
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  t      tournaments%rowtype;
  v_when timestamptz;
begin
  select * into t from tournaments where id = p_tournament_id;
  if not found then
    raise exception 'Tornooi bestaat niet';
  end if;

  if not public.is_service_context()
     and not public.has_club_role(t.club_id, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten' using errcode = 'insufficient_privilege';
  end if;

  -- Nog eens bevriezen terwijl het al vast staat, laat het tijdstip staan:
  -- anders verspringt "sinds 14 minuten" naar "sinds nu" omdat iemand twee
  -- keer klikte.
  v_when := case
              when not p_frozen then null
              else coalesce(t.counts_frozen_at, now())
            end;

  update tournaments set counts_frozen_at = v_when where id = p_tournament_id;
  return v_when;
end;
$$;

comment on function public.floor_freeze_counts(uuid, boolean) is
  'Zet de ingave van chipcounts door spelers op slot, of geeft ze weer vrij. De floor kan altijd invullen. Geeft het tijdstip terug waarop de grendel dichtging.';

-- ---------------------------------------------------------------------------
-- 3. De spelerskant weet het ook
-- ---------------------------------------------------------------------------
-- Zonder dit staat er op de gsm van de speler een invulveld dat bij het
-- opslaan een foutmelding geeft. Beter is een veld dat op slot staat met de
-- reden erbij.

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
  my_chips             int,
  my_chips_by          text,
  my_chips_at          timestamptz,
  counts_frozen        boolean,
  players_left         int,
  entries              int,
  avg_stack            int,
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
    m.chip_count,
    m.chip_count_by::text,
    m.chip_count_updated_at,
    t.counts_frozen_at is not null,
    (select count(*)::int from tournament_players x
      where x.tournament_id = t.id and x.status in ('active','registered')),
    (select count(*)::int from tournament_players x where x.tournament_id = t.id),
    (public.chips_in_play(t.id) / greatest(1, (
       select count(*)::int from tournament_players x
       where x.tournament_id = t.id and x.status in ('active','registered'))))::int,
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
    grant execute on function public.floor_freeze_counts(uuid, boolean) to authenticated;
    grant execute on function public.my_live_tournaments() to authenticated;
  end if;
end $$;

-- ===========================================================================
-- 0053_mijn_tafel.sql
-- ===========================================================================
-- Pokerleague — wat een speler aan tafel echt wil weten
--
-- Op de spelerspagina stond tot nu: mijn stapel, het gemiddelde, hoeveel
-- spelers er over zijn en de prijzenpot. Vier getallen die geen van alle de
-- vraag beantwoorden die iemand aan tafel stelt: *hoe sta ik ervoor?*
--
-- Aan een pokertafel wordt die vraag in big blinds gesteld en niet in chips.
-- 54.000 zegt niets — 27 big blinds zegt "je hebt nog ruimte", 9 big blinds
-- zegt "je moet iets gaan doen". Datzelfde geldt voor het gemiddelde: het is
-- pas een ijkpunt als je het in dezelfde eenheid kan lezen als je eigen
-- stapel.
--
-- Daar komt bij: waar sta ik in het veld, en hoe ver is het geld nog? Dat
-- laatste is de reden dat mensen bij een bubbel anders gaan spelen, en het
-- staat nu nergens.
--
-- **Waarom de plaats een slag om de arm krijgt.** De rangschikking komt uit de
-- chipcounts, en die zijn onvolledig: op een gewone avond vult niet iedereen
-- ze in. Een "3de van 14" die eigenlijk op zes ingevulde stapels berust, is
-- een verzonnen zekerheid. Vandaar dat de functie er twee getallen bij geeft —
-- hoeveel stapels er meetellen — zodat het scherm eerlijk kan zijn over wat
-- het weet. Wie zelf niets invulde, krijgt geen plaats; die kan hem verdienen
-- door zijn stapel in te geven.
--
-- **De blinds tijdens een pauze.** Dan telt het eerstvolgende speelniveau,
-- niet nul. Anders staat er midden in de pauze "je hebt oneindig veel big
-- blinds", en dat is het moment waarop iemand zijn stapel juist wil inschatten
-- voor de volgende ronde.

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
  -- Waar de klok staat, in de taal van de zaal.
  level_label          text,
  is_break             boolean,
  small_blind          int,
  big_blind            int,
  ante                 int,
  next_big_blind       int,
  -- Mijn stapel, en wat er over de ingave bekend is.
  my_chips             int,
  my_chips_by          text,
  my_chips_at          timestamptz,
  counts_frozen        boolean,
  -- Het veld.
  players_left         int,
  entries              int,
  avg_stack            int,
  chips_in_play        int,
  -- Waar ik sta. Null als ik zelf niets invulde.
  my_rank              int,
  ranked_players       int,
  -- Hoe ver het geld nog is.
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
      -- Lopend of gepauzeerd. Een afgesloten avond hoort bij je resultaten,
      -- niet bij "waar zit ik nu".
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

    -- Het niveau waar de klok op staat, en het niveau waar je mee rekent.
    -- Tijdens een pauze zijn dat er twee verschillende.
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

    (select count(*)::int from tournament_players x
      where x.tournament_id = t.id and x.status in ('active','registered')),
    (select count(*)::int from tournament_players x where x.tournament_id = t.id),
    (public.chips_in_play(t.id) / greatest(1, (
       select count(*)::int from tournament_players x
       where x.tournament_id = t.id and x.status in ('active','registered'))))::int,
    public.chips_in_play(t.id),

    -- Mijn plaats, gerekend over wie er een stapel heeft ingevuld. Zonder
    -- eigen aantal geen plaats: dan zou je bij de laatste staan omdat je
    -- niets doorgaf, en dat is geen informatie maar een verwijt.
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

comment on function public.my_live_tournaments() is
  'De avonden waar de aangemelde speler nu aan tafel zit, met alles wat hij aan tafel wil weten: de blinds van dit moment, zijn stapel, het gemiddelde, zijn plaats over de ingevulde stapels en hoeveel plaatsen er betaald worden.';

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function public.my_live_tournaments() to authenticated;
  end if;
end $$;

-- ===========================================================================
-- 0054_spelers_per_tafel.sql
-- ===========================================================================
-- Pokerleague — hoeveel spelers er per tafel zitten
--
-- Een tornooi is 9-max of 8-max of 6-max, en dat is geen detail: het bepaalt
-- hoeveel tafels je moet openen, wanneer je er een breekt, en hoe het spel
-- speelt. Tot nu stond het nergens. De tabel `tournament_tables` kende al een
-- `seats` per tafel, maar er was geen afspraak op het niveau van de avond
-- waar die tafels hun aantal vandaan halen.
--
-- Vandaar één veld op het tornooi. De tafels die er straks bij komen erven
-- het; wie één tafel afwijkend wil zetten, kan dat daar nog altijd.
--
-- **Waarom negen als standaard.** Dat is de volle ring waar de meeste clubs
-- mee draaien, en het is de veiligste kant om op te vergissen: te ruim zetten
-- geeft een tafel met een lege stoel, te krap zetten geeft een speler die
-- nergens kan zitten.
--
-- **En waarom er een grens op staat.** Twee is heads-up, tien is de breedste
-- tafel die in een zaal past. Daarbuiten is het een tikfout, en een tikfout in
-- dit veld merk je pas als er tien man rond een tafel voor acht staat.
--
-- ---------------------------------------------------------------------------
-- Tussendoor: de lijst met bij te stellen velden verhuist naar een functie
-- ---------------------------------------------------------------------------
-- `update_tournament` (0049) draagt die lijst als constante in zijn body. Elk
-- nieuw veld betekent dus de hele functie opnieuw uitschrijven — honderd
-- regels overtypen om er één woord bij te zetten, en dat gaat een keer mis.
-- De lijst staat nu apart; een volgend veld is voortaan één regel.

alter table tournaments
  add column if not exists seats_per_table int not null default 9;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'tournaments_seats_per_table_check'
  ) then
    alter table tournaments
      add constraint tournaments_seats_per_table_check
      check (seats_per_table between 2 and 10);
  end if;
end $$;

comment on column public.tournaments.seats_per_table is
  'Hoeveel spelers er maximaal aan één tafel zitten: 9 voor een volle ring, 8 voor 8-max, 6 voor short-handed. Tafels die voor dit tornooi worden geopend, erven dit aantal.';

-- ---------------------------------------------------------------------------
-- 1. Wat een mens aan een bestaand tornooi mag bijstellen
-- ---------------------------------------------------------------------------

create or replace function public.tournament_editable_fields()
returns text[]
language sql
immutable
as $$
  select array[
    'name', 'notes', 'scheduled_at', 'player_visibility',
    'season_id', 'structure_id', 'payout_template_id',
    'buyin_cents', 'fee_cents', 'rebuy_cents', 'rebuy_fee_cents',
    'addon_cents', 'addon_fee_cents', 'addon_stack',
    'bounty_mode', 'bounty_cents',
    'starting_stack', 'max_reentries', 'late_reg_level',
    'prereg_bonus_stack', 'seats_per_table'
  ];
$$;

comment on function public.tournament_editable_fields() is
  'De velden die het bewerkscherm van een tornooi mag wijzigen. Staat apart zodat er een veld bij kan zonder update_tournament opnieuw uit te schrijven.';

create or replace function public.update_tournament(
  p_tournament_id uuid,
  p_patch         jsonb
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  t         tournaments%rowtype;
  v_new     tournaments%rowtype;
  v_sleutel text;
  v_klok    boolean;

  c_toegestaan constant text[] := public.tournament_editable_fields();
  -- Hiervan blijft er ná afloop nog iets over: een verkeerd gespelde naam mag
  -- je altijd rechtzetten.
  c_na_afloop constant text[] := array['name', 'notes', 'player_visibility'];
begin
  select * into t from tournaments where id = p_tournament_id;
  if not found then
    raise exception 'Tornooi bestaat niet';
  end if;

  if not public.is_service_context()
     and not public.has_club_role(t.club_id, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten om dit tornooi te wijzigen'
      using errcode = 'insufficient_privilege';
  end if;

  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then
    raise exception 'Geef een object mee met de velden die moeten wijzigen'
      using errcode = 'check_violation';
  end if;

  for v_sleutel in select jsonb_object_keys(p_patch) loop
    if not (v_sleutel = any(c_toegestaan)) then
      raise exception 'Het veld "%" kan hier niet gewijzigd worden.', v_sleutel
        using errcode = 'check_violation';
    end if;
    if t.status in ('finished', 'cancelled') and not (v_sleutel = any(c_na_afloop)) then
      raise exception 'Deze avond is afgelopen. Alleen de naam en de zichtbaarheid kunnen nog wijzigen, "%" niet.', v_sleutel
        using errcode = 'check_violation';
    end if;
  end loop;

  v_new := jsonb_populate_record(t, p_patch);

  v_klok := t.started_at is not null or t.level_idx > 0;
  if v_new.structure_id is distinct from t.structure_id and v_klok then
    raise exception 'De klok van deze avond heeft al gelopen. De blindstructuur wisselen zou de zaal naar een ander level sturen dan wat er op tafel ligt.'
      using errcode = 'check_violation';
  end if;

  if v_new.starting_stack <= 0 then
    raise exception 'De startstapel moet groter zijn dan nul' using errcode = 'check_violation';
  end if;

  if v_new.seats_per_table < 2 or v_new.seats_per_table > 10 then
    raise exception 'Een tafel heeft plaats voor 2 tot 10 spelers' using errcode = 'check_violation';
  end if;

  if least(
       v_new.buyin_cents, v_new.fee_cents, v_new.bounty_cents,
       coalesce(v_new.rebuy_cents, 0), coalesce(v_new.rebuy_fee_cents, 0),
       coalesce(v_new.addon_cents, 0), coalesce(v_new.addon_fee_cents, 0),
       v_new.prereg_bonus_stack, v_new.max_reentries
     ) < 0 then
    raise exception 'Bedragen en aantallen kunnen niet negatief zijn' using errcode = 'check_violation';
  end if;

  update tournaments set
    name               = v_new.name,
    notes              = v_new.notes,
    scheduled_at       = v_new.scheduled_at,
    player_visibility  = v_new.player_visibility,
    season_id          = v_new.season_id,
    structure_id       = v_new.structure_id,
    payout_template_id = v_new.payout_template_id,
    buyin_cents        = v_new.buyin_cents,
    fee_cents          = v_new.fee_cents,
    rebuy_cents        = v_new.rebuy_cents,
    rebuy_fee_cents    = v_new.rebuy_fee_cents,
    addon_cents        = v_new.addon_cents,
    addon_fee_cents    = v_new.addon_fee_cents,
    addon_stack        = v_new.addon_stack,
    bounty_mode        = v_new.bounty_mode,
    bounty_cents       = v_new.bounty_cents,
    starting_stack     = v_new.starting_stack,
    max_reentries      = v_new.max_reentries,
    late_reg_level     = v_new.late_reg_level,
    prereg_bonus_stack = v_new.prereg_bonus_stack,
    seats_per_table    = v_new.seats_per_table
  where id = p_tournament_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Een tafel erft het aantal van de avond
-- ---------------------------------------------------------------------------
-- Zodat de indeling die hierna komt niet elke keer opnieuw hoeft te bedenken
-- hoeveel stoelen er aan een tafel staan. Wie een tafel bewust anders zet —
-- een finaletafel voor tien — geeft `seats` gewoon mee; dan blijft die staan.

create or replace function public.default_table_seats()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.seats is null then
    select t.seats_per_table into new.seats
    from tournaments t where t.id = new.tournament_id;
  end if;
  return new;
end;
$$;

alter table tournament_tables alter column seats drop not null;
alter table tournament_tables alter column seats drop default;

drop trigger if exists tournament_tables_default_seats on tournament_tables;
create trigger tournament_tables_default_seats
  before insert on tournament_tables
  for each row execute function public.default_table_seats();

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function public.update_tournament(uuid, jsonb) to authenticated;
    grant execute on function public.tournament_editable_fields() to authenticated;
  end if;
end $$;

-- ===========================================================================
-- 0055_tafelindeling.sql
-- ===========================================================================
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

-- ===========================================================================
-- 0056_live_blinds_en_stoelen.sql
-- ===========================================================================
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

-- ===========================================================================
-- 0057_plaats_schatten.sql
-- ===========================================================================
-- Pokerleague — je plaats schatten in plaats van tellen
--
-- "3de van 9" klonk exact en was het niet. Die 9 waren de spelers die hun
-- stapel hadden ingevuld, en dat zijn er op een gewone avond een handvol. Wie
-- als enige zijn chips doorgaf stond eerste van één — een getal dat niets zegt
-- en toch als een stand leest.
--
-- **Wat we wél zeker weten.** Het aantal chips in spel staat vast: dat volgt
-- uit het geldregister en niet uit wat spelers doorgeven. Gedeeld door het
-- aantal spelers dat nog zit, geeft dat een gemiddelde dat altijd klopt. Jouw
-- eigen stapel weet je zelf. Twee getallen die er zijn, dus, en daaruit valt
-- af te leiden waar je ongeveer staat — zonder dat er iemand anders iets moet
-- invullen.
--
-- **De schatting.** Neem aan dat de stapels ruwweg gelijkmatig liggen tussen
-- niets en het dubbele van het gemiddelde. Zit je precies op het gemiddelde,
-- dan staat de helft van het veld boven je: bij vijf spelers ben je de derde.
-- Heb je het dubbele, dan sta je bovenaan; heb je bijna niets, onderaan.
--
--     plaats = 1 + (1 - stapel / (2 × gemiddelde)) × (spelers - 1)
--
-- Dat is een model en geen meting, en het pretendeert ook niet meer te zijn:
-- het scherm zet er een ± voor. Maar het is over het hele veld gerekend en
-- niet over de vier mensen die toevallig hun gsm bovenhaalden, en dus zegt het
-- iets waar je aan tafel wat aan hebt.
--
-- **Behalve als iedereen wél ingevuld heeft.** Dan is tellen beter dan
-- schatten, en telt hij gewoon. Het scherm laat het ± dan weg. Dat is precies
-- de situatie na een telronde van de floor, en dan hoort het getal ook hard te
-- zijn.

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
  /** True als de plaats een schatting is uit het gemiddelde. */
  rank_estimated       boolean,
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
    v.over,
    v.deelnames,
    v.gemiddeld,
    v.in_spel,

    -- De plaats. Weet iedereen zijn stapel, dan tellen we; anders schatten we
    -- uit het gemiddelde. Zonder eigen aantal staat er niets — dat blijft een
    -- vraag aan de speler en geen verwijt.
    case
      when m.chip_count is null then null
      when v.ingevuld >= v.over then v.exacte_plaats
      when v.gemiddeld <= 0 then null
      else greatest(1, least(v.over, round(
             1 + (1 - least(1, m.chip_count::numeric / (2 * v.gemiddeld))) * (v.over - 1)
           )::int))
    end,
    (m.chip_count is not null and v.ingevuld < v.over and v.gemiddeld > 0),
    v.ingevuld,

    (select count(*)::int from public.tournament_prizes(t.id)),
    (select coalesce(sum(b.amount_cents), 0) from buyins b
      where b.tournament_id = t.id and not b.is_void)
  from mijn m
  join tournaments t on t.id = m.tournament_id
  join clubs c       on c.id = t.club_id
  cross join lateral public.clock_position(t.id) k
  cross join lateral (
    select
      (select count(*)::int from tournament_players x
        where x.tournament_id = t.id and x.status in ('active','registered')) as over,
      (select count(*)::int from tournament_players x
        where x.tournament_id = t.id) as deelnames,
      (select count(*)::int from tournament_players x
        where x.tournament_id = t.id and x.status in ('active','registered')
          and x.chip_count is not null) as ingevuld,
      public.chips_in_play(t.id) as in_spel,
      (public.chips_in_play(t.id) / greatest(1, (
         select count(*)::int from tournament_players x
         where x.tournament_id = t.id and x.status in ('active','registered'))))::int as gemiddeld,
      (select count(*)::int + 1
        from tournament_players x
        where x.tournament_id = t.id
          and x.status in ('active','registered')
          and x.chip_count is not null
          and x.chip_count > m.chip_count) as exacte_plaats
  ) v
  order by t.scheduled_at desc;
$$;

comment on function public.my_live_tournaments() is
  'De avonden waar de aangemelde speler nu aan tafel zit. De plaats wordt geteld als iedereen zijn stapel ingaf, en anders geschat uit de verhouding tot het gemiddelde — dat gemiddelde volgt uit het geldregister en klopt altijd.';

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function public.my_live_tournaments() to authenticated;
  end if;
end $$;

-- ===========================================================================
-- 0058_levels_tijdens_de_avond.sql
-- ===========================================================================
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

-- ===========================================================================
-- 0059_tornooi_verwijderen.sql
-- ===========================================================================
-- Pokerleague — het aantal inschrijvingen uit het zicht, en een avond kunnen wissen
--
-- Twee dingen die niets met elkaar te maken hebben behalve dat ze allebei over
-- vertrouwen gaan: wie mag wat zien, en wie mag wat weggooien.
--
-- ---------------------------------------------------------------------------
-- 1. Het aantal inschrijvingen is niet voor spelers
-- ---------------------------------------------------------------------------
-- Het stond op twee plaatsen: op de affichepagina ("12 ingeschreven") en in de
-- kalender van de speler ("12 komen"). Dat leest als sfeerbeeld maar werkt als
-- het tegenovergestelde: staat er drie, dan denkt de volgende bezoeker dat het
-- niet doorgaat en schrijft hij zich niet in. Een lage teller houdt zichzelf
-- laag. En het gaat de zaal ook niet aan hoe vol het is — dat is iets tussen de
-- floor en zijn tafels.
--
-- **Het weghalen uit het scherm volstaat niet.** Deze functies zijn RPC's die
-- iedereen mag aanroepen; wie het getal uit de tabel haalt, heeft het gewoon.
-- Dus gaat de kolom eruit, en dan bestaat het antwoord niet meer.
--
-- De floor houdt zijn lijst: `tournament_rsvp_list` is afgeschermd op rol en
-- blijft ongemoeid.
--
-- Wat blijft staan is `entries` — hoeveel mensen er werkelijk aan tafel zitten
-- op een avond die loopt. Dat is geen inschrijvingsteller maar de veldgrootte,
-- en die staat sowieso al op het live-bord.

-- `returns table` verandert van vorm, dus eerst weg. `create or replace` kan
-- het rijtype niet aanpassen en geeft anders een fout die niets uitlegt.
drop function if exists public.tournament_signup_card(text, uuid);

create or replace function public.tournament_signup_card(
  p_club_slug     text,
  p_tournament_id uuid default null
)
returns table (
  tournament_id  uuid,
  name           text,
  scheduled_at   timestamptz,
  status         text,
  buyin_cents    int,
  fee_cents      int,
  starting_stack int,
  bonus_stack    int,
  is_open        boolean,
  club_slug      text,
  club_name      text,
  city           text,
  address_line   text,
  maps_url       text,
  logo_url       text,
  primary_color  text,
  currency       char(3),
  timezone       text,
  locale         text
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with c as (
    select * from clubs where slug = p_club_slug and is_active
  ),
  t as (
    select t.*
    from tournaments t
    join c on c.id = t.club_id
    where (p_tournament_id is null or t.id = p_tournament_id)
      and t.status = 'scheduled'
      -- Zonder id: de eerstvolgende. Zo kan er één kort adres op de affiche
      -- staan dat volgende maand vanzelf naar de volgende avond wijst.
      and (p_tournament_id is not null or t.scheduled_at > now())
    order by t.scheduled_at
    limit 1
  )
  select
    t.id, t.name, t.scheduled_at, t.status::text,
    t.buyin_cents, t.fee_cents, t.starting_stack, t.prereg_bonus_stack,
    -- Open tot het tornooi begint. Daarna is inschrijven zinloos: dan sta je
    -- aan de deur en doet de floor het.
    (t.status = 'scheduled' and t.scheduled_at > now()),
    c.slug, c.name, c.city, c.address_line, c.maps_url, c.logo_url,
    c.primary_color, c.currency, c.timezone, c.locale
  from t cross join c;
$$;

comment on function public.tournament_signup_card(text, uuid) is
  'De gegevens voor de publieke inschrijfpagina van één avond. Bewust zonder het aantal inschrijvingen: dat gaat de bezoeker niet aan, en een lage teller houdt zichzelf laag.';

drop function if exists public.my_calendar(int);

create or replace function public.my_calendar(p_days int default 120)
returns table (
  tournament_id  uuid,
  name           text,
  scheduled_at   timestamptz,
  status         text,
  club_slug      text,
  club_name      text,
  logo_url       text,
  primary_color  text,
  currency       char(3),
  timezone       text,
  buyin_cents    int,
  fee_cents      int,
  bonus_stack    int,
  entries        int,
  i_play         boolean,
  i_rsvp         boolean,
  can_rsvp       boolean
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
  mijn_clubs as (
    select cp.club_id from club_players cp where cp.player_id = (select id from me)
  )
  select
    t.id,
    t.name,
    t.scheduled_at,
    t.status::text,
    c.slug,
    c.name,
    c.logo_url,
    c.primary_color,
    c.currency,
    c.timezone,
    t.buyin_cents,
    t.fee_cents,
    t.prereg_bonus_stack,
    (select count(*)::int from tournament_players x where x.tournament_id = t.id),
    exists (
      select 1 from tournament_players x
      where x.tournament_id = t.id and x.player_id = (select id from me)
    ),
    -- Of híj ingeschreven staat, blijft hij wél zien. Dat is zijn eigen
    -- gegeven en het antwoord op de enige vraag die hij hier heeft.
    exists (
      select 1 from tournament_registrations r
      where r.tournament_id = t.id and r.player_id = (select id from me)
        and r.cancelled_at is null
    ),
    -- Inschrijven kan zolang de avond gepland is en nog moet beginnen. Zit je
    -- al aan tafel, dan is de vraag niet meer aan de orde.
    (t.status = 'scheduled' and t.scheduled_at > now()
     and not exists (select 1 from tournament_players x
                     where x.tournament_id = t.id and x.player_id = (select id from me)))
  from tournaments t
  join clubs c on c.id = t.club_id
  where t.club_id in (select club_id from mijn_clubs)
    and t.status in ('scheduled', 'running', 'paused')
    and (t.player_visibility = 'public'
         or (t.player_visibility = 'members' and public.is_club_player(t.club_id))
         or public.is_club_member(t.club_id))
    and t.scheduled_at >= now() - interval '12 hours'
    and t.scheduled_at <= now() + make_interval(days => greatest(1, p_days))
  order by t.scheduled_at;
$$;

comment on function public.my_calendar(int) is
  'De komende avonden bij de clubs van deze speler. Toont wel of hij zelf ingeschreven staat, niet hoeveel anderen.';

-- ---------------------------------------------------------------------------
-- 2. Een avond verwijderen
-- ---------------------------------------------------------------------------
-- Tot nu toe kon dat alleen met een script in de SQL-editor, en dat is een
-- omweg voor iets wat regelmatig nodig is: een testavond, een dubbel
-- aangemaakt tornooi, een zondag die niet doorgaat.
--
-- **Alles gaat mee.** Deelnames, inkopen, uitschakelingen, inschrijvingen,
-- tafels, uitslag. Dat volgt uit de cascade op de tabellen; er is hier niets
-- apart te wissen. Het klassement rekent uit `tournament_results`, dus dat
-- klopt meteen weer.
--
-- **Maar niet iedereen mag alles.** Een avond die nooit gespeeld is, is
-- rommel opruimen — dat mag een floor. Een avond mét uitslag weggooien
-- verandert het klassement van de club, en wie dat doet moet het ook mogen
-- beslissen: alleen owner en admin. Dat onderscheid staat hier en niet in het
-- scherm, want een knop die je verbergt is geen beveiliging.
--
-- **Afgelasten is iets anders dan wissen.** Een avond die niet doorgaat maar
-- wel bestond, zet je op `cancelled`; dan blijft hij in de geschiedenis staan.
-- Wissen is voor wat er nooit had mogen zijn.

create or replace function public.tournament_delete_info(p_tournament_id uuid)
returns table (
  name           text,
  status         text,
  scheduled_at   timestamptz,
  spelers        int,
  inschrijvingen int,
  inkopen        int,
  uitslagen      int,
  mag_ik         boolean
)
language plpgsql
stable
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

  return query
  select
    t.name,
    t.status::text,
    t.scheduled_at,
    (select count(*)::int from tournament_players x where x.tournament_id = t.id),
    (select count(*)::int from tournament_registrations x
      where x.tournament_id = t.id and x.cancelled_at is null),
    (select count(*)::int from buyins x where x.tournament_id = t.id),
    (select count(*)::int from tournament_results x where x.tournament_id = t.id),
    -- Mag de aanroeper hem ook werkelijk wissen, of ziet hij alleen de cijfers?
    (public.is_service_context()
     or public.has_club_role(t.club_id, array['owner','admin']::club_role[])
     or not exists (select 1 from tournament_results x where x.tournament_id = t.id)
        and not exists (select 1 from tournament_players x where x.tournament_id = t.id));
end;
$$;

comment on function public.tournament_delete_info(uuid) is
  'Wat er aan een avond hangt, zodat het scherm kan tonen wat er precies verdwijnt voor er iemand op verwijderen drukt.';

create or replace function public.floor_delete_tournament(p_tournament_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  t          tournaments%rowtype;
  v_spelers  int;
  v_uitslag  int;
  v_naam     text;
  v_str      uuid;
begin
  select * into t from tournaments where id = p_tournament_id;
  if not found then
    raise exception 'Tornooi bestaat niet';
  end if;

  if not public.is_service_context()
     and not public.has_club_role(t.club_id, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten' using errcode = 'insufficient_privilege';
  end if;

  select count(*) into v_spelers from tournament_players where tournament_id = t.id;
  select count(*) into v_uitslag from tournament_results where tournament_id = t.id;

  -- Er is gespeeld. Dan raakt wissen de geschiedenis van de club, en dat is
  -- geen beslissing voor tijdens een avond.
  if (v_spelers > 0 or v_uitslag > 0)
     and not public.is_service_context()
     and not public.has_club_role(t.club_id, array['owner','admin']::club_role[]) then
    raise exception 'Aan deze avond hangt al gespeeld werk (% deelnames, % uitslagregels). Alleen een beheerder kan die verwijderen.',
      v_spelers, v_uitslag
      using errcode = 'insufficient_privilege';
  end if;

  v_naam := t.name;
  v_str := t.structure_id;

  delete from tournaments where id = p_tournament_id;

  -- Had die avond een eigen kopie van de blindstructuur — die maakt het
  -- systeem aan zodra je tijdens het spelen aan de levels komt — dan hangt ze
  -- nu nergens meer aan. Clubsjablonen blijven, die hebben geen tornooi nodig.
  if v_str is not null then
    delete from blind_structures bs
    where bs.id = v_str
      and bs.club_id = t.club_id
      and bs.description like 'Eigen structuur van deze avond%'
      and not exists (select 1 from tournaments x where x.structure_id = bs.id);
  end if;

  return jsonb_build_object(
    'name', v_naam,
    'players', v_spelers,
    'results', v_uitslag);
end;
$$;

comment on function public.floor_delete_tournament(uuid) is
  'Verwijdert een avond met alles wat eraan hangt. Een avond waar al gespeeld is, kan alleen door owner of admin.';

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function public.tournament_signup_card(text, uuid)     to anon, authenticated;
    grant execute on function public.my_calendar(int)                       to authenticated;
    grant execute on function public.tournament_delete_info(uuid)           to authenticated;
    grant execute on function public.floor_delete_tournament(uuid)          to authenticated;
  end if;
end $$;
