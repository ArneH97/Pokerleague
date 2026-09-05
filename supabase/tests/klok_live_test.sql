-- Tests voor de klok zoals de speler hem ziet, en voor het stoelvoorstel.
--
-- De aanleiding: op de spelerspagina stonden de verkeerde blinds. Die las
-- `tournaments.level_idx`, en dat veld loopt achter zodra er geen floorscherm
-- openstaat om het bij te werken. De databank rekent het nu zelf uit.

begin;

do $$
declare
  v_club uuid; v_str uuid; v_tour uuid; v_ik uuid; v_tp uuid;
  v_user uuid := gen_random_uuid();
  k record; r record; v_sug jsonb;
begin
  insert into auth.users (id, email) values (v_user, 'klok@test.be');

  insert into clubs (slug, name, compliance)
  values ('kl-' || substr(gen_random_uuid()::text, 1, 12), 'Kloktest',
          jsonb_build_object('enforce','off'))
  returning id into v_club;

  -- Vier niveaus van 20 minuten, met een pauze op plek 3.
  insert into blind_structures (club_id, name) values (v_club, 'S') returning id into v_str;
  insert into blind_levels (structure_id, idx, small_blind, big_blind, ante, duration_s, is_break)
  values (v_str, 0, 100,  200,  0,   1200, false),
         (v_str, 1, 200,  400,  400, 1200, false),
         (v_str, 2, 0,    0,    0,   600,  true),
         (v_str, 3, 300,  600,  600, 1200, false);

  insert into tournaments (club_id, structure_id, name, scheduled_at, status,
                           buyin_cents, fee_cents, starting_stack,
                           clock, level_idx, level_elapsed_ms, seats_per_table)
  values (v_club, v_str, 'Avond', now(), 'running', 4000, 0, 40000,
          'paused', 0, 0, 6)
  returning id into v_tour;

  -- --------------------------------------------------- de klok staat stil
  select * into k from public.clock_position(v_tour);
  assert k.level_idx = 0, format('niveau 1 verwacht, kreeg %s', k.level_idx + 1);
  assert k.remaining_ms = 1200000, format('twintig minuten verwacht, kreeg %s ms', k.remaining_ms);
  raise notice 'OK  een stilstaande klok staat waar hij staat';

  -- Een gepauzeerde klok schuift niet op, hoe lang je ook wacht: alleen de
  -- opgebouwde tijd telt.
  update tournaments set level_started_at = now() - interval '3 hours' where id = v_tour;
  select * into k from public.clock_position(v_tour);
  assert k.level_idx = 0, 'een pauze van drie uur schoof toch een niveau op';
  raise notice 'OK  een pauze schuift geen niveaus op';

  -- ------------------------------------------- de klok loopt en rolt door
  -- Vijfenveertig minuten sinds het vertrekpunt: 20 + 20 gaan eraf, dus we
  -- zitten vijf minuten in de pauze van tien op plek 3. Bewust niet precies
  -- vijftig: dat is de grens zelf, en dan is het net zo goed te verdedigen dat
  -- de klok al één niveau verder staat.
  update tournaments
  set clock = 'running', level_idx = 0, level_elapsed_ms = 0,
      level_started_at = now() - interval '45 minutes'
  where id = v_tour;

  select * into k from public.clock_position(v_tour);
  assert k.level_idx = 2, format('de pauze verwacht (index 2), kreeg %s', k.level_idx);
  assert k.remaining_ms between 0 and 600000,
    format('binnen de pauze van tien minuten verwacht, kreeg %s ms', k.remaining_ms);
  raise notice 'OK  een lopende klok rolt vanzelf door naar het juiste niveau';

  -- En dat is precies wat de speler te zien hoort te krijgen — ook al staat
  -- er in de databank nog altijd level_idx = 0 omdat er geen floorscherm
  -- openstond om het bij te werken.
  assert (select level_idx from tournaments where id = v_tour) = 0,
    'de opzet klopt niet: het veld hoort nog achter te lopen';

  insert into players (display_name, email, auth_user_id, link_state)
  values ('Ik', 'klok@test.be', v_user, 'claimed') returning id into v_ik;
  v_tp := public.floor_add_entry(v_tour, v_ik);

  perform set_config('request.jwt.claim.sub', v_user::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  select * into r from public.my_live_tournaments() limit 1;
  assert r.level_idx = 2, format('de speler hoort niveau 3 te zien, kreeg %s', r.level_idx + 1);
  assert r.is_break, 'de speler ziet niet dat het pauze is';
  assert r.big_blind = 600,
    format('tijdens de pauze horen de blinds van erna te gelden (600), kreeg %s', r.big_blind);
  assert r.level_remaining_ms > 0, 'er hoort nog tijd op de klok te staan';
  raise notice 'OK  de speler ziet de blinds van dit moment, ook zonder floorscherm';

  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);

  -- Voorbij het laatste niveau blijft hij op het laatste staan.
  update tournaments set level_started_at = now() - interval '10 hours' where id = v_tour;
  select * into k from public.clock_position(v_tour);
  assert k.finished, 'na alle niveaus hoort de klok afgelopen te zijn';
  assert k.level_idx = 3, format('het laatste niveau verwacht, kreeg %s', k.level_idx);
  raise notice 'OK  voorbij het laatste niveau blijft hij op het laatste staan';

  -- --------------------------------------------------- het stoelvoorstel
  v_sug := public.seating_suggestion(v_tour);
  assert (v_sug ->> 'opens_table')::boolean,
    'zonder tafels hoort het voorstel er een te openen';
  assert (v_sug ->> 'table_no')::int = 1 and (v_sug ->> 'seat_no')::int = 1,
    'het voorstel hoort tafel 1 stoel 1 te zijn';
  raise notice 'OK  zonder tafels stelt hij tafel 1 stoel 1 voor';

  -- Iemand toevoegen en meteen zetten.
  v_sug := public.floor_seat_next(v_tp);
  assert (v_sug ->> 'table_no')::int = 1 and (v_sug ->> 'seat_no')::int = 1,
    'de speler kwam niet op de voorgestelde stoel';
  assert (select table_no from tournament_players where id = v_tp) = 1,
    'de speler zit niet aan tafel 1';
  raise notice 'OK  de voorgestelde stoel is met één handeling toe te kennen';

  -- Het volgende voorstel schuift op naar stoel 2.
  v_sug := public.seating_suggestion(v_tour);
  assert (v_sug ->> 'seat_no')::int = 2 and not (v_sug ->> 'opens_table')::boolean,
    format('stoel 2 verwacht, kreeg %s', v_sug ->> 'seat_no');
  raise notice 'OK  het volgende voorstel schuift op naar de eerstvolgende vrije stoel';
end $$;

rollback;
