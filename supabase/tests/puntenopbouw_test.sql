-- Tests voor de puntenopbouw per speler.
--
-- Het scherm trekt een streep onder de beste N avonden. Die streep moet
-- precies de streep zijn die de telling zelf trekt, anders staat er een
-- uitleg die niet klopt met de stand erboven — en dan is de uitleg erger dan
-- geen uitleg.

begin;

do $$
declare
  v_club uuid; v_rc uuid; v_season uuid; v_t uuid;
  v_baas uuid := gen_random_uuid();
  v_mails text[] := array[]::text[];
  v_tps uuid[]; i int; j int;
  v_speler uuid;
  v_rij record; v_regels int; v_tellend int;
  v_som numeric; v_stand record;
begin
  insert into auth.users (id, email) values (v_baas, format('b-%s@test.be', substr(v_baas::text,1,8)));

  insert into clubs (slug, name, compliance, public_names)
  values ('po-' || substr(gen_random_uuid()::text, 1, 10), 'Opbouwtest',
          jsonb_build_object('enforce', 'off'), true)
  returning id into v_club;
  insert into club_members (club_id, user_id, role) values (v_club, v_baas, 'owner');

  -- Beste drie van vijf tellen, drempel vier avonden.
  insert into ranking_configs (club_id, name, method, params, bonus_entry,
                               count_best_n, min_tournaments)
  values (v_club, 'League', 'sqrt_ratio',
          '{"multiplier":10,"exponent":0.75,"buyin_ref":30,"buyin_weight":0.5}'::jsonb,
          3, 3, 4)
  returning id into v_rc;

  insert into seasons (club_id, name, starts_on, ends_on, ranking_config_id, is_active)
  values (v_club, 'League', current_date - 30, current_date + 30, v_rc, true)
  returning id into v_season;

  for i in 1 .. 6 loop
    v_mails := v_mails || format('po%s-%s@test.be', i, substr(gen_random_uuid()::text,1,8));
  end loop;

  -- Vijf avonden. Onze speler (nummer 1) wordt om beurten eerste en laatste,
  -- zodat er écht iets af te strepen valt.
  for i in 1 .. 5 loop
    insert into tournaments (club_id, season_id, name, scheduled_at, status,
                             buyin_cents, fee_cents, bounty_cents, bounty_mode,
                             starting_stack, player_visibility)
    values (v_club, v_season, format('Avond %s', i), now() - (i || ' days')::interval,
            'running', 2000, 500, 2000, 'fixed', 40000, 'public')
    returning id into v_t;

    v_tps := array[]::uuid[];
    for j in 1 .. 6 loop
      v_tps := v_tps || public.floor_add_entry(v_t, null, format('Speler %s', j), v_mails[j]);
    end loop;

    if i <= 3 then
      -- Speler 1 wint: iedereen behalve hij valt af.
      for j in 2 .. 6 loop perform public.floor_eliminate(v_tps[j], null); end loop;
    else
      -- Speler 1 valt als eerste af en wordt dus laatste.
      perform public.floor_eliminate(v_tps[1], null);
      for j in 2 .. 5 loop perform public.floor_eliminate(v_tps[j], null); end loop;
    end if;
    perform public.floor_finish_tournament(v_t);
  end loop;

  select player_id into v_speler from tournament_results r
   where r.season_id = v_season order by r.points desc limit 1;

  -- ----------------------------------------------------- de opbouw zelf
  select count(*)::int into v_regels
  from public.club_public_player_season(
    (select slug from clubs where id = v_club), v_speler, v_season);
  assert v_regels = 5, format('vijf avonden verwacht, kreeg %s', v_regels);

  select count(*)::int into v_tellend
  from public.club_public_player_season(
    (select slug from clubs where id = v_club), v_speler, v_season)
  where counted;
  assert v_tellend = 3, format('drie tellende avonden verwacht, kreeg %s', v_tellend);
  raise notice 'OK  vijf avonden, waarvan drie meetellen';

  -- De volgorde is die van de telling: beste eerst, en de streep valt daar
  -- waar de beste-N ophoudt.
  select * into v_rij from public.club_public_player_season(
    (select slug from clubs where id = v_club), v_speler, v_season) limit 1;
  assert v_rij.counted, 'de beste avond telde niet mee';
  assert v_rij.place = 1, 'de bovenste regel was niet zijn beste avond';
  assert v_rij.entries = 6, 'het veld klopt niet';
  assert v_rij.stake_cents = 4000,
    format('de inzet hoort €40 te zijn (pot plus bounty), is %s cent', v_rij.stake_cents);
  assert v_rij.player_name is not null and v_rij.player_name <> '',
    'er kwam geen naam mee';
  raise notice 'OK  de bovenste regel is zijn beste avond, met het veld en de inzet erbij';

  assert not exists (
    select 1 from public.club_public_player_season(
      (select slug from clubs where id = v_club), v_speler, v_season) x
    where x.counted = false
      and x.points > (select min(y.points) from public.club_public_player_season(
        (select slug from clubs where id = v_club), v_speler, v_season) y
        where y.counted)),
    'een afgestreepte avond leverde meer op dan een die wel meetelt';
  raise notice 'OK  er wordt niets afgestreept dat beter was dan wat blijft staan';

  -- ------------------------------------- en de som klopt met de stand
  select sum(points) into v_som
  from public.club_public_player_season(
    (select slug from clubs where id = v_club), v_speler, v_season)
  where counted;

  select * into v_stand from public.club_public_season_standings(
    (select slug from clubs where id = v_club), v_season)
  where player_id = v_speler;

  assert v_stand.points = round(v_som, 0),
    format('de stand zegt % punten, de opbouw telt op tot %', v_stand.points, v_som);
  assert v_stand.counted = 3, 'de stand telde een ander aantal meetellende avonden';
  assert v_stand.tournaments = 5, 'de stand telde een ander aantal avonden';
  assert v_stand.qualified, 'vijf avonden hoort boven de drempel van vier te liggen';
  raise notice 'OK  de opbouw telt op tot exact wat er in de stand staat: % punten', v_stand.points;

  -- --------------------------------------------- en de regels van het seizoen
  declare v_reg record;
  begin
    select * into v_reg from public.club_public_season_rules(
      (select slug from clubs where id = v_club), v_season);
    assert v_reg.multiplier = 10 and v_reg.exponent = 0.75,
      'de formule kwam verkeerd terug';
    assert v_reg.buyin_ref = 30 and v_reg.buyin_weight = 0.5,
      'de inlegweging kwam verkeerd terug';
    assert v_reg.bonus_entry = 3, 'de deelnamebonus kwam verkeerd terug';
    assert v_reg.count_best_n = 3 and v_reg.min_tournaments = 4,
      'de twee drempels kwamen verkeerd terug';
    assert v_reg.season_name = 'League', 'de seizoensnaam kwam niet mee';
    raise notice 'OK  het scherm kan de formule opvragen in plaats van hem na te bouwen';
  end;

  -- Een exponent buiten de grenzen hoort geklemd terug te komen, net als in
  -- calc_points. Legt het scherm 9 uit terwijl de database met 1,5 rekent,
  -- dan klopt de uitleg niet.
  update ranking_configs
  set params = '{"multiplier":10,"exponent":9,"buyin_ref":30}'::jsonb
  where id = v_rc;
  assert (select exponent from public.club_public_season_rules(
            (select slug from clubs where id = v_club), v_season)) = 1.5,
    'een onmogelijke exponent kwam ongeklemd terug';
  raise notice 'OK  de uitleg toont dezelfde grenzen waar de telling mee rekent';
end $$;

rollback;
