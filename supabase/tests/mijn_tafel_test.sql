-- Tests voor wat een speler aan tafel op zijn eigen pagina ziet.

begin;

do $$
declare
  v_club uuid; v_str uuid; v_pt uuid; v_tour uuid;
  v_ik uuid; v_user uuid := gen_random_uuid();
  v_tp uuid; v_tps uuid[] := array[]::uuid[]; i int;
  r record;
begin
  insert into auth.users (id, email) values (v_user, 'aantafel@test.be');

  insert into clubs (slug, name, compliance)
  values ('mt-' || substr(gen_random_uuid()::text, 1, 12), 'Tafeltest',
          jsonb_build_object('enforce','off'))
  returning id into v_club;

  -- Een structuur met een pauze op plek 3, zodat we kunnen nakijken wat er
  -- tijdens die pauze als "de blinds" geldt.
  insert into blind_structures (club_id, name) values (v_club, 'Struct') returning id into v_str;
  insert into blind_levels (structure_id, idx, small_blind, big_blind, ante, duration_s, is_break)
  values (v_str, 0, 100,  200,  0,    1200, false),
         (v_str, 1, 200,  400,  400,  1200, false),
         (v_str, 2, 0,    0,    0,    600,  true),
         (v_str, 3, 300,  600,  600,  1200, false),
         (v_str, 4, 500, 1000, 1000,  1200, false);

  insert into payout_templates (club_id, name, tiers)
  values (v_club, 'P', '[{"min_entries":2,"max_entries":99,"percentages":[50,30,20]}]'::jsonb)
  returning id into v_pt;

  insert into tournaments (club_id, structure_id, payout_template_id, name, scheduled_at,
                           status, buyin_cents, fee_cents, starting_stack, level_idx)
  values (v_club, v_str, v_pt, 'Avond', now(), 'running', 4000, 0, 40000, 1)
  returning id into v_tour;

  insert into players (display_name, email, auth_user_id, link_state)
  values ('Ik', 'aantafel@test.be', v_user, 'claimed')
  returning id into v_ik;

  v_tp := public.floor_add_entry(v_tour, v_ik);
  for i in 1 .. 4 loop
    v_tps := v_tps || public.floor_add_entry(
      v_tour, null, format('Speler %s', i),
      format('mt%s-%s@test.be', i, substr(gen_random_uuid()::text, 1, 8)));
  end loop;

  perform set_config('request.jwt.claim.sub', v_user::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  -- ---------------------------------------------------------------- blinds
  select * into r from public.my_live_tournaments() limit 1;
  assert r.big_blind = 400, format('de big blind hoort 400 te zijn op niveau 2, kreeg %s', r.big_blind);
  assert r.ante = 400, 'de ante klopt niet';
  assert r.next_big_blind = 600,
    format('het volgende speelniveau hoort 600 te geven (de pauze overslaan), kreeg %s', r.next_big_blind);
  assert not r.is_break, 'niveau 2 is geen pauze';
  raise notice 'OK  de blinds van dit moment en van het volgende speelniveau';

  -- Tijdens de pauze telt het eerstvolgende speelniveau.
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);
  update tournaments set level_idx = 2 where id = v_tour;
  perform set_config('request.jwt.claim.sub', v_user::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  select * into r from public.my_live_tournaments() limit 1;
  assert r.is_break, 'de pauze werd niet als pauze herkend';
  assert r.big_blind = 600,
    format('tijdens de pauze hoort de volgende big blind te gelden, kreeg %s', r.big_blind);
  raise notice 'OK  tijdens een pauze gelden de blinds van het volgende speelniveau';

  -- --------------------------------------------------------------- het veld
  assert r.players_left = 5, format('vijf spelers verwacht, kreeg %s', r.players_left);
  assert r.chips_in_play = 200000,
    format('vijf startstapels horen 200.000 te zijn, kreeg %s', r.chips_in_play);
  assert r.avg_stack = 40000, format('gemiddelde hoort 40.000 te zijn, kreeg %s', r.avg_stack);
  assert r.paid_places = 3, format('drie betaalde plaatsen verwacht, kreeg %s', r.paid_places);
  raise notice 'OK  veldgrootte, chips in spel, gemiddelde en betaalde plaatsen';

  -- ------------------------------------------------------------- mijn plaats
  -- Iedereen begint op de startstapel; dan is er nog niets te rangschikken
  -- dat betekenis heeft, maar de telling hoort wel te kloppen.
  assert r.ranked_players = 5, 'alle vijf de stapels horen mee te tellen';

  -- Nu wat verschil aanbrengen: twee spelers gaan mij voorbij.
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);
  update tournament_players set chip_count = 90000 where id = v_tps[1];
  update tournament_players set chip_count = 70000 where id = v_tps[2];
  update tournament_players set chip_count = 20000 where id = v_tps[3];
  update tournament_players set chip_count = null  where id = v_tps[4];
  update tournament_players set chip_count = 55000 where id = v_tp;
  perform set_config('request.jwt.claim.sub', v_user::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  select * into r from public.my_live_tournaments() limit 1;
  assert r.my_chips = 55000, 'mijn stapel klopt niet';
  assert r.my_rank = 3, format('ik hoor derde te staan, kreeg %s', r.my_rank);
  assert r.ranked_players = 4,
    format('vier ingevulde stapels verwacht, kreeg %s', r.ranked_players);
  raise notice 'OK  mijn plaats wordt gerekend over de ingevulde stapels';

  -- Wie zelf niets invulde, krijgt geen plaats in plaats van de laatste.
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);
  update tournament_players set chip_count = null where id = v_tp;
  perform set_config('request.jwt.claim.sub', v_user::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  select * into r from public.my_live_tournaments() limit 1;
  assert r.my_rank is null, 'zonder eigen stapel hoort er geen plaats te staan';
  assert r.ranked_players = 3, 'de telling van ingevulde stapels klopt niet meer';
  raise notice 'OK  zonder eigen aantal geen plaats, in plaats van de laatste plaats';

  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);
end $$;

rollback;
