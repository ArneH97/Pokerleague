-- Tests voor een gedeelde eindplaats.
--
-- Wat hier vastligt is vooral één getal: de avond mag niet méér punten
-- weggeven omdat er gedeald is. Dat is het verschil tussen een deal die het
-- geld verdeelt en een deal die het klassement bespeelt.

begin;

do $$
declare
  v_league jsonb := '{"multiplier":10,"exponent":0.75,"buyin_ref":30,"buyin_weight":0.5}'::jsonb;
  v1 numeric; v2 numeric; v3 numeric; v_gedeeld numeric;
begin
  v1 := public.calc_points('sqrt_ratio', v_league, 1, 20, 0, 3000, 0, 3);
  v2 := public.calc_points('sqrt_ratio', v_league, 2, 20, 0, 3000, 0, 3);
  v3 := public.calc_points('sqrt_ratio', v_league, 3, 20, 0, 3000, 0, 3);
  assert v1 = 48 and v2 = 30 and v3 = 23,
    format('de opzet klopt niet: %s / %s / %s', v1, v2, v3);

  v_gedeeld := public.calc_points_shared('sqrt_ratio', v_league, 1, 3, 20, 0, 3000, 0, 3);
  assert v_gedeeld = round((v1 + v2 + v3) / 3, 0),
    format('een gedeelde eerste plaats hoort %s te geven, gaf %s',
           round((v1 + v2 + v3) / 3, 0), v_gedeeld);
  assert v_gedeeld = 34, format('34 punten verwacht, kreeg %s', v_gedeeld);
  raise notice 'OK  drie samen eerste krijgen elk % punten in plaats van 48 / 30 / 23', v_gedeeld;

  -- En het totaal blijft gelijk: dat is de hele reden voor het gemiddelde.
  assert abs(v_gedeeld * 3 - (v1 + v2 + v3)) <= 1,
    'de avond gaf samen een ander aantal punten weg dan zonder deal';
  raise notice 'OK  de avond geeft evenveel punten weg als zonder deal';

  -- Eén speler op één plaats is gewoon calc_points.
  assert public.calc_points_shared('sqrt_ratio', v_league, 5, 5, 20, 0, 3000, 0, 3)
       = public.calc_points('sqrt_ratio', v_league, 5, 20, 0, 3000, 0, 3),
    'een ongedeelde plaats rekende anders dan vroeger';
  raise notice 'OK  zonder deling rekent hij precies zoals calc_points';
end $$;

-- ---------------------------------------------------------------------------
-- Een hele avond met een deal erop
-- ---------------------------------------------------------------------------

do $$
declare
  v_club uuid; v_rc uuid; v_season uuid; v_t uuid;
  v_baas uuid := gen_random_uuid();
  v_tps uuid[] := array[]::uuid[]; i int;
  v_shares jsonb;
  v_plaatsen int[]; v_punten numeric[];
  v_som_gedeeld numeric; v_som_normaal numeric;
