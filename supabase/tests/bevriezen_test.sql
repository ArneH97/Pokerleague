-- Tests voor de grendel op de chipcounts, en voor wat er bijgehouden wordt
-- over wie een stapel intikte.

begin;

do $$
declare
  v_club uuid; v_tour uuid; v_tp uuid; v_speler uuid;
  v_user uuid := gen_random_uuid();
  v_staf uuid := gen_random_uuid();
  v_toen timestamptz;
begin
  insert into auth.users (id, email) values (v_user, 'speler-b@test.be'), (v_staf, 'floor-b@test.be');

  insert into clubs (slug, name, compliance)
  values ('fr-' || substr(gen_random_uuid()::text, 1, 12), 'Bevriestest',
          jsonb_build_object('enforce','off'))
  returning id into v_club;
  insert into club_members (club_id, user_id, role) values (v_club, v_staf, 'floor');

  insert into tournaments (club_id, name, scheduled_at, status,
                           buyin_cents, fee_cents, starting_stack)
  values (v_club, 'Telavond', now(), 'running', 4000, 0, 40000)
  returning id into v_tour;

  insert into players (display_name, email, auth_user_id, link_state)
  values ('Speler', 'speler-b@test.be', v_user, 'claimed')
  returning id into v_speler;

  v_tp := public.floor_add_entry(v_tour, v_speler);

  -- ------------------------------------------------- de speler tikt zelf in
  perform set_config('request.jwt.claim.sub', v_user::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  update tournament_players set chip_count = 52000 where id = v_tp;

  assert (select chip_count from tournament_players where id = v_tp) = 52000,
    'de speler kon zijn eigen stapel niet ingeven';
  assert (select chip_count_by from tournament_players where id = v_tp) = 'player',
    'de herkomst van de ingave werd niet op "player" gezet';
  assert (select chip_count_updated_at from tournament_players where id = v_tp) is not null,
    'het tijdstip van de ingave werd niet vastgelegd';
  raise notice 'OK  een speler kan zijn stapel ingeven, met herkomst en tijdstip erbij';

  -- ---------------------------------------------------------- de grendel om
  perform set_config('request.jwt.claim.sub', v_staf::text, true);
  v_toen := public.floor_freeze_counts(v_tour, true);
  assert v_toen is not null, 'bevriezen gaf geen tijdstip terug';
  assert (select counts_frozen_at from tournaments where id = v_tour) is not null,
    'de grendel staat niet op het tornooi';

  -- Nog eens klikken mag het tijdstip niet verzetten: anders springt
  -- "bevroren sinds 14 minuten" terug naar nul.
  perform pg_sleep(0.01);
  assert public.floor_freeze_counts(v_tour, true) = v_toen,
    'twee keer bevriezen verzette het tijdstip';
  raise notice 'OK  bevriezen legt een tijdstip vast en houdt dat vast';

  -- ------------------------------------------- de speler botst tegen de grendel
  perform set_config('request.jwt.claim.sub', v_user::text, true);
  begin
    update tournament_players set chip_count = 999999 where id = v_tp;
    raise exception 'de speler kon zijn stapel wijzigen terwijl er geteld werd';
  exception when check_violation then
    raise notice 'OK  een speler kan niets wijzigen terwijl de stapels geteld worden';
  end;
  assert (select chip_count from tournament_players where id = v_tp) = 52000,
    'de geweigerde ingave heeft toch iets veranderd';

  -- ----------------------------------------------- de floor kan wel gewoon door
  perform set_config('request.jwt.claim.sub', v_staf::text, true);
  update tournament_players set chip_count = 48500 where id = v_tp;
  assert (select chip_count from tournament_players where id = v_tp) = 48500,
    'de floor kon niet invullen terwijl de grendel om stond';
  assert (select chip_count_by from tournament_players where id = v_tp) = 'floor',
    'de herkomst staat niet op "floor" na een telling door de floor';
  raise notice 'OK  de floor telt en vult in terwijl de grendel om staat';

  -- --------------------------------------------------------- weer vrijgeven
  assert public.floor_freeze_counts(v_tour, false) is null,
    'vrijgeven gaf toch een tijdstip terug';
  perform set_config('request.jwt.claim.sub', v_user::text, true);
  update tournament_players set chip_count = 51000 where id = v_tp;
  assert (select chip_count from tournament_players where id = v_tp) = 51000,
    'na het vrijgeven kon de speler nog altijd niets ingeven';
  raise notice 'OK  na vrijgeven mag de speler weer';

  -- ---------------------------------------------------------------- rechten
  begin
    perform public.floor_freeze_counts(v_tour, true);
    raise exception 'een speler kon de grendel bedienen';
  exception when insufficient_privilege then
    raise notice 'OK  alleen staf kan de ingave bevriezen';
  end;

  -- ------------------------------------------- wat de spelerspagina toont
  perform set_config('request.jwt.claim.sub', v_staf::text, true);
  perform public.floor_freeze_counts(v_tour, true);
  perform set_config('request.jwt.claim.sub', v_user::text, true);

  assert (select counts_frozen from public.my_live_tournaments() limit 1),
    'de spelerspagina weet niet dat de ingave op slot staat';
  assert (select my_chips_at from public.my_live_tournaments() limit 1) is not null,
    'de spelerspagina kent het tijdstip van de laatste ingave niet';
  raise notice 'OK  de spelerspagina weet dat er geteld wordt';

  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);
end $$;

rollback;
