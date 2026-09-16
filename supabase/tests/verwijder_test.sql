-- Tests voor het verwijderen van een avond, en voor wat een speler niet meer ziet.
--
-- Twee dingen die allebei stil kunnen breken. Een kolom die uit een RPC
-- verdwijnt, merk je pas als een scherm leeg blijft; en een verwijderfunctie
-- die te veel toelaat, merk je pas als er een avond weg is.

begin;

do $$
declare
  v_club uuid; v_leeg uuid; v_gespeeld uuid; v_str uuid; v_eigen uuid;
  v_floor uuid := gen_random_uuid();
  v_baas  uuid := gen_random_uuid();
  v_p uuid; v_tp uuid; v_tps uuid[] := array[]::uuid[]; i int;
  r record; v_res jsonb; v_n int;
begin
  insert into auth.users (id, email) values
    (v_floor, format('floor-%s@test.be', substr(v_floor::text, 1, 8))),
    (v_baas,  format('baas-%s@test.be',  substr(v_baas::text, 1, 8)));

  insert into clubs (slug, name, compliance)
  values ('vw-' || substr(gen_random_uuid()::text, 1, 12), 'Verwijdertest',
          jsonb_build_object('enforce','off'))
  returning id into v_club;

  insert into club_members (club_id, user_id, role) values
    (v_club, v_floor, 'floor'), (v_club, v_baas, 'owner');

  insert into blind_structures (club_id, name) values (v_club, 'Clubsjabloon') returning id into v_str;
  insert into blind_levels (structure_id, idx, small_blind, big_blind, ante, duration_s, is_break)
  values (v_str, 0, 25, 50, 0, 1200, false), (v_str, 1, 50, 100, 0, 1200, false);

  -- ------------------------------------------------ een avond zonder geschiedenis
  insert into tournaments (club_id, structure_id, name, scheduled_at, status,
                           buyin_cents, fee_cents, starting_stack)
  values (v_club, v_str, 'Testavond', now() + interval '2 days', 'scheduled', 4000, 500, 40000)
  returning id into v_leeg;

  -- ------------------------------------------------ en een waar gespeeld is
  insert into tournaments (club_id, structure_id, name, scheduled_at, status,
                           buyin_cents, fee_cents, starting_stack)
  values (v_club, v_str, 'Echte avond', now() - interval '7 days', 'running', 4000, 500, 40000)
  returning id into v_gespeeld;

  for i in 1 .. 4 loop
    v_tps := v_tps || public.floor_add_entry(
      v_gespeeld, null, format('Speler %s', i),
      format('sp%s-%s@test.be', i, substr(gen_random_uuid()::text, 1, 8)));
  end loop;
  for i in 1 .. 3 loop perform public.floor_eliminate(v_tps[i], null); end loop;
  perform public.floor_finish_tournament(v_gespeeld);

  -- ------------------------------------------------- wat het scherm te zien krijgt
  select * into r from public.tournament_delete_info(v_leeg);
  assert r.spelers = 0, format('de lege avond hoort nul deelnames te hebben, kreeg %s', r.spelers);
  assert r.uitslagen = 0, 'de lege avond hoort geen uitslag te hebben';
  raise notice 'OK  het scherm ziet wat er aan een lege avond hangt';

  select * into r from public.tournament_delete_info(v_gespeeld);
  assert r.spelers = 4, format('vier deelnames verwacht, kreeg %s', r.spelers);
  assert r.uitslagen = 4, format('vier uitslagregels verwacht, kreeg %s', r.uitslagen);
  raise notice 'OK  en wat er aan een gespeelde avond hangt';

  -- ------------------------------------------------------------- als floor
  perform set_config('request.jwt.claim.sub', v_floor::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  select * into r from public.tournament_delete_info(v_gespeeld);
  assert not r.mag_ik, 'een floor hoort een gespeelde avond niet te mogen wissen';
  select * into r from public.tournament_delete_info(v_leeg);
  assert r.mag_ik, 'een floor hoort een lege avond wel te mogen wissen';
  raise notice 'OK  het scherm weet vooraf wat deze floor mag';

  begin
    perform public.floor_delete_tournament(v_gespeeld);
    raise exception 'een floor kon een gespeelde avond wissen';
  exception when insufficient_privilege then
    raise notice 'OK  een floor kan een avond met gespeeld werk niet wissen';
  end;

  -- En die avond staat er nog, met alles erop.
  assert (select count(*) from tournament_results where tournament_id = v_gespeeld) = 4,
    'de uitslag ging toch verloren';

  v_res := public.floor_delete_tournament(v_leeg);
  assert (v_res ->> 'name') = 'Testavond', 'de verkeerde avond werd gewist';
  assert not exists (select 1 from tournaments where id = v_leeg), 'de lege avond staat er nog';
  raise notice 'OK  een floor kan een avond zonder geschiedenis wel wissen';

  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);

  -- ---------------------------------------------- het clubsjabloon blijft staan
  assert exists (select 1 from blind_structures where id = v_str),
    'het clubsjabloon ging mee met de avond';
  assert (select count(*) from blind_levels where structure_id = v_str) = 2,
    'de levels van het clubsjabloon zijn weg';
  raise notice 'OK  het clubsjabloon overleeft het wissen van een avond';

  -- ------------------------------------------------------- als eigenaar
  perform set_config('request.jwt.claim.sub', v_baas::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  select * into r from public.tournament_delete_info(v_gespeeld);
  assert r.mag_ik, 'een eigenaar hoort een gespeelde avond wel te mogen wissen';

  v_res := public.floor_delete_tournament(v_gespeeld);
  assert (v_res ->> 'results')::int = 4, 'het antwoord telt de uitslagregels niet mee';
  assert not exists (select 1 from tournaments where id = v_gespeeld), 'de avond staat er nog';
  assert not exists (select 1 from tournament_results where tournament_id = v_gespeeld),
    'de uitslagregels bleven achter';
  raise notice 'OK  een eigenaar kan een gespeelde avond wissen, uitslag en al';

  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);

  -- --------------------------------------------- een vreemde kan niets
  insert into tournaments (club_id, name, scheduled_at, status, buyin_cents, fee_cents, starting_stack)
  values (v_club, 'Nog een', now() + interval '3 days', 'scheduled', 4000, 0, 40000)
  returning id into v_leeg;

  perform set_config('request.jwt.claim.sub', gen_random_uuid()::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  begin
    perform public.floor_delete_tournament(v_leeg);
    raise exception 'een buitenstaander kon een avond wissen';
  exception when insufficient_privilege then
    raise notice 'OK  wie niets met de club te maken heeft, kan niets wissen';
  end;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);

  -- ------------------------------ het aantal inschrijvingen is niet meer op te vragen
  select count(*) into v_n
  from information_schema.routines ro
  join information_schema.parameters pa
    on pa.specific_name = ro.specific_name
  where ro.routine_schema = 'public'
    and ro.routine_name in ('tournament_signup_card', 'my_calendar')
    and pa.parameter_name = 'registered';
  assert v_n = 0,
    'de kolom "registered" zit nog in tournament_signup_card of my_calendar';
  raise notice 'OK  het aantal inschrijvingen komt uit geen van beide RPCs nog terug';
end $$;

rollback;