begin
  insert into auth.users (id, email) values (v_baas, format('b-%s@test.be', substr(v_baas::text,1,8)));

  insert into clubs (slug, name, compliance)
  values ('xa-' || substr(gen_random_uuid()::text, 1, 10), 'Exaequotest',
          jsonb_build_object('enforce', 'off'))
  returning id into v_club;
  insert into club_members (club_id, user_id, role) values (v_club, v_baas, 'owner');

  insert into ranking_configs (club_id, name, method, params, bonus_entry)
  values (v_club, 'League', 'sqrt_ratio',
          '{"multiplier":10,"exponent":0.75,"buyin_ref":30,"buyin_weight":0.5}'::jsonb, 3)
  returning id into v_rc;
  insert into seasons (club_id, name, starts_on, ranking_config_id, is_active)
  values (v_club, 'League', current_date - 1, v_rc, true)
  returning id into v_season;

  insert into tournaments (club_id, season_id, name, scheduled_at, status,
                           buyin_cents, fee_cents, starting_stack, player_visibility)
  values (v_club, v_season, 'Dealavond', now(), 'running', 3000, 0, 40000, 'public')
  returning id into v_t;

  for i in 1 .. 8 loop
    v_tps := v_tps || public.floor_add_entry(
      v_t, null, format('Speler %s', i),
      format('xa%s-%s@test.be', i, substr(gen_random_uuid()::text, 1, 8)));
  end loop;

  -- Vijf vallen af; drie blijven over en dealen voor hetzelfde bedrag.
  for i in 1 .. 5 loop perform public.floor_eliminate(v_tps[i], null); end loop;

  perform set_config('request.jwt.claim.sub', v_baas::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  v_shares := jsonb_build_array(
    jsonb_build_object('tournament_player_id', v_tps[6], 'agreed_cents', 8000),
    jsonb_build_object('tournament_player_id', v_tps[7], 'agreed_cents', 8000),
    jsonb_build_object('tournament_player_id', v_tps[8], 'agreed_cents', 8000));
  perform public.deal_propose(v_t, 'even', v_shares);
  perform public.deal_accept(v_t);

  -- --------------------------------------------- de plaatsen zelf
  select array_agg(finish_position order by finish_position)
    into v_plaatsen
  from tournament_players where id = any(array[v_tps[6], v_tps[7], v_tps[8]]);
  assert v_plaatsen = array[1, 1, 1],
    format('de drie dealers horen alledrie eerste te staan, staan op %s', v_plaatsen);

  assert (select finish_position from tournament_players where id = v_tps[5]) = 4,
    'de speler na de gedeelde plaatsen hoort vierde te worden, niet tweede';
  raise notice 'OK  drie samen eerste, en daarna volgt plaats vier';

  -- --------------------------------------------- en de punten
  select array_agg(distinct r.points) into v_punten
  from tournament_results r
  join tournament_players tp on tp.player_id = r.player_id
  where r.tournament_id = v_t and tp.id = any(array[v_tps[6], v_tps[7], v_tps[8]]);
  assert array_length(v_punten, 1) = 1,
    'de drie dealers kregen niet alledrie hetzelfde aantal punten';
  assert v_punten[1] = public.calc_points_shared(
           'sqrt_ratio', '{"multiplier":10,"exponent":0.75,"buyin_ref":30,"buyin_weight":0.5}'::jsonb,
           1, 3, 8, 0, 3000, 0, 3),
    format('de gedeelde punten kloppen niet: %s', v_punten[1]);
  assert (select shared_with from tournament_results r
          join tournament_players tp on tp.player_id = r.player_id
          where r.tournament_id = v_t and tp.id = v_tps[6]) = 3,
    'shared_with stond niet op drie';
  raise notice 'OK  elk van de drie krijgt % punten, en de uitslag onthoudt dat het gedeeld was',
    v_punten[1];

  -- Het prijzengeld komt uit de deal en niet uit de ladder.
  assert (select prize_cents from tournament_results r
          join tournament_players tp on tp.player_id = r.player_id
          where r.tournament_id = v_t and tp.id = v_tps[7]) = 8000,
    'het afgesproken bedrag kwam niet in de uitslag';
  raise notice 'OK  het geld blijft wat de tafel afsprak';

  -- --------------------------------- de avond geeft niet meer punten weg
  select sum(points) into v_som_gedeeld from tournament_results where tournament_id = v_t;
  select sum(public.calc_points(
           'sqrt_ratio', '{"multiplier":10,"exponent":0.75,"buyin_ref":30,"buyin_weight":0.5}'::jsonb,
           g, 8, 0, 3000, 0, 3))
    into v_som_normaal
  from generate_series(1, 8) g;
  assert abs(v_som_gedeeld - v_som_normaal) <= 2,
    format('de avond gaf %s punten weg, zonder deal zou dat %s zijn',
           v_som_gedeeld, v_som_normaal);
  raise notice 'OK  de avond gaf % punten weg, evenveel als zonder deal (%)',
    v_som_gedeeld, v_som_normaal;

  -- ------------------------------------- en herrekenen verandert er niets aan
  perform public.season_recompute_points(v_season);
  assert (select count(distinct points) from tournament_results r
          join tournament_players tp on tp.player_id = r.player_id
          where r.tournament_id = v_t and tp.id = any(array[v_tps[6], v_tps[7], v_tps[8]])) = 1,
    'na het herrekenen liepen de drie dealers uit elkaar';
  assert (select max(points) from tournament_results r
          join tournament_players tp on tp.player_id = r.player_id
          where r.tournament_id = v_t and tp.id = v_tps[6]) = v_punten[1],
    'het herrekenen gaf een ander getal dan het afsluiten';
  raise notice 'OK  een seizoen opnieuw doorrekenen houdt de gedeelde plaatsen aan';

  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);
end $$;

-- ---------------------------------------------------------------------------
-- Een ICM-deal verdeelt ongelijk, en dan is de volgorde wél gespeeld
-- ---------------------------------------------------------------------------

do $$
declare
  v_club uuid; v_t uuid; v_baas uuid := gen_random_uuid();
  v_tps uuid[] := array[]::uuid[]; i int; v_shares jsonb;
