-- Tests voor de prijzenverdeling die de floor zelf zet, en de bubbel.
-- Draait in een transactie die terugrolt.

begin;

do $$
declare
  v_club uuid; v_rc uuid; v_season uuid; v_pt uuid; v_tour uuid;
  v_tps uuid[] := array[]::uuid[]; v_tp uuid;
  i int; v_n int; v_sum int; v_pot int; v_geweigerd int := 0;
  v_amounts int[];
begin
  insert into clubs (slug, name, compliance)
  values ('t-' || substr(gen_random_uuid()::text, 1, 12), 'Payoutclub',
          jsonb_build_object('enforce','off'))
  returning id into v_club;
  insert into ranking_configs (club_id, name, method, params)
  values (v_club, 'R', 'sqrt_ratio', '{"multiplier":10}') returning id into v_rc;
  insert into seasons (club_id, name, starts_on, ranking_config_id)
  values (v_club, 'S', current_date, v_rc) returning id into v_season;
  insert into payout_templates (club_id, name, tiers, rounding)
  values (v_club, 'P', '[{"min_entries":2,"max_entries":99,"percentages":[50,30,20]}]'::jsonb, 500)
  returning id into v_pt;

  insert into tournaments (club_id, season_id, payout_template_id, name, scheduled_at,
                           status, buyin_cents, starting_stack)
  values (v_club, v_season, v_pt, 'Payout', now(), 'running', 2000, 20000)
  returning id into v_tour;

  -- Dertig spelers: pot 60000 cent.
  for i in 1 .. 30 loop
    v_tp := public.floor_add_entry(v_tour, null, format('S%s', i), null, 'test');
    v_tps := v_tps || v_tp;
  end loop;

  select coalesce(sum(amount_cents),0) into v_pot from buyins
  where tournament_id = v_tour and not is_void;
  assert v_pot = 60000, format('pot verwacht 60000, kreeg %s', v_pot);

  -- Zonder override volgt hij het sjabloon: drie plaatsen.
  select count(*) into v_n from public.tournament_prizes(v_tour);
  assert v_n = 3, format('sjabloon geeft 3 plaatsen, kreeg %s', v_n);

  -- Voorstel voor zes plaatsen. Som moet exact de pot zijn.
  select count(*), coalesce(sum(amount_cents),0)
  into v_n, v_sum from public.suggest_payouts(v_tour, 6, 0);
  assert v_n = 6, format('verwacht 6 plaatsen, kreeg %s', v_n);
  assert v_sum = 60000, format('voorstel telt op tot %s in plaats van 60000', v_sum);

  -- Aflopend: plaats 1 hoort het meeste te krijgen.
  assert (select amount_cents from public.suggest_payouts(v_tour, 6, 0) where place = 1)
       > (select amount_cents from public.suggest_payouts(v_tour, 6, 0) where place = 2),
    'de eerste plaats hoort meer te krijgen dan de tweede';
  assert (select amount_cents from public.suggest_payouts(v_tour, 6, 0) where place = 6) > 0,
    'de laatste betaalde plaats mag niet op nul staan';

  -- Met bubbel: één plaats erbij, en die gaat van de pot af.
  select count(*), coalesce(sum(amount_cents),0)
  into v_n, v_sum from public.suggest_payouts(v_tour, 6, 2000);
  assert v_n = 7, format('met bubbel verwacht 7 plaatsen, kreeg %s', v_n);
  assert v_sum = 60000, format('met bubbel telt het op tot %s in plaats van 60000', v_sum);
  assert (select amount_cents from public.suggest_payouts(v_tour, 6, 2000) where place = 7) = 2000,
    'de bubbel hoort precies de inleg terug te krijgen';

  -- Vastleggen.
  select array_agg(amount_cents order by place) into v_amounts
  from public.suggest_payouts(v_tour, 6, 2000);
  v_n := public.set_payouts(v_tour, v_amounts);
  assert v_n = 7, 'er hadden 7 plaatsen vastgelegd moeten worden';
  assert (select paid_places from tournaments where id = v_tour) = 7,
    'paid_places werd niet bijgewerkt';

  -- Vanaf nu volgt de ladder de override, niet meer het sjabloon.
  select count(*) into v_n from public.tournament_prizes(v_tour);
  assert v_n = 7, format('de ladder hoort nu 7 plaatsen te tellen, kreeg %s', v_n);

  -- Een verdeling die niet optelt tot de pot wordt geweigerd.
  begin
    perform public.set_payouts(v_tour, array[1000, 1000]);
  exception when check_violation then v_geweigerd := v_geweigerd + 1;
  end;
  assert v_geweigerd = 1, 'een verdeling die niet klopt hoort geweigerd te worden';

  -- Afsluiten betaalt uit volgens de override, bubbel inbegrepen.
  perform public.floor_finish_tournament(v_tour);
  select coalesce(sum(prize_cents),0) into v_sum from tournament_results
  where tournament_id = v_tour;
  assert v_sum = 60000, format('uitbetaald %s <> pot 60000', v_sum);

  select count(*) into v_n from tournament_results
  where tournament_id = v_tour and prize_cents > 0;
  assert v_n = 7, format('verwacht 7 spelers in het geld, kreeg %s', v_n);

  assert (select prize_cents from tournament_results
          where tournament_id = v_tour and position = 7) = 2000,
    'de bubbel kreeg zijn inleg niet terug';

  raise notice 'prijzenverdeling OK: 6 plaatsen + bubbel, som klopt met de pot';
