-- Tests voor het weghalen van een deelname en voor de hernummering van de
-- eindplaatsen. Draait in een transactie die terugrolt.
--
-- De aanleiding staat in 0048: een speler die per ongeluk werd toegevoegd was
-- niet meer weg te krijgen, en een uitschakeling van eerder op de avond
-- terugdraaien gaf twee spelers dezelfde plaats.

begin;

do $$
declare
  v_club uuid; v_season uuid; v_rc uuid; v_pt uuid; v_tour uuid;
  v_tps uuid[] := array[]::uuid[]; v_tp uuid; v_speler uuid;
  i int; v_pos int; v_n int;
begin
  insert into clubs (slug, name, compliance)
  values ('v-' || substr(gen_random_uuid()::text, 1, 12), 'Verwijdertest',
          jsonb_build_object('enforce','off'))
  returning id into v_club;

  insert into ranking_configs (club_id, name, method, params)
  values (v_club, 'R', 'sqrt_ratio', '{"multiplier":10}') returning id into v_rc;
  insert into seasons (club_id, name, starts_on, ranking_config_id)
  values (v_club, 'S', current_date, v_rc) returning id into v_season;
  insert into payout_templates (club_id, name, tiers)
  values (v_club, 'P', '[{"min_entries":2,"max_entries":99,"percentages":[50,30,20]}]'::jsonb)
  returning id into v_pt;

  insert into tournaments (club_id, season_id, payout_template_id, name, scheduled_at,
                           status, buyin_cents, fee_cents, starting_stack)
  values (v_club, v_season, v_pt, 'Verwijdertornooi', now(), 'running', 2000, 500, 20000)
  returning id into v_tour;

  for i in 1 .. 6 loop
    v_tp := public.floor_add_entry(
      v_tour, null, format('Speler %s', i),
      format('v%s-%s@test.be', i, substr(gen_random_uuid()::text, 1, 8)));
    v_tps := v_tps || v_tp;
  end loop;

  -- ------------------------------------------------- terugdraaien van eerder
  -- Drie afvallers: plaats 6, 5 en 4.
  perform public.floor_eliminate(v_tps[6], null);
  perform public.floor_eliminate(v_tps[5], null);
  perform public.floor_eliminate(v_tps[4], null);

  -- En nu de middelste terugdraaien. Vóór 0048 kwam speler 4 hier op plaats 3
  -- terecht, met een gat op 4 en 5 en straks een dubbele plaats in de uitslag.
  perform public.floor_undo_elimination(v_tps[5]);

  assert (select status from tournament_players where id = v_tps[5]) = 'active',
    'terugdraaien zette de speler niet terug op actief';
  assert (select finish_position from tournament_players where id = v_tps[6]) = 6,
    'de eerste afvaller hoort zesde te blijven';
  assert (select finish_position from tournament_players where id = v_tps[4]) = 5,
    format('de tweede overblijvende afvaller hoort vijfde te zijn, staat op %s',
           (select finish_position from tournament_players where id = v_tps[4]));

  select count(distinct finish_position) into v_n
  from tournament_players where tournament_id = v_tour and finish_position is not null;
  assert v_n = 2, 'twee afvallers horen twee verschillende plaatsen te hebben';
  raise notice 'OK  een uitschakeling van eerder terugdraaien houdt de plaatsen sluitend';

  -- ------------------------------------------------------------- weghalen
  select player_id into v_speler from tournament_players where id = v_tps[3];

  perform public.floor_remove_entry(v_tps[3]);

  assert not exists (select 1 from tournament_players where id = v_tps[3]),
    'de deelname staat er nog';
  assert not exists (select 1 from buyins where tournament_player_id = v_tps[3]),
    'de inkoop van de weggehaalde speler staat er nog';
  assert exists (select 1 from players where id = v_speler),
    'de speler zelf hoort te blijven bestaan';
  assert exists (select 1 from club_players where club_id = v_club and player_id = v_speler),
    'het clublidmaatschap hoort te blijven staan';
  raise notice 'OK  een deelname weghalen neemt de inkoop mee en laat de speler staan';

  -- Vijf deelnemers over, dus de eerste afvaller is nu vijfde.
  assert (select finish_position from tournament_players where id = v_tps[6]) = 5,
    format('na het weghalen hoort de eerste afvaller vijfde te zijn, staat op %s',
           (select finish_position from tournament_players where id = v_tps[6]));
  assert (select finish_position from tournament_players where id = v_tps[4]) = 4,
    'de tweede afvaller schoof niet mee op';
  raise notice 'OK  de eindplaatsen schuiven mee als er iemand uit het veld verdwijnt';

  -- ------------------------------------------------- uitgeschakelde weghalen
  -- Precies wat er misging: iemand schakelt zichzelf uit omdat er geen andere
  -- knop is, en wil er daarna helemaal af.
  perform public.floor_remove_entry(v_tps[6]);
  assert not exists (select 1 from tournament_players where id = v_tps[6]),
    'een uitgeschakelde speler kon niet weggehaald worden';
  assert not exists (select 1 from eliminations where tournament_player_id = v_tps[6]),
    'de uitschakeling bleef in het register staan';
  assert (select finish_position from tournament_players where id = v_tps[4]) = 4,
    'de overblijvende afvaller hoort vierde te zijn van vier deelnemers';
  raise notice 'OK  ook een uitgeschakelde speler kan weg';

  -- ---------------------------------------------------------------- sloten
  -- Wie extra ingekocht heeft, gaat er niet zomaar af: daar is geld mee
  -- gemoeid en dat hoort eerst teruggedraaid te worden.
  perform public.floor_rebuy(v_tps[1], 'rebuy');
  begin
    perform public.floor_remove_entry(v_tps[1]);
    raise exception 'weghalen mocht met een openstaande rebuy';
  exception when check_violation then
    raise notice 'OK  weghalen weigert zolang er extra inkopen openstaan';
  end;

  perform public.floor_undo_last_buyin(v_tps[1]);
  perform public.floor_remove_entry(v_tps[1]);
  assert not exists (select 1 from tournament_players where id = v_tps[1]),
    'na het terugdraaien van de rebuy hoort weghalen wel te lukken';
  raise notice 'OK  na het terugdraaien van de inkoop kan hij er alsnog af';

  -- Een afgelopen tornooi blijft eraf.
  perform public.floor_finish_tournament(v_tour);
  begin
    perform public.floor_remove_entry(v_tps[2]);
    raise exception 'weghalen mocht op een afgesloten tornooi';
  exception when check_violation then
    raise notice 'OK  weghalen weigert op een afgesloten tornooi';
  end;

  -- En de uitslag van dat tornooi is sluitend: geen gat, geen dubbele plaats.
  select count(*) into v_n from tournament_results where tournament_id = v_tour;
  assert (select count(distinct position) from tournament_results where tournament_id = v_tour) = v_n,
    'twee spelers deelden dezelfde plaats in de uitslag';
  assert (select max(position) from tournament_results where tournament_id = v_tour) = v_n,
    format('de plaatsen lopen niet van 1 tot %s', v_n);
  raise notice 'OK  de uitslag loopt sluitend van 1 tot het aantal deelnemers';