begin
  insert into auth.users (id, email) values (v_baas, format('b2-%s@test.be', substr(v_baas::text,1,8)));
  insert into clubs (slug, name, compliance)
  values ('xb-' || substr(gen_random_uuid()::text, 1, 10), 'ICMtest',
          jsonb_build_object('enforce', 'off'))
  returning id into v_club;
  insert into club_members (club_id, user_id, role) values (v_club, v_baas, 'owner');

  insert into tournaments (club_id, name, scheduled_at, status,
                           buyin_cents, fee_cents, starting_stack, player_visibility)
  values (v_club, 'ICM-avond', now(), 'running', 3000, 0, 40000, 'public')
  returning id into v_t;

  for i in 1 .. 5 loop
    v_tps := v_tps || public.floor_add_entry(
      v_t, null, format('Speler %s', i),
      format('xb%s-%s@test.be', i, substr(gen_random_uuid()::text, 1, 8)));
  end loop;
  for i in 1 .. 3 loop perform public.floor_eliminate(v_tps[i], null); end loop;

  -- De grootste stapel hoort eerste te worden.
  update tournament_players set chip_count = 90000 where id = v_tps[4];
  update tournament_players set chip_count = 60000 where id = v_tps[5];

  perform set_config('request.jwt.claim.sub', v_baas::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  v_shares := jsonb_build_array(
    jsonb_build_object('tournament_player_id', v_tps[4], 'agreed_cents', 9000),
    jsonb_build_object('tournament_player_id', v_tps[5], 'agreed_cents', 6000));
  perform public.deal_propose(v_t, 'icm', v_shares);
  perform public.deal_accept(v_t);

  assert (select finish_position from tournament_players where id = v_tps[4]) = 1,
    'de grootste stapel werd niet eerste na een ongelijke deal';
  assert (select finish_position from tournament_players where id = v_tps[5]) = 2,
    'de tweede stapel kreeg niet gewoon plaats twee';
  assert (select shared_with from tournament_results r
          join tournament_players tp on tp.player_id = r.player_id
          where r.tournament_id = v_t and tp.id = v_tps[4]) = 1,
    'een ongelijke deal maakte er toch een gedeelde plaats van';
  raise notice 'OK  bij een ongelijke deal blijft de volgorde staan';

  -- Tenzij de floor er zelf om vraagt.
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);
end $$;

-- ---------------------------------------------------------------------------
-- De markering overleeft een herberekening
-- ---------------------------------------------------------------------------

do $$
declare
  v_club uuid; v_t uuid; v_baas uuid := gen_random_uuid();
  v_tps uuid[] := array[]::uuid[]; i int;
begin
  insert into auth.users (id, email) values (v_baas, format('b3-%s@test.be', substr(v_baas::text,1,8)));
  insert into clubs (slug, name, compliance)
  values ('xc-' || substr(gen_random_uuid()::text, 1, 10), 'Hernummertest',
          jsonb_build_object('enforce', 'off'))
  returning id into v_club;
  insert into club_members (club_id, user_id, role) values (v_club, v_baas, 'owner');

  insert into tournaments (club_id, name, scheduled_at, status,
                           buyin_cents, fee_cents, starting_stack, max_reentries)
  values (v_club, 'Hernummeren', now(), 'running', 3000, 0, 40000, 3)
  returning id into v_t;

  for i in 1 .. 6 loop
    v_tps := v_tps || public.floor_add_entry(
      v_t, null, format('Speler %s', i),
      format('xc%s-%s@test.be', i, substr(gen_random_uuid()::text, 1, 8)));
  end loop;
  for i in 1 .. 4 loop perform public.floor_eliminate(v_tps[i], null); end loop;

  perform set_config('request.jwt.claim.sub', v_baas::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  -- Speler 3 en 4 vielen samen af en delen hun plaats.
  perform public.floor_set_tie(array[v_tps[3], v_tps[4]]);
  assert (select count(distinct finish_position) from tournament_players
          where id = any(array[v_tps[3], v_tps[4]])) = 1,
    'de twee kregen niet dezelfde plaats';
  raise notice 'OK  de floor kan twee spelers zelf ex aequo zetten';

  -- Een re-entry hernummert alles. De afspraak hoort dat te overleven.
  perform public.floor_rebuy(v_tps[1], 'reentry');
  assert (select count(distinct finish_position) from tournament_players
          where id = any(array[v_tps[3], v_tps[4]])) = 1,
    'de gedeelde plaats ging verloren bij een herberekening';
  raise notice 'OK  een gedeelde plaats overleeft een re-entry en een hernummering';

  -- En hij kan ze weer losmaken.
  perform public.floor_clear_tie(array[v_tps[3], v_tps[4]]);
  assert (select count(distinct finish_position) from tournament_players
          where id = any(array[v_tps[3], v_tps[4]])) = 2,
    'de twee bleven aan elkaar geplakt na het losmaken';
  raise notice 'OK  en losmaken kan ook';

  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);
end $$;

rollback;
