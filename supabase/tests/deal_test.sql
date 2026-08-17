-- Tests voor de deal aan de finaletafel.
-- Draait in een transactie die terugrolt.

begin;

do $$
declare
  v_club uuid; v_rc uuid; v_season uuid; v_pt uuid; v_tour uuid;
  v_tps uuid[] := array[]::uuid[]; v_tp uuid;
  i int; v_n int; v_pot int; v_paid int; v_deal uuid;
  v_shares jsonb; v_geweigerd int := 0;
begin
  insert into clubs (slug, name, compliance)
  values ('t-' || substr(gen_random_uuid()::text, 1, 12), 'Dealclub',
          jsonb_build_object('enforce','off'))
  returning id into v_club;
  insert into ranking_configs (club_id, name, method, params)
  values (v_club, 'R', 'sqrt_ratio', '{"multiplier":10}') returning id into v_rc;
  insert into seasons (club_id, name, starts_on, ranking_config_id)
  values (v_club, 'S', current_date, v_rc) returning id into v_season;
  insert into payout_templates (club_id, name, tiers, rounding)
  values (v_club, 'P', '[{"min_entries":2,"max_entries":99,"percentages":[50,30,20]}]'::jsonb, 100)
  returning id into v_pt;

  insert into tournaments (club_id, season_id, payout_template_id, name, scheduled_at,
                           status, buyin_cents, starting_stack)
  values (v_club, v_season, v_pt, 'Deal', now(), 'running', 2000, 20000)
  returning id into v_tour;

  for i in 1 .. 5 loop
    v_tp := public.floor_add_entry(v_tour, null, format('S%s', i), null, 'test');
    v_tps := v_tps || v_tp;
  end loop;

  -- Pot: 5 x 2000 = 10000. Ladder: 50/30/20 -> 5000 / 3000 / 2000.
  select count(*) into v_n from public.tournament_prizes(v_tour);
  assert v_n = 3, format('verwacht 3 betaalde plaatsen, kreeg %s', v_n);
  select amount_cents into v_n from public.tournament_prizes(v_tour) where place = 1;
  assert v_n = 5000, format('plaats 1 verwacht 5000, kreeg %s', v_n);

  -- Twee spelers eruit, drie blijven over: er valt 5000+3000+2000 te verdelen.
  perform public.floor_eliminate(v_tps[5], null);
  perform public.floor_eliminate(v_tps[4], null);

  -- Chipstanden voor de finaletafel.
  update tournament_players set chip_count = 60000 where id = v_tps[1];
  update tournament_players set chip_count = 25000 where id = v_tps[2];
  update tournament_players set chip_count = 15000 where id = v_tps[3];

  -- Voorstel: samen exact de resterende 10000 cent.
  v_shares := jsonb_build_array(
    jsonb_build_object('tournament_player_id', v_tps[1], 'name', 'S1', 'chips', 60000, 'agreed_cents', 4200),
    jsonb_build_object('tournament_player_id', v_tps[2], 'name', 'S2', 'chips', 25000, 'agreed_cents', 3200),
    jsonb_build_object('tournament_player_id', v_tps[3], 'name', 'S3', 'chips', 15000, 'agreed_cents', 2600)
  );

  v_deal := public.deal_propose(v_tour, 'icm', v_shares);
  assert (select count(*) from tournament_deals
          where tournament_id = v_tour and status = 'proposed') = 1,
    'er hoort precies één openstaand voorstel te zijn';
  assert (select pool_cents from tournament_deals where id = v_deal) = 10000,
    'de pot van het voorstel klopt niet';

  -- Een tweede voorstel vervangt het eerste in plaats van ernaast te komen.
  perform public.deal_propose(v_tour, 'chipchop', v_shares);
  assert (select count(*) from tournament_deals
          where tournament_id = v_tour and status = 'proposed') = 1,
    'er mag maar één voorstel tegelijk open staan';
  assert (select status from tournament_deals where id = v_deal) = 'rejected',
    'het vorige voorstel hoort ingetrokken te zijn';
  assert (select count(*) from tournament_deals where tournament_id = v_tour) = 2,
    'het spoor van de eerste onderhandeling hoort te blijven';

  -- Akkoord: tornooi eindigt met deze bedragen.
  v_n := public.deal_accept(v_tour);
  assert v_n = 5, format('verwacht 5 resultaatrijen, kreeg %s', v_n);
  assert (select status from tournaments where id = v_tour) = 'finished',
    'het tornooi staat niet op afgelopen';

  -- De grootste stapel wint, maar krijgt het afgesproken bedrag en niet 5000.
  select prize_cents into v_n
  from tournament_results r
  join tournament_players tp on tp.player_id = r.player_id and tp.tournament_id = v_tour
  where r.tournament_id = v_tour and tp.id = v_tps[1];
  assert v_n = 4200, format('S1 hoorde 4200 te krijgen, kreeg %s', v_n);

  select prize_cents into v_n
  from tournament_results r
  join tournament_players tp on tp.player_id = r.player_id and tp.tournament_id = v_tour
  where r.tournament_id = v_tour and tp.id = v_tps[3];
  assert v_n = 2600, format('S3 hoorde 2600 te krijgen, kreeg %s', v_n);

  -- Wie al uitgeschakeld was krijgt nog altijd niets, en de pot klopt.
  select coalesce(sum(amount_cents),0) into v_pot from buyins
  where tournament_id = v_tour and not is_void;
  select coalesce(sum(prize_cents),0) into v_paid from tournament_results
  where tournament_id = v_tour;
  assert v_paid = v_pot, format('uitbetaald %s <> pot %s', v_paid, v_pot);

  -- Punten blijven van de eindstand, niet van de deal.
  assert (select points from tournament_results r
          join tournament_players tp on tp.player_id = r.player_id and tp.tournament_id = v_tour
          where r.tournament_id = v_tour and tp.id = v_tps[1]) > 0,
    'punten horen gewoon berekend te zijn';

  raise notice 'deal OK: voorstel, vervanging, akkoord en uitbetaling kloppen';
