-- Tests voor update_tournament: wat een mens mag bijstellen aan een avond die
-- al bestaat, en waar de functie de deur dichthoudt.

begin;

do $$
declare
  v_club uuid; v_s1 uuid; v_s2 uuid; v_pt uuid; v_tour uuid; v_tp uuid;
  v_user uuid := gen_random_uuid();
begin
  insert into clubs (slug, name, compliance)
  values ('b-' || substr(gen_random_uuid()::text, 1, 12), 'Bewerktest',
          jsonb_build_object('enforce','off'))
  returning id into v_club;

  insert into blind_structures (club_id, name) values (v_club, 'Oude structuur') returning id into v_s1;
  insert into blind_levels (structure_id, idx, small_blind, big_blind, duration_s)
    select v_s1, g, 25 * (g + 1), 50 * (g + 1), 1200 from generate_series(0, 5) g;
  insert into blind_structures (club_id, name) values (v_club, 'Nieuwe structuur') returning id into v_s2;
  insert into blind_levels (structure_id, idx, small_blind, big_blind, duration_s)
    select v_s2, g, 100 * (g + 1), 200 * (g + 1), 1200 from generate_series(0, 5) g;

  insert into payout_templates (club_id, name, tiers)
  values (v_club, 'P', '[{"min_entries":2,"max_entries":99,"percentages":[50,30,20]}]'::jsonb)
  returning id into v_pt;

  insert into tournaments (club_id, structure_id, payout_template_id, name, scheduled_at,
                           status, buyin_cents, fee_cents, starting_stack)
  values (v_club, v_s1, v_pt, 'Openingsavond', '2026-09-06 16:00+02',
          'scheduled', 3500, 500, 40000)
  returning id into v_tour;

  -- --------------------------------------------------------------- gewoon bijstellen
  perform public.update_tournament(v_tour, jsonb_build_object(
    'name', 'Grand Opening Event',
    'buyin_cents', 4000,
    'starting_stack', 40000,
    'prereg_bonus_stack', 5000,
    'late_reg_level', 10
  ));

  assert (select name from tournaments where id = v_tour) = 'Grand Opening Event',
    'de naam werd niet bijgesteld';
  assert (select buyin_cents from tournaments where id = v_tour) = 4000,
    'de inleg werd niet bijgesteld';
  assert (select prereg_bonus_stack from tournaments where id = v_tour) = 5000,
    'de bonuschips werden niet bijgesteld';
  assert (select fee_cents from tournaments where id = v_tour) = 500,
    'een veld dat niet in de patch stond, is toch gewijzigd';
  raise notice 'OK  velden bijstellen raakt alleen wat er in de patch staat';

  -- ------------------------------------------------------------ tikfout in een veldnaam
  begin
    perform public.update_tournament(v_tour, jsonb_build_object('buyin_cent', 9999));
    raise exception 'een onbekend veld werd geslikt';
  exception when check_violation then
    raise notice 'OK  een onbekende veldnaam geeft een foutmelding';
  end;

  -- ------------------------------------------------------- wat de floor toebehoort
  begin
    perform public.update_tournament(v_tour, jsonb_build_object('status', 'running'));
    raise exception 'de status kon via het bewerkscherm gezet worden';
  exception when check_violation then
    raise notice 'OK  de status en de klok blijven buiten het bewerkscherm';
  end;

  begin
    perform public.update_tournament(v_tour, jsonb_build_object('club_id', gen_random_uuid()));
    raise exception 'het tornooi kon naar een andere club verhuizen';
  exception when check_violation then
    raise notice 'OK  een tornooi kan niet naar een andere club verhuizen';
  end;

  -- ------------------------------------------------------------------ onzinwaarden
  begin
    perform public.update_tournament(v_tour, jsonb_build_object('starting_stack', 0));
    raise exception 'een startstapel van nul werd aanvaard';
  exception when check_violation then
    raise notice 'OK  een startstapel van nul wordt geweigerd';
  end;

  begin
    perform public.update_tournament(v_tour, jsonb_build_object('buyin_cents', -100));
    raise exception 'een negatieve inleg werd aanvaard';
  exception when check_violation then
    raise notice 'OK  een negatief bedrag wordt geweigerd';
  end;

  -- ----------------------------------------------------- structuur, voor de klok liep
  perform public.update_tournament(v_tour, jsonb_build_object('structure_id', v_s2));
  assert (select structure_id from tournaments where id = v_tour) = v_s2,
    'de blindstructuur kon niet gewisseld worden op een avond die nog moet beginnen';
  raise notice 'OK  de blindstructuur wisselen mag zolang de klok niet liep';

  -- ------------------------------------------------------ en daarna niet meer
  update tournaments set status = 'running', started_at = now(), level_idx = 3 where id = v_tour;
  begin
    perform public.update_tournament(v_tour, jsonb_build_object('structure_id', v_s1));
    raise exception 'de structuur kon gewisseld worden terwijl de klok liep';
  exception when check_violation then
    raise notice 'OK  de blindstructuur ligt vast zodra de klok gelopen heeft';
  end;

  -- Maar de inleg bijstellen mag wél tijdens de avond: elke inkoop bewaart
  -- zijn eigen bedrag, dus wie het nu rechtzet verandert niets aan wat er al
  -- betaald is.
  v_tp := public.floor_add_entry(v_tour, null, 'Speler',
    format('b-%s@test.be', substr(gen_random_uuid()::text, 1, 8)));
  perform public.update_tournament(v_tour, jsonb_build_object('buyin_cents', 4500));
  assert (select amount_cents from buyins where tournament_player_id = v_tp) = 4000,
    'de inkoop die al geboekt was, veranderde mee van bedrag';
  assert (select buyin_cents from tournaments where id = v_tour) = 4500,
    'de inleg voor de rest van de avond werd niet bijgesteld';
  raise notice 'OK  de inleg bijstellen tijdens de avond laat geboekte inkopen staan';

  -- ------------------------------------------------------------- na afloop
  update tournaments set status = 'finished' where id = v_tour;

  perform public.update_tournament(v_tour, jsonb_build_object('name', 'Grand Opening Event 2026'));
  assert (select name from tournaments where id = v_tour) = 'Grand Opening Event 2026',
    'de naam van een afgelopen avond kon niet rechtgezet worden';

  begin
    perform public.update_tournament(v_tour, jsonb_build_object('buyin_cents', 1000));
    raise exception 'de inleg van een afgelopen avond kon nog wijzigen';
  exception when check_violation then
    raise notice 'OK  na afloop kan enkel de naam, de notitie en de zichtbaarheid nog';
  end;

  -- ---------------------------------------------------------------- rechten
  insert into auth.users (id, email) values (v_user, 'vreemde-b@test.be');
  perform set_config('request.jwt.claim.sub', v_user::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  begin
    perform public.update_tournament(v_tour, jsonb_build_object('name', 'Gekaapt'));
    raise exception 'een vreemde kon het tornooi hernoemen';
  exception when insufficient_privilege then
    raise notice 'OK  zonder rol bij de club kan je niets bijstellen';
  end;

  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);
end $$;

rollback;
