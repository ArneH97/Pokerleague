-- Tests voor de leaguepuntentelling.
--
-- Twee dingen moeten kloppen en ze trekken aan elkaar. De nieuwe telling moet
-- winnen zwaarder laten wegen dan deelnemen — anders wint de trouwste bezoeker
-- en niet de beste speler. En ze mag geen enkele bestaande club raken, want
-- die hebben punten in hun geschiedenis staan die niet achteraf mogen
-- verschuiven.

begin;

do $$
declare
  v_oud numeric; v_nieuw numeric;
  v_winnaar numeric; v_laatste numeric; v_tweede numeric;
  v_twintig numeric; v_dertig numeric;
begin
  -- -------------------------------------------- wie niets instelt, verandert niets
  v_oud := public.calc_points('sqrt_ratio', '{"multiplier": 10}'::jsonb, 1, 20);
  assert v_oud = round(10 * sqrt(20::numeric) / sqrt(1::numeric), 0),
    format('de oude formule gaf iets anders: %s', v_oud);
  assert public.calc_points('sqrt_ratio', '{"multiplier": 10}'::jsonb, 20, 20) = 10,
    'de laatste plaats gaf niet meer exact de multiplier';
  raise notice 'OK  zonder exponent rekent sqrt_ratio precies zoals vroeger';

  -- -------------------------------------------- en met exponent wordt het steiler
  v_winnaar := public.calc_points('sqrt_ratio', '{"multiplier":10,"exponent":0.75}'::jsonb, 1, 20);
  v_tweede  := public.calc_points('sqrt_ratio', '{"multiplier":10,"exponent":0.75}'::jsonb, 2, 20);
  v_laatste := public.calc_points('sqrt_ratio', '{"multiplier":10,"exponent":0.75}'::jsonb, 20, 20);

  assert v_winnaar = 45, format('de winnaar hoort 45 te krijgen, kreeg %s', v_winnaar);
  assert v_laatste = 5,  format('de laatste hoort 5 te krijgen, kreeg %s', v_laatste);
  assert v_winnaar / v_laatste > 5,
    format('winnen hoort meer dan vijf keer zoveel te zijn als laatste worden, is %sx',
           round(v_winnaar / v_laatste, 1));
  assert v_winnaar > v_tweede * 1.4,
    'de winnaar hoort duidelijk boven de tweede uit te komen';
  raise notice 'OK  met exponent 0,75 is winnen %x zoveel als laatste worden (zonder deelnamebonus)',
    round(v_winnaar / v_laatste, 1);

  -- ------------------------------------------------ een groter veld is meer waard
  v_twintig := public.calc_points('sqrt_ratio', '{"multiplier":10,"exponent":0.75}'::jsonb, 1, 20);
  v_dertig  := public.calc_points('sqrt_ratio', '{"multiplier":10,"exponent":0.75}'::jsonb, 1, 30);
  assert v_dertig > v_twintig, 'een groter veld hoort meer op te leveren';
  assert v_dertig < v_twintig * 1.5,
    'een groter veld hoort niet zó veel meer op te leveren dat één avond de league beslist';
  raise notice 'OK  dertig spelers levert de winnaar % procent meer op dan twintig',
    round((v_dertig / v_twintig - 1) * 100);

  -- ------------------------------------------------------ de exponent is geklemd
  -- Een exponent van nul zou de plaats betekenisloos maken, een van vijf zou
  -- alleen de winnaar nog punten geven. Allebei geklemd op iets speelbaars.
  assert public.calc_points('sqrt_ratio', '{"multiplier":10,"exponent":0}'::jsonb, 20, 20)
       = public.calc_points('sqrt_ratio', '{"multiplier":10,"exponent":0.5}'::jsonb, 20, 20),
    'een exponent onder de helft werd niet opgetrokken';
  assert public.calc_points('sqrt_ratio', '{"multiplier":10,"exponent":9}'::jsonb, 2, 20)
       = public.calc_points('sqrt_ratio', '{"multiplier":10,"exponent":1.5}'::jsonb, 2, 20),
    'een exponent boven anderhalf werd niet afgetopt';
  raise notice 'OK  een onmogelijke exponent wordt naar iets speelbaars getrokken';

  -- -------------------------------------------- deelname telt, maar weinig
  v_nieuw := public.calc_points('sqrt_ratio', '{"multiplier":10,"exponent":0.75}'::jsonb,
                                20, 20, 0, 0, 0, 3);
  assert v_nieuw = v_laatste + 3, 'de deelnamebonus kwam er niet bij';
  assert v_nieuw < v_winnaar / 5,
    format('laatste worden mét deelnamebonus (%s) hoort ver onder winnen (%s) te blijven',
           v_nieuw, v_winnaar);
  raise notice 'OK  deelname levert iets op, maar een overwinning is zes avonden waard';