end $$;

-- ---------------------------------------------------------------------------
-- Rechten en grenzen
-- ---------------------------------------------------------------------------

do $$
declare
  v_club uuid; v_tour uuid; v_tp uuid; v_geweigerd int := 0; v_shares jsonb;
begin
  insert into clubs (slug, name, compliance)
  values ('t-' || substr(gen_random_uuid()::text, 1, 12), 'Grenzen',
          jsonb_build_object('enforce','off'))
  returning id into v_club;
  insert into tournaments (club_id, name, scheduled_at, status, buyin_cents, starting_stack)
  values (v_club, 'X', now(), 'running', 2000, 20000) returning id into v_tour;
  v_tp := public.floor_add_entry(v_tour, null, 'Eenling', null, 'test');

  -- Eén speler is geen deal.
  begin
    perform public.deal_propose(v_tour, 'icm', jsonb_build_array(
      jsonb_build_object('tournament_player_id', v_tp, 'agreed_cents', 1000)));
  exception when check_violation then v_geweigerd := v_geweigerd + 1;
  end;

  -- Zonder voorstel valt er niets te bevestigen.
  begin perform public.deal_accept(v_tour);
  exception when check_violation then v_geweigerd := v_geweigerd + 1;
  end;

  assert v_geweigerd = 2, format('verwacht 2 weigeringen, kreeg %s', v_geweigerd);

  -- Een buitenstaander raakt er niet aan.
  v_geweigerd := 0;
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', gen_random_uuid()::text, true);
  v_shares := jsonb_build_array(
    jsonb_build_object('tournament_player_id', v_tp, 'agreed_cents', 500),
    jsonb_build_object('tournament_player_id', v_tp, 'agreed_cents', 500));

  begin perform public.deal_propose(v_tour, 'icm', v_shares);
  exception when insufficient_privilege then v_geweigerd := v_geweigerd + 1; end;
  begin perform public.deal_accept(v_tour);
  exception when insufficient_privilege then v_geweigerd := v_geweigerd + 1; end;
  begin perform * from public.tournament_prizes(v_tour);
  exception when insufficient_privilege then v_geweigerd := v_geweigerd + 1; end;

  perform set_config('request.jwt.claim.role', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  assert v_geweigerd = 3, format('verwacht 3 weigeringen, kreeg %s', v_geweigerd);

  raise notice 'dealrechten OK: grenzen en buitenstaanders geweigerd';
end $$;

rollback;
