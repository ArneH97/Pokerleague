-- Tests voor wat er als inleg meeweegt in de league.
--
-- Bij een freezeout is dat eenvoudig: wat je betaalt gaat naar de pot. Bij
-- een bountytornooi staat de helft van je geld op de hoofden van de anderen,
-- en dat is net zo goed inzet — je kan het terugwinnen. De rake niet; die
-- komt nooit meer op tafel.
--
-- Zonder dit onderscheid gold The Hunt bij Cutoff (€20 pot + €20 bounty +
-- €10 rake) als een avond van twintig euro, en woog de duurste avond van de
-- kalender lichter dan een gewone €30-freezeout.

begin;

do $$
declare
  v_league jsonb := '{"multiplier":10,"exponent":0.75,"buyin_ref":30,"buyin_weight":0.5}'::jsonb;
begin
  -- ----------------------------------------------- wat de inzet is, per vorm
  assert public.stake_cents(3000, 0, 'none') = 3000,
    'een freezeout van €30 hoort €30 inzet te zijn';
  assert public.stake_cents(2000, 2000, 'fixed') = 4000,
    'pot plus bounty hoort samen €40 te zijn';
  assert public.stake_cents(2000, 2000, 'progressive') = 4000,
    'ook bij een progressieve bounty telt de bounty mee';
  assert public.stake_cents(2000, 2000, 'none') = 2000,
    'zonder bountyspel hoort een ingevuld bountybedrag niet mee te tellen';
  assert public.stake_cents(4000, null, 'fixed') = 4000,
    'een leeg bountybedrag hoort als nul te tellen';
  raise notice 'OK  de inzet is pot plus bounty, en de rake telt niet mee';

  -- ------------------------------------- en wat dat met de punten doet
  -- The Hunt tegenover een gewone avond van dertig euro, dertien spelers.
  declare
    v_hunt_oud numeric := public.calc_points('sqrt_ratio', v_league, 1, 13, 0, 2000, 0, 3);
    v_hunt_nu  numeric := public.calc_points('sqrt_ratio', v_league, 1, 13, 0,
                            public.stake_cents(2000, 2000, 'fixed'), 0, 3);
    v_dertig   numeric := public.calc_points('sqrt_ratio', v_league, 1, 13, 0, 3000, 0, 3);
  begin
    assert v_hunt_oud < v_dertig,
      'de opzet klopt niet: met alleen de pot hoorde The Hunt lichter te wegen';
    assert v_hunt_nu > v_dertig,
      format('The Hunt (%s) hoort zwaarder te wegen dan een €30-avond (%s)',
             v_hunt_nu, v_dertig);
    raise notice 'OK  The Hunt gaat van % naar % punten, tegenover % voor een €30-avond',
      v_hunt_oud, v_hunt_nu, v_dertig;
  end;

  -- Een freezeout mag niet verschuiven. Dit raakt elke club op het platform.
  assert public.calc_points('sqrt_ratio', v_league, 1, 13, 0, 3000, 0, 3)
       = public.calc_points('sqrt_ratio', v_league, 1, 13, 0,
           public.stake_cents(3000, 0, 'none'), 0, 3),
    'een freezeout kreeg ineens andere punten';
  raise notice 'OK  voor een freezeout verandert er niets';
end $$;

-- ---------------------------------------------------------------------------
-- En de hele keten: afsluiten, herrekenen, verzetten
-- ---------------------------------------------------------------------------
-- Drie plekken rekenen punten uit. Reken er één anders dan de andere, dan
-- veranderen de punten van een avond zodra je hem aanraakt — en dat is het
-- soort fout dat je pas in februari ziet.

do $$
declare
  v_club uuid; v_rc uuid; v_season uuid; v_t uuid;
  v_baas uuid := gen_random_uuid();
  v_tps uuid[] := array[]::uuid[]; i int;
  v_na_afsluiten numeric; v_na_herrekenen numeric; v_verwacht numeric;
begin
  insert into auth.users (id, email) values (v_baas, format('baas-%s@test.be', substr(v_baas::text,1,8)));

  insert into clubs (slug, name, compliance)
  values ('iz-' || substr(gen_random_uuid()::text, 1, 10), 'Inzettest',
          jsonb_build_object('enforce', 'off'))
  returning id into v_club;
  insert into club_members (club_id, user_id, role) values (v_club, v_baas, 'owner');

  insert into ranking_configs (club_id, name, method, params, bonus_entry)
  values (v_club, 'League', 'sqrt_ratio',
          '{"multiplier":10,"exponent":0.75,"buyin_ref":30,"buyin_weight":0.5}'::jsonb, 3)
  returning id into v_rc;

  insert into seasons (club_id, name, starts_on, ranking_config_id, is_active)
  values (v_club, 'League', current_date - 5, v_rc, true)
  returning id into v_season;

  -- Een avond in de vorm van The Hunt.
  insert into tournaments (club_id, season_id, name, scheduled_at, status,
                           buyin_cents, fee_cents, bounty_cents, bounty_mode,
                           starting_stack, player_visibility)
  values (v_club, v_season, 'De Jacht', now() - interval '1 day', 'running',
          2000, 1000, 2000, 'fixed', 40000, 'public')
  returning id into v_t;

  for i in 1 .. 13 loop
    v_tps := v_tps || public.floor_add_entry(
      v_t, null, format('Speler %s', i),
      format('iz%s-%s@test.be', i, substr(gen_random_uuid()::text, 1, 8)));
  end loop;
  for i in 1 .. 12 loop perform public.floor_eliminate(v_tps[i], null); end loop;
  perform public.floor_finish_tournament(v_t);

  v_verwacht := public.calc_points(
    'sqrt_ratio', '{"multiplier":10,"exponent":0.75,"buyin_ref":30,"buyin_weight":0.5}'::jsonb,
    1, 13, 0, 4000, 0, 3);

  select points into v_na_afsluiten from tournament_results
   where tournament_id = v_t and position = 1;
  assert v_na_afsluiten = v_verwacht,
    format('afsluiten gaf de winnaar % punten in plaats van %', v_na_afsluiten, v_verwacht);
  raise notice 'OK  bij het afsluiten telt de bounty mee: % punten voor de winnaar', v_na_afsluiten;

  perform set_config('request.jwt.claim.sub', v_baas::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  perform public.season_recompute_points(v_season);
  select points into v_na_herrekenen from tournament_results
   where tournament_id = v_t and position = 1;
  assert v_na_herrekenen = v_na_afsluiten,
    format('herrekenen veranderde de punten: % werd %', v_na_afsluiten, v_na_herrekenen);
  raise notice 'OK  herrekenen komt op hetzelfde uit als afsluiten';

  -- Even los en weer terug: ook het verzetten hoort hetzelfde te rekenen.
  perform public.tournament_set_season(v_t, null);
  perform public.tournament_set_season(v_t, v_season);
  select points into v_na_herrekenen from tournament_results
   where tournament_id = v_t and position = 1;
  assert v_na_herrekenen = v_na_afsluiten,
    format('verzetten veranderde de punten: % werd %', v_na_afsluiten, v_na_herrekenen);
  raise notice 'OK  een avond verzetten komt op hetzelfde uit';

  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);
end $$;

rollback;