end $$;

-- ---------------------------------------------------------------------------
-- Terug naar het sjabloon, en de rechten
-- ---------------------------------------------------------------------------

do $$
declare
  v_club uuid; v_pt uuid; v_tour uuid; v_n int; v_geweigerd int := 0;
begin
  insert into clubs (slug, name, compliance)
  values ('t-' || substr(gen_random_uuid()::text, 1, 12), 'Terug',
          jsonb_build_object('enforce','off'))
  returning id into v_club;
  insert into payout_templates (club_id, name, tiers, rounding)
  values (v_club, 'P', '[{"min_entries":1,"max_entries":99,"percentages":[70,30]}]'::jsonb, 500)
  returning id into v_pt;
  insert into tournaments (club_id, payout_template_id, name, scheduled_at, status,
                           buyin_cents, starting_stack)
  values (v_club, v_pt, 'T', now(), 'running', 2000, 20000) returning id into v_tour;

  perform public.floor_add_entry(v_tour, null, 'A', null, 't');
  perform public.floor_add_entry(v_tour, null, 'B', null, 't');
  perform public.set_payouts(v_tour, array[4000]);
  assert (select count(*) from public.tournament_prizes(v_tour)) = 1,
    'de override werd niet gevolgd';

  perform public.clear_payouts(v_tour);
  assert (select payout_override from tournaments where id = v_tour) is null,
    'de override werd niet gewist';
  assert (select count(*) from public.tournament_prizes(v_tour)) = 2,
    'na het wissen hoort het sjabloon weer te gelden';

  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', gen_random_uuid()::text, true);

  begin perform * from public.suggest_payouts(v_tour, 3, 0);
  exception when insufficient_privilege then v_geweigerd := v_geweigerd + 1; end;
  begin perform public.set_payouts(v_tour, array[4000]);
  exception when insufficient_privilege then v_geweigerd := v_geweigerd + 1; end;
  begin perform public.clear_payouts(v_tour);
  exception when insufficient_privilege then v_geweigerd := v_geweigerd + 1; end;

  perform set_config('request.jwt.claim.role', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  assert v_geweigerd = 3, format('verwacht 3 weigeringen, kreeg %s', v_geweigerd);

  raise notice 'override OK: wissen werkt, buitenstaanders geweigerd';
end $$;

rollback;