end $$;

-- ---------------------------------------------------------------------------
-- Rechten: een speler zonder rol bij de club komt er niet aan
-- ---------------------------------------------------------------------------

do $$
declare
  v_club uuid; v_tour uuid; v_tp uuid; v_user uuid := gen_random_uuid();
begin
  insert into clubs (slug, name, compliance)
  values ('v-' || substr(gen_random_uuid()::text, 1, 12), 'Rechtentest',
          jsonb_build_object('enforce','off'))
  returning id into v_club;

  insert into tournaments (club_id, name, scheduled_at, status, buyin_cents, fee_cents, starting_stack)
  values (v_club, 'Rechten', now(), 'running', 2000, 500, 20000)
  returning id into v_tour;

  v_tp := public.floor_add_entry(v_tour, null, 'Iemand',
    format('r-%s@test.be', substr(gen_random_uuid()::text, 1, 8)));

  insert into auth.users (id, email) values (v_user, 'vreemde@test.be');
  perform set_config('request.jwt.claim.sub', v_user::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  begin
    perform public.floor_remove_entry(v_tp);
    raise exception 'een vreemde kon een deelname weghalen';
  exception when insufficient_privilege then
    raise notice 'OK  zonder rol bij de club kan je niemand weghalen';
  end;

  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);
end $$;

rollback;
