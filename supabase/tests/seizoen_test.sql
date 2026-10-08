-- Tests voor het toewijzen van een avond aan een seizoen, en voor de
-- publieke seizoensstand.
--
-- Een avond verzetten is drie dingen tegelijk en het gaat mis als je er één
-- vergeet: het tornooi hangt aan het nieuwe seizoen, zijn uitslagen hangen
-- mee, en de punten in die uitslagen zijn herrekend met de telling van dat
-- seizoen. Doe je alleen het eerste, dan staat de avond in de league maar
-- draagt hij nog de punten van de oude telling — en dan is de stand verkeerd
-- op een manier die je pas in februari ziet.

begin;

do $$
declare
  v_club   uuid;
  v_slug   text := 'sz-' || substr(gen_random_uuid()::text, 1, 10);
  v_baas   uuid := gen_random_uuid();
  v_vreemd uuid := gen_random_uuid();
  v_oud_rc uuid; v_lg_rc uuid;
  v_oud_s  uuid; v_lg_s  uuid;
  v_t30 uuid; v_t50 uuid;
  v_tps uuid[]; i int;
  v_voor numeric; v_na numeric; v_na50 numeric;
  v_n int; v_rij record;
begin
  insert into auth.users (id, email) values
    (v_baas,   format('baas-%s@test.be', substr(v_baas::text, 1, 8))),
    (v_vreemd, format('vrmd-%s@test.be', substr(v_vreemd::text, 1, 8)));

  insert into clubs (slug, name, compliance, public_names)
  values (v_slug, 'Seizoentest', jsonb_build_object('enforce', 'off'), true)
  returning id into v_club;
  insert into club_members (club_id, user_id, role) values (v_club, v_baas, 'owner');

  -- De oude, vlakke huisranking en de league ernaast.
  insert into ranking_configs (club_id, name, method, params, bonus_entry, min_tournaments)
  values (v_club, 'Huis', 'sqrt_ratio', '{"multiplier": 10}'::jsonb, 0, 0)
  returning id into v_oud_rc;

  insert into ranking_configs (club_id, name, method, params, bonus_entry, min_tournaments)
  values (v_club, 'League', 'sqrt_ratio',
          '{"multiplier":10,"exponent":0.75,"buyin_ref":30,"buyin_weight":0.5}'::jsonb, 3, 2)
  returning id into v_lg_rc;

  insert into seasons (club_id, name, starts_on, ranking_config_id, is_active)
  values (v_club, 'Huisseizoen', current_date - 200, v_oud_rc, false)
  returning id into v_oud_s;

  insert into seasons (club_id, name, starts_on, ranking_config_id, is_active)
  values (v_club, 'League', current_date - 10, v_lg_rc, true)
  returning id into v_lg_s;

  -- Twee avonden met hetzelfde veld maar een andere inleg, allebei afgesloten
  -- met de oude telling en allebei publiek.
  insert into tournaments (club_id, season_id, name, scheduled_at, status,
                           buyin_cents, fee_cents, starting_stack, player_visibility)
  values (v_club, v_oud_s, 'Dertig', now() - interval '4 days', 'running',
          3000, 500, 40000, 'public')
  returning id into v_t30;

  insert into tournaments (club_id, season_id, name, scheduled_at, status,
                           buyin_cents, fee_cents, starting_stack, player_visibility)
  values (v_club, null, 'Vijftig', now() - interval '2 days', 'running',
          5000, 500, 40000, 'public')
  returning id into v_t50;

  -- Dezelfde acht spelers op beide avonden, want anders meet de stand het
  -- verkeerde: een league gaat over mensen die terugkomen.
  declare
    v_mails text[] := array[]::text[];
    v_t uuid;
    j int;
  begin
    for i in 1 .. 8 loop
      v_mails := v_mails || format('sz%s-%s@test.be', i, substr(gen_random_uuid()::text, 1, 8));
    end loop;

    foreach v_t in array array[v_t30, v_t50] loop
      v_tps := array[]::uuid[];
      for j in 1 .. 8 loop
        v_tps := v_tps || public.floor_add_entry(
          v_t, null, format('Speler %s', j), v_mails[j]);
      end loop;
      for j in 1 .. 7 loop perform public.floor_eliminate(v_tps[j], null); end loop;
      perform public.floor_finish_tournament(v_t);
    end loop;
  end;

  select points into v_voor from tournament_results
   where tournament_id = v_t30 and position = 1;
  assert v_voor = round(10 * sqrt(8::numeric), 0),
    format('de dertig-euroavond stond niet op de oude telling: %s', v_voor);

  perform set_config('request.jwt.claim.sub', v_baas::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  -- -------------------------------------------- het lijstje om aan te vinken
  select count(*)::int into v_n from public.season_tournaments(v_club);
  assert v_n = 2, format('het overzicht hoort twee avonden te tonen, toonde %s', v_n);

  select * into v_rij from public.season_tournaments(v_club) where name = 'Dertig';
  assert v_rij.season_name = 'Huisseizoen',
    format('het overzicht noemde het verkeerde seizoen: %s', v_rij.season_name);
  assert v_rij.results = 8, 'het overzicht telde de uitslagregels niet mee';
  assert v_rij.buyin_cents = 3000, 'het overzicht gaf de verkeerde inleg';

  select * into v_rij from public.season_tournaments(v_club) where name = 'Vijftig';
  assert v_rij.season_id is null and v_rij.season_name is null,
    'een avond zonder seizoen hoorde leeg te staan';
  raise notice 'OK  het overzicht toont per avond het seizoen, de inleg en de uitslagregels';

  -- ---------------------------------------------------- en het verzetten zelf
  v_n := public.tournament_set_season(v_t30, v_lg_s);
  assert v_n = 8, format('acht uitslagregels verwacht, kreeg %s', v_n);

  assert (select season_id from tournaments where id = v_t30) = v_lg_s,
    'het tornooi hing niet aan het nieuwe seizoen';
  assert not exists (select 1 from tournament_results
                     where tournament_id = v_t30 and season_id is distinct from v_lg_s),
    'de uitslagen verhuisden niet mee naar het nieuwe seizoen';

  select points into v_na from tournament_results
   where tournament_id = v_t30 and position = 1;
  assert v_na = round(10 * sqrt(8::numeric) / power(1, 0.75) * 1, 0) + 3,
    format('de punten van de dertig-euroavond zijn niet herrekend: %s', v_na);
  raise notice 'OK  een avond verzetten verhuist de uitslagen mee en rekent de punten opnieuw';

  -- En nu het hele punt van deze migratie: dezelfde avond, duurdere inleg,
  -- meer punten.
  perform public.tournament_set_season(v_t50, v_lg_s);
  select points into v_na50 from tournament_results
   where tournament_id = v_t50 and position = 1;
  assert v_na50 > v_na,
    format('de vijftig-euroavond (%s) gaf niet meer dan de dertig-euroavond (%s)', v_na50, v_na);
  raise notice 'OK  winnen op €50 levert % punten, op €30 maar % — de inleg weegt mee', v_na50, v_na;

  -- --------------------------------------- twee keer verzetten doet niets dubbel
  assert public.tournament_set_season(v_t50, v_lg_s) = 0,
    'nog eens hetzelfde seizoen zetten deed alsnog werk';
  raise notice 'OK  hetzelfde seizoen nog eens zetten verandert niets';

  -- ------------------------------------------------ en eruit halen kan ook
  perform public.tournament_set_season(v_t50, null);
  assert (select season_id from tournaments where id = v_t50) is null,
    'de avond kwam niet uit het seizoen';
  assert (select points from tournament_results where tournament_id = v_t50 and position = 1) = v_na50,
    'een avond uit de league halen zette zijn punten op nul';
  perform public.tournament_set_season(v_t50, v_lg_s);
  raise notice 'OK  een avond uit een seizoen halen laat zijn punten staan';

  -- ------------------------------------------------------- de publieke stand
  declare
    v_pub record;
    v_aantal int;
  begin
    select count(*)::int into v_aantal
    from public.club_public_season_standings(v_slug, v_lg_s);
    assert v_aantal = 8, format('acht spelers verwacht in de publieke stand, kreeg %s', v_aantal);

    select * into v_pub
    from public.club_public_season_standings(v_slug, v_lg_s)
    order by points desc limit 1;
    assert v_pub.player_name is not null and v_pub.player_name <> '',
      'de publieke stand gaf een lege naam';
    assert v_pub.tournaments = 2, 'de bovenste speler speelde twee avonden';
    assert v_pub.qualified, 'wie twee van de twee avonden speelde, hoort gekwalificeerd te zijn';
    assert v_pub.min_required = 2, 'de drempel van het seizoen kwam niet mee';
    raise notice 'OK  de publieke seizoensstand toont de league met drempel en al';

    -- Zonder seizoen meegeven hoort hij het nieuwste te pakken.
    select count(*)::int into v_aantal
    from public.club_public_season_standings(v_slug);
    assert v_aantal = 8, 'zonder seizoen koos hij niet het nieuwste met uitslagen';

    assert (select count(*) from public.club_public_seasons(v_slug)) = 1,
      'alleen het seizoen met afgesloten publieke avonden hoort publiek te zijn';
    raise notice 'OK  een leeg seizoen staat niet publiek, het nieuwste met uitslagen wel';
  end;

  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);

  -- ------------------------------------------------------------------ rechten
  perform set_config('request.jwt.claim.sub', v_vreemd::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  begin
    perform public.tournament_set_season(v_t30, v_oud_s);
    raise exception 'een vreemde kon een avond in een ander seizoen zetten';
  exception when insufficient_privilege then
    raise notice 'OK  een vreemde kan geen avonden verzetten';
  end;
  begin
    perform public.season_tournaments(v_club);
    raise exception 'een vreemde kon de tornooien van de club opvragen';
  exception when insufficient_privilege then
    raise notice 'OK  het overzicht blijft dicht voor wie geen staf is';
  end;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);

  -- Een floor bedient de avond maar beslist niet in welke competitie hij telt.
  insert into club_members (club_id, user_id, role) values (v_club, v_vreemd, 'floor');
  perform set_config('request.jwt.claim.sub', v_vreemd::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  begin
    perform public.tournament_set_season(v_t30, v_oud_s);
    raise exception 'een floor kon een avond in een ander seizoen zetten';
  exception when insufficient_privilege then
    raise notice 'OK  alleen owner of admin verzet een avond; een floor ziet het overzicht wel';
  end;
  assert (select count(*) from public.season_tournaments(v_club)) = 2,
    'een floor mocht het overzicht niet zien';
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);

  -- En een seizoen van een andere club hoort geweigerd te worden.
  declare
    v_ander uuid;
    v_ander_s uuid;
  begin
    insert into clubs (slug, name, compliance)
    values ('sz2-' || substr(gen_random_uuid()::text, 1, 10), 'Andere',
            jsonb_build_object('enforce', 'off'))
    returning id into v_ander;
    insert into seasons (club_id, name, starts_on)
    values (v_ander, 'Vreemd seizoen', current_date) returning id into v_ander_s;

    perform set_config('request.jwt.claim.sub', v_baas::text, true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    begin
      perform public.tournament_set_season(v_t30, v_ander_s);
      raise exception 'een avond kon in het seizoen van een andere club gezet worden';
    exception when check_violation then
      raise notice 'OK  een seizoen van een andere club wordt geweigerd';
    end;
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claim.role', '', true);
  end;
end $$;

rollback;
