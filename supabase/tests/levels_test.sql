-- Tests voor het bijstellen van de blindstructuur tijdens de avond.
--
-- Het gevoeligste punt: een structuur hangt aan de club en dus aan élke avond
-- die hem gebruikt. Wie er vanavond twee levels bij plakt, mag daarmee niet
-- stilzwijgend volgende week veranderen.

begin;

do $$
declare
  v_club uuid; v_str uuid; v_a uuid; v_b uuid;
  v_str_a uuid; v_niveaus int; v_res jsonb;
  v_bb_voor int; v_bb_na int;
begin
  insert into clubs (slug, name, compliance)
  values ('lv-' || substr(gen_random_uuid()::text, 1, 12), 'Leveltest',
          jsonb_build_object('enforce','off'))
  returning id into v_club;

  insert into blind_structures (club_id, name) values (v_club, 'Clubsjabloon') returning id into v_str;
  insert into blind_levels (structure_id, idx, small_blind, big_blind, ante, duration_s, is_break)
  values (v_str, 0, 25,  50,  0, 1200, false),
         (v_str, 1, 50,  100, 0, 1200, false),
         (v_str, 2, 0,   0,   0, 600,  true),
         (v_str, 3, 100, 200, 0, 1200, false),
         (v_str, 4, 150, 300, 0, 1200, false);

  -- Twee avonden op hetzelfde sjabloon: dat is precies de situatie waarin
  -- bijstellen gevaarlijk zou zijn.
  insert into tournaments (club_id, structure_id, name, scheduled_at, status,
                           buyin_cents, fee_cents, starting_stack,
                           clock, level_idx, level_elapsed_ms, level_started_at)
  values (v_club, v_str, 'Vanavond', now(), 'running', 4000, 0, 40000,
          'running', 0, 0, now() - interval '25 minutes')
  returning id into v_a;

  insert into tournaments (club_id, structure_id, name, scheduled_at, status,
                           buyin_cents, fee_cents, starting_stack)
  values (v_club, v_str, 'Volgende week', now() + interval '7 days', 'scheduled',
          4000, 0, 40000)
  returning id into v_b;

  -- De klok van vanavond staat op level 2 (25 minuten: level 1 is voorbij).
  assert (select k.level_idx from public.clock_position(v_a) k) = 1,
    'de opzet klopt niet: de klok hoort op het tweede niveau te staan';

  -- ------------------------------------- het verleden ligt vast
  begin
    perform public.floor_set_upcoming_levels(v_a, 0, '[]'::jsonb);
    raise exception 'een gespeeld level kon vervangen worden';
  exception when check_violation then
    raise notice 'OK  levels die al gespeeld zijn, kan je niet meer aanpassen';
  end;

  -- ------------------------------------- vanaf het huidige level mag wel
  v_niveaus := public.floor_set_upcoming_levels(v_a, 1, jsonb_build_array(
    jsonb_build_object('small_blind', 50,  'big_blind', 100, 'ante', 100, 'duration_s', 1800),
    jsonb_build_object('is_break', true,   'label', 'Pauze', 'duration_s', 900),
    jsonb_build_object('small_blind', 100, 'big_blind', 200, 'ante', 200, 'duration_s', 1800)
  ));
  assert v_niveaus = 3, format('drie levels verwacht, kreeg %s', v_niveaus);
  raise notice 'OK  de komende levels zijn te vervangen';

  -- ------------------------------- en het clubsjabloon blijft ongemoeid
  select structure_id into v_str_a from tournaments where id = v_a;
  assert v_str_a <> v_str, 'de avond kreeg geen eigen structuur';
  assert (select structure_id from tournaments where id = v_b) = v_str,
    'de andere avond werd van structuur gewisseld';
  assert (select count(*) from blind_levels where structure_id = v_str) = 5,
    'het clubsjabloon is veranderd';
  assert (select duration_s from blind_levels where structure_id = v_str and idx = 1) = 1200,
    'het clubsjabloon kreeg de nieuwe duur toch mee';
  raise notice 'OK  het clubsjabloon en de andere avonden blijven ongemoeid';

  -- Het gespeelde level staat er nog zoals het was.
  assert (select duration_s from blind_levels where structure_id = v_str_a and idx = 0) = 1200,
    'het gespeelde level is toch veranderd';
  assert (select big_blind from blind_levels where structure_id = v_str_a and idx = 1) = 100,
    'het huidige level kreeg de nieuwe blinds niet';
  assert (select duration_s from blind_levels where structure_id = v_str_a and idx = 1) = 1800,
    'de nieuwe duur van het huidige level kwam niet aan';
  raise notice 'OK  het gespeelde verleden blijft staan, het heden en de toekomst wijzigen';

  -- En de klok staat nog waar hij stond: 25 minuten in, level 2 duurt nu 30.
  assert (select k.level_idx from public.clock_position(v_a) k) = 1,
    'de klok verschoof door het bijstellen';
  raise notice 'OK  de klok blijft staan waar hij stond';

  -- ------------------------------------------------ nog eens bijstellen
  -- De tweede keer is de structuur al van deze avond alleen; er hoort geen
  -- tweede kopie bij te komen.
  perform public.floor_set_upcoming_levels(v_a, 2, jsonb_build_array(
    jsonb_build_object('small_blind', 200, 'big_blind', 400, 'duration_s', 1200)));
  assert (select structure_id from tournaments where id = v_a) = v_str_a,
    'er kwam een tweede kopie bij';
  assert (select count(*) from blind_structures where club_id = v_club) = 2,
    'er staan meer structuren dan het sjabloon plus de kopie van deze avond';
  raise notice 'OK  een tweede aanpassing hergebruikt dezelfde eigen structuur';

  -- ------------------------------------------------- er eentje bijzetten
  select big_blind into v_bb_voor from blind_levels
   where structure_id = v_str_a and not is_break order by idx desc limit 1;

  v_res := public.floor_append_level(v_a, false);
  select big_blind into v_bb_na from blind_levels
   where structure_id = v_str_a and not is_break order by idx desc limit 1;

  assert v_bb_na > v_bb_voor,
    format('de nieuwe blinds (%s) horen hoger te zijn dan de vorige (%s)', v_bb_na, v_bb_voor);
  assert (v_res ->> 'big_blind')::int = v_bb_na, 'het antwoord klopt niet met wat er staat';
  raise notice 'OK  een level bijzetten volgt de sprong van de structuur';

  -- En een pauze bijzetten.
  v_res := public.floor_append_level(v_a, true);
  assert (v_res ->> 'is_break')::boolean, 'de pauze werd niet als pauze gezet';
  assert (select is_break from blind_levels
           where structure_id = v_str_a order by idx desc limit 1),
    'het laatste niveau is geen pauze';
  raise notice 'OK  een pauze bijzetten kan ook';

  -- ---------------------------------------------------------------- rechten
  perform set_config('request.jwt.claim.sub', gen_random_uuid()::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  begin
    perform public.floor_append_level(v_a, false);
    raise exception 'een vreemde kon een level bijzetten';
  exception when insufficient_privilege then
    raise notice 'OK  zonder rol bij de club kan je niets aan de structuur doen';
  end;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);

  -- ------------------------------------------------ na afloop niet meer
  update tournaments set status = 'finished' where id = v_a;
  begin
    perform public.floor_append_level(v_a, false);
    raise exception 'er kon een level bij op een afgesloten tornooi';
  exception when check_violation then
    raise notice 'OK  op een afgesloten avond kan er niets meer bij';
  end;
end $$;

rollback;
