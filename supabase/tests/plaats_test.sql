-- Tests voor de geschatte plaats.
--
-- De aanleiding: de plaats werd geteld over de spelers die hun stapel hadden
-- ingevuld. Op een gewone avond zijn dat er een handvol, en dan staat er
-- "1ste van 1" bij wie als enige iets doorgaf. Nu wordt ze geschat uit de
-- verhouding tot het gemiddelde, en dat gemiddelde volgt uit het geldregister.

begin;

do $$
declare
  v_club uuid; v_tour uuid; v_ik uuid; v_tp uuid;
  v_user uuid := gen_random_uuid();
  v_tps uuid[] := array[]::uuid[]; i int;
  r record;
begin
  insert into auth.users (id, email) values (v_user, 'plaats@test.be');

  insert into clubs (slug, name, compliance)
  values ('pl-' || substr(gen_random_uuid()::text, 1, 12), 'Plaatstest',
          jsonb_build_object('enforce','off'))
  returning id into v_club;

  -- Vijf spelers, elk 40.000: 200.000 in spel, gemiddeld 40.000.
  insert into tournaments (club_id, name, scheduled_at, status,
                           buyin_cents, fee_cents, starting_stack)
  values (v_club, 'Avond', now(), 'running', 4000, 0, 40000)
  returning id into v_tour;

  insert into players (display_name, email, auth_user_id, link_state)
  values ('Ik', 'plaats@test.be', v_user, 'claimed') returning id into v_ik;
  v_tp := public.floor_add_entry(v_tour, v_ik);

  for i in 1 .. 4 loop
    v_tps := v_tps || public.floor_add_entry(
      v_tour, null, format('Speler %s', i),
      format('pl%s-%s@test.be', i, substr(gen_random_uuid()::text, 1, 8)));
  end loop;

  -- Niemand vult iets in, behalve ik. Vroeger stond er dan "1ste van 1".
  for i in 1 .. 4 loop
    update tournament_players set chip_count = null where id = v_tps[i];
  end loop;

  perform set_config('request.jwt.claim.sub', v_user::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  -- ------------------------------------------------- precies het gemiddelde
  select * into r from public.my_live_tournaments() limit 1;
  assert r.avg_stack = 40000, format('gemiddeld 40.000 verwacht, kreeg %s', r.avg_stack);
  assert r.my_chips = 40000, 'de eigen stapel klopt niet';
  assert r.my_rank = 3,
    format('op het gemiddelde hoor je de derde van vijf te zijn, kreeg %s', r.my_rank);
  assert r.rank_estimated, 'dit hoort een schatting te zijn';
  assert r.players_left = 5, 'het veld hoort vijf spelers groot te zijn';
  raise notice 'OK  precies op het gemiddelde is de derde van vijf';

  -- --------------------------------------------------------- iets eronder
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);
  update tournament_players set chip_count = 34000 where id = v_tp;
  perform set_config('request.jwt.claim.sub', v_user::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  select * into r from public.my_live_tournaments() limit 1;
  assert r.my_rank = 3,
    format('iets onder het gemiddelde hoort nog de derde te zijn, kreeg %s', r.my_rank);
  raise notice 'OK  iets onder het gemiddelde blijft de derde van vijf';

  -- ------------------------------------------------------ ruim bovenaan
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);
  update tournament_players set chip_count = 120000 where id = v_tp;
  perform set_config('request.jwt.claim.sub', v_user::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  select * into r from public.my_live_tournaments() limit 1;
  assert r.my_rank = 1,
    format('met drie keer het gemiddelde hoor je bovenaan te staan, kreeg %s', r.my_rank);
  raise notice 'OK  ruim boven het gemiddelde is de eerste';

  -- ------------------------------------------------------------ bijna niets
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);
  update tournament_players set chip_count = 1000 where id = v_tp;
  perform set_config('request.jwt.claim.sub', v_user::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  select * into r from public.my_live_tournaments() limit 1;
  assert r.my_rank = 5,
    format('met bijna niets hoor je onderaan te staan, kreeg %s', r.my_rank);
  raise notice 'OK  bijna niets is de laatste van vijf';

  -- ------------------------------------- iedereen ingevuld: dan wordt geteld
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);
  update tournament_players set chip_count = 40000 where id = v_tp;
  update tournament_players set chip_count = 90000 where id = v_tps[1];
  update tournament_players set chip_count = 70000 where id = v_tps[2];
  update tournament_players set chip_count = 20000 where id = v_tps[3];
  update tournament_players set chip_count = 10000 where id = v_tps[4];
  perform set_config('request.jwt.claim.sub', v_user::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  select * into r from public.my_live_tournaments() limit 1;
  assert not r.rank_estimated, 'met alle stapels ingevuld hoort er geteld te worden';
  assert r.my_rank = 3, format('geteld hoor je de derde te zijn, kreeg %s', r.my_rank);
  assert r.ranked_players = 5, 'alle vijf de stapels horen mee te tellen';
  raise notice 'OK  weet iedereen zijn stapel, dan wordt er geteld in plaats van geschat';

  -- ------------------------------------------ zonder eigen aantal geen plaats
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);
  update tournament_players set chip_count = null where id = v_tp;
  perform set_config('request.jwt.claim.sub', v_user::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  select * into r from public.my_live_tournaments() limit 1;
  assert r.my_rank is null, 'zonder eigen stapel hoort er geen plaats te staan';
  assert not r.rank_estimated, 'zonder eigen stapel is er ook niets te schatten';
  raise notice 'OK  zonder eigen aantal staat er nog altijd geen plaats';

  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);
end $$;

rollback;