end $$;

-- ---------------------------------------------------------------------------
-- Een heel seizoen opnieuw doorrekenen
-- ---------------------------------------------------------------------------

do $$
declare
  v_club uuid; v_rc uuid; v_season uuid; v_t uuid;
  v_baas uuid := gen_random_uuid();
  v_tps uuid[] := array[]::uuid[]; i int;
  v_voor numeric; v_na numeric; v_n int;
begin
  insert into auth.users (id, email) values (v_baas, format('baas-%s@test.be', substr(v_baas::text,1,8)));

  insert into clubs (slug, name, compliance)
  values ('lg-' || substr(gen_random_uuid()::text, 1, 12), 'Leaguetest',
          jsonb_build_object('enforce','off'))
  returning id into v_club;
  insert into club_members (club_id, user_id, role) values (v_club, v_baas, 'owner');

  -- Een avond die met de oude, vlakke telling is afgesloten.
  insert into ranking_configs (club_id, name, method, params, bonus_entry)
  values (v_club, 'Oud', 'sqrt_ratio', '{"multiplier": 10}'::jsonb, 0)
  returning id into v_rc;

  insert into seasons (club_id, name, starts_on, ranking_config_id)
  values (v_club, 'Seizoen', current_date - 30, v_rc)
  returning id into v_season;

  insert into tournaments (club_id, season_id, name, scheduled_at, status,
                           buyin_cents, fee_cents, starting_stack)
  values (v_club, v_season, 'Avond', now() - interval '3 days', 'running', 4000, 0, 40000)
  returning id into v_t;

  for i in 1 .. 8 loop
    v_tps := v_tps || public.floor_add_entry(
      v_t, null, format('Speler %s', i),
      format('lg%s-%s@test.be', i, substr(gen_random_uuid()::text, 1, 8)));
  end loop;
  for i in 1 .. 7 loop perform public.floor_eliminate(v_tps[i], null); end loop;
  perform public.floor_finish_tournament(v_t);

  select points into v_voor from tournament_results
   where tournament_id = v_t and position = 1;
  raise notice 'met de oude telling kreeg de winnaar % punten', v_voor;

  -- Nu stappen we over op de leaguetelling en rekenen het seizoen opnieuw door.
  update ranking_configs
  set params = '{"multiplier":10,"exponent":0.75}'::jsonb, bonus_entry = 3
  where id = v_rc;

  perform set_config('request.jwt.claim.sub', v_baas::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  v_n := public.season_recompute_points(v_season);
  assert v_n = 8, format('acht uitslagregels verwacht, kreeg %s', v_n);

  select points into v_na from tournament_results
   where tournament_id = v_t and position = 1;
  assert v_na <> v_voor, 'de punten van de winnaar veranderden niet';
  assert v_na = round(10 * sqrt(8::numeric) / power(1, 0.75), 0) + 3,
    format('de winnaar kreeg %s in plaats van de nieuwe telling', v_na);

  -- En de laatste plaats zakt, want dat is het hele punt.
  --
  -- Niet strenger dan een derde: dit is een veld van acht, en dan weegt de
  -- vaste deelnamebonus van drie punten relatief zwaar mee. Bij de twintig
  -- tot dertig spelers van een echte zondag zakt die verhouding vanzelf naar
  -- ongeveer een zesde. Een test die op acht spelers een zesde eist, zou het
  -- verkeerde gedrag afdwingen.
  assert (select points from tournament_results where tournament_id = v_t and position = 8)
       < (select points from tournament_results where tournament_id = v_t and position = 1) / 3,
    format('de laatste (%s) zakte niet ver genoeg onder de winnaar (%s)',
           (select points from tournament_results where tournament_id = v_t and position = 8),
           (select points from tournament_results where tournament_id = v_t and position = 1));
  raise notice 'OK  een heel seizoen opnieuw doorrekenen werkt, winnaar van % naar %', v_voor, v_na;

  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);

  -- ------------------------------------------------------------------ rechten
  perform set_config('request.jwt.claim.sub', gen_random_uuid()::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  begin
    perform public.season_recompute_points(v_season);
    raise exception 'een vreemde kon de punten van een seizoen herrekenen';
  exception when insufficient_privilege then
    raise notice 'OK  alleen owner of admin kan een seizoen opnieuw doorrekenen';
  end;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);
end $$;

rollback;
