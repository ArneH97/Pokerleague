-- Pokerleague — wat een speler bij één club heeft staan
--
-- Deze functie bestaat om het onderscheid tussen "de club" en "het platform"
-- eindelijk zichtbaar te maken, en dan moet ze wel het juiste getal geven.
-- Een verkeerde klassering op je eigen pagina is erger dan geen klassering:
-- dan staat er iets naast de lijst van de club dat er niet mee klopt.
--
-- Bewaakt wordt:
--
--   * de winnaar staat eerste, en het totaal klopt met het aantal spelers
--   * besloten avonden tellen niet mee — net zoals bij het publieke klassement
--   * je krijgt je eigen cijfers en niet die van je buurman
--   * zonder aanmelding krijg je niets
\set ON_ERROR_STOP on

begin;

do $$
declare
  v_club uuid; v_struct uuid; v_pay uuid;
  v_open uuid; v_dicht uuid;
  v_a uuid; v_b uuid; v_c uuid;
  v_ua uuid; v_ub uuid;
  v_tp_a uuid; v_tp_b uuid; v_tp_c uuid;
  v_n int; v_rank int; v_van int; v_tor int;
begin
  insert into clubs (slug, name, city, country, locale, timezone)
  values ('t32', 'Testclub 32', 'Aalst', 'BE', 'nl', 'Europe/Brussels') returning id into v_club;

  insert into blind_structures (club_id, name) values (v_club, 'S') returning id into v_struct;
  insert into blind_levels (structure_id, idx, is_break, small_blind, big_blind, ante, duration_s)
  values (v_struct, 0, false, 25, 50, 0, 1200);
  insert into payout_templates (club_id, name, tiers, rounding)
  values (v_club, 'P', '[{"min_entries":2,"max_entries":99,"percentages":[100]}]'::jsonb, 100)
  returning id into v_pay;

  -- Eén publieke avond met drie man.
  insert into tournaments (club_id, payout_template_id, structure_id, name, scheduled_at,
                           status, player_visibility, buyin_cents, fee_cents,
                           starting_stack, max_reentries)
  values (v_club, v_pay, v_struct, 'Publieke avond', now(), 'running'::tournament_status,
          'public'::visibility, 2000, 0, 20000, 0)
  returning id into v_open;

  v_tp_a := public.floor_add_entry(v_open, null, 'Speler A', 'a@t32.be');
  v_tp_b := public.floor_add_entry(v_open, null, 'Speler B', 'b@t32.be');
  v_tp_c := public.floor_add_entry(v_open, null, 'Speler C', 'c@t32.be');
  select player_id into v_a from tournament_players where id = v_tp_a;
  select player_id into v_b from tournament_players where id = v_tp_b;
  select player_id into v_c from tournament_players where id = v_tp_c;

  -- C valt eerst, dan B. A wint.
  perform public.floor_eliminate(v_tp_c, null);
  perform public.floor_eliminate(v_tp_b, null);
  perform public.floor_finish_tournament(v_open);

  -- En een besloten avond waar A ook meespeelde.
  insert into tournaments (club_id, payout_template_id, structure_id, name, scheduled_at,
                           status, player_visibility, buyin_cents, fee_cents,
                           starting_stack, max_reentries)
  values (v_club, v_pay, v_struct, 'Besloten avond', now(), 'running'::tournament_status,
          'private'::visibility, 2000, 0, 20000, 0)
  returning id into v_dicht;

  v_tp_a := public.floor_add_entry(v_dicht, v_a);
  v_tp_b := public.floor_add_entry(v_dicht, v_b);
  perform public.floor_eliminate(v_tp_b, null);
  perform public.floor_finish_tournament(v_dicht);

  -- --------------------------------------------------------------------- 1 ---
  insert into auth.users (email) values ('a@t32.be') returning id into v_ua;
  update players set auth_user_id = v_ua, link_state = 'claimed' where id = v_a;

  perform set_config('request.jwt.claims',
    json_build_object('sub', v_ua, 'role', 'authenticated', 'email', 'a@t32.be')::text, true);
  perform set_config('request.jwt.claim.sub', v_ua::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  set local role authenticated;

  select count(*) into v_n from public.my_club_stats();
  if v_n <> 1 then raise exception 'FOUT: verwacht 1 club, kreeg %', v_n; end if;

  select rank, of_players, tournaments into v_rank, v_van, v_tor
  from public.my_club_stats('t32');

  if v_rank <> 1 then raise exception 'FOUT: de winnaar staat % en niet eerste', v_rank; end if;
  if v_van <> 3 then raise exception 'FOUT: verwacht 3 spelers in het klassement, kreeg %', v_van; end if;
  raise notice 'OK  de winnaar staat eerste van drie';

  -- --------------------------------------------------------------------- 2 ---
  -- De besloten avond telt niet mee. Zou hij dat wel doen, dan zou hier 2
  -- staan terwijl de klassementpagina van de club er één toont — en dan is
  -- het cijfer erger dan geen cijfer.
  if v_tor <> 1 then
    raise exception 'FOUT: % avonden geteld; een besloten avond telde mee', v_tor;
  end if;
  raise notice 'OK  een besloten avond telt niet mee, net als bij het clubklassement';

  -- --------------------------------------------------------------------- 3 ---
  -- Filteren op een club waar hij niet speelde geeft niets, geen fout.
  select count(*) into v_n from public.my_club_stats('bestaat-niet');
  if v_n <> 0 then raise exception 'FOUT: onbekende club gaf % rijen', v_n; end if;
  raise notice 'OK  een onbekende club geeft gewoon niets';

  reset role;

  -- --------------------------------------------------------------------- 4 ---
  -- Zijn buurman krijgt zijn eigen regel. Dit is de controle die telt: de
  -- functie is security definer en zou zonder de filter op auth.uid() de
  -- cijfers van iedereen teruggeven aan wie ernaar vraagt.
  insert into auth.users (email) values ('b@t32.be') returning id into v_ub;
  update players set auth_user_id = v_ub, link_state = 'claimed' where id = v_b;

  perform set_config('request.jwt.claims',
    json_build_object('sub', v_ub, 'role', 'authenticated', 'email', 'b@t32.be')::text, true);
  perform set_config('request.jwt.claim.sub', v_ub::text, true);
  set local role authenticated;

  select rank into v_rank from public.my_club_stats('t32');
  if v_rank = 1 then raise exception 'FOUT: B kreeg de cijfers van A'; end if;
  if v_rank is null then raise exception 'FOUT: B kreeg helemaal niets'; end if;
  raise notice 'OK  iedereen krijgt zijn eigen regel (B staat %)', v_rank;

  reset role;

  -- --------------------------------------------------------------------- 5 ---
  -- En zonder aanmelding: niets.
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  set local role anon;

  select count(*) into v_n from public.my_club_stats();
  if v_n <> 0 then raise exception 'FOUT: een bezoeker kreeg % rijen', v_n; end if;
  raise notice 'OK  zonder aanmelding krijg je niets';

  reset role;
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.role', '', true);
end $$;

rollback;
