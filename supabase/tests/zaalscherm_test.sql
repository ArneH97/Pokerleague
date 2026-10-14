-- Tests voor het zaalscherm.
--
-- Twee dingen staan hier vast en ze zijn allebei belangrijk. Ten eerste: de
-- sleutel is een slot en geen formaliteit — zonder of met de verkeerde komt
-- er niets terug, ook niet van een publiek tornooi. Ten tweede: de cijfers op
-- de tv zijn dezelfde cijfers als op het floorscherm. Een klok aan de muur
-- die iets anders zegt dan de telefoon van de floor is erger dan geen klok.

begin;

do $$
declare
  v_club uuid; v_club2 uuid; v_t uuid; v_struct uuid;
  v_baas uuid := gen_random_uuid();
  v_slug text := 'zs-' || substr(gen_random_uuid()::text, 1, 10);
  v_slug2 text := 'zt-' || substr(gen_random_uuid()::text, 1, 10);
  v_key text; v_key2 text;
  v_tp uuid;
  r record;
  v_n int;
begin
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);

  insert into auth.users (id, email) values (v_baas, format('zs-%s@test.be', substr(v_baas::text,1,8)));

  insert into clubs (slug, name, compliance, is_active, timezone)
  values (v_slug, 'Zaaltest', jsonb_build_object('enforce','off'), true, 'Europe/Brussels')
  returning id into v_club;
  insert into club_members (club_id, user_id, role) values (v_club, v_baas, 'owner');

  insert into clubs (slug, name, compliance, is_active, timezone)
  values (v_slug2, 'Andere club', jsonb_build_object('enforce','off'), true, 'Europe/Brussels')
  returning id into v_club2;

  -- Elke club kreeg bij de migratie een sleutel.
  select screen_key into v_key  from clubs where id = v_club;
  select screen_key into v_key2 from clubs where id = v_club2;
  assert v_key is not null and length(v_key) = 10,
    format('elke club hoort een sleutel van tien tekens te krijgen, kreeg %s', v_key);
  assert v_key <> v_key2, 'twee clubs kregen dezelfde sleutel';
  assert v_key ~ '^[a-z2-9]+$',
    format('de sleutel hoort alleen kleine letters en cijfers te bevatten: %s', v_key);
  raise notice 'OK  elke club heeft een eigen sleutel van tien leesbare tekens';

  insert into blind_structures (club_id, name)
  values (v_club, 'Zondag') returning id into v_struct;
  insert into blind_levels (structure_id, idx, is_break, label, small_blind, big_blind, ante, duration_s)
  values (v_struct, 0, false, null, 100, 200, 200, 1200),
         (v_struct, 1, false, null, 200, 400, 400, 1200),
         (v_struct, 2, true,  'Pauze', 0, 0, 0, 600),
         (v_struct, 3, false, null, 300, 600, 600, 1200);

  insert into tournaments (club_id, structure_id, name, scheduled_at, status,
                           buyin_cents, fee_cents, starting_stack, player_visibility,
                           clock, level_idx)
  values (v_club, v_struct, 'Sunday Opening', now(), 'running', 3000, 500, 40000,
          'public', 'running', 1)
  returning id into v_t;

  v_tp := public.floor_add_entry(v_t, null, 'Speler Een',
            format('zs1-%s@test.be', substr(gen_random_uuid()::text,1,8)));
  perform public.floor_add_entry(v_t, null, 'Speler Twee',
            format('zs2-%s@test.be', substr(gen_random_uuid()::text,1,8)));
  perform public.floor_add_entry(v_t, null, 'Speler Drie',
            format('zs3-%s@test.be', substr(gen_random_uuid()::text,1,8)));
  perform public.floor_rebuy(v_tp, 'rebuy');
  perform public.floor_eliminate(v_tp, null);

  perform set_config('pl.club', v_slug, true);
  perform set_config('pl.key', v_key, true);
  perform set_config('pl.key2', v_key2, true);
  perform set_config('pl.t', v_t::text, true);
end $$;

-- ---------------------------------------------------------------------------
-- Vanaf hier: een tv zonder account.
-- ---------------------------------------------------------------------------
set local role anon;

do $$
declare
  b record;
  v_n int;
begin
  -- Zonder sleutel: niets.
  select count(*) into v_n
  from public.club_screen_board(current_setting('pl.club'), '');
  assert v_n = 0, 'zonder sleutel kwam er toch een rij terug';

  -- Met de sleutel van een ándere club: ook niets. Dit is de vergissing die
  -- je wil uitsluiten — een sleutel die overal past is geen sleutel.
  select count(*) into v_n
  from public.club_screen_board(current_setting('pl.club'), current_setting('pl.key2'));
  assert v_n = 0, 'de sleutel van een andere club gaf toch toegang';

  select count(*) into v_n
  from public.club_screen_board(current_setting('pl.club'), 'zomaarwat');
  assert v_n = 0, 'een verzonnen sleutel gaf toch toegang';
  raise notice 'OK  zonder de juiste sleutel komt er niets terug';

  -- Met de juiste sleutel: de avond die nu bezig is.
  select * into b
  from public.club_screen_board(current_setting('pl.club'), current_setting('pl.key'));
  assert b.tournament_id = current_setting('pl.t')::uuid,
    'de verkeerde avond kwam terug';
  assert b.name = 'Sunday Opening', format('naam klopt niet: %s', b.name);
  assert b.club_name = 'Zaaltest', format('clubnaam klopt niet: %s', b.club_name);
  raise notice 'OK  met de sleutel komt de lopende avond terug';

  -- En de cijfers kloppen met wat er geboekt is: drie inkopen plus een rebuy,
  -- één speler eruit.
  assert b.entries = 3, format('3 deelnemers verwacht, stond %s', b.entries);
  assert b.players_left = 2, format('2 spelers over verwacht, stond %s', b.players_left);
  assert b.rebuys = 1, format('1 rebuy verwacht, stond %s', b.rebuys);
  assert b.prize_pool_cents = 4 * 3000,
    format('4 x 3000 in de pot verwacht, stond %s', b.prize_pool_cents);
  raise notice 'OK  de tellers op de tv komen uit het geldregister';

  -- Chips in spel: drie startstapels plus wat de rebuy bijlegde.
  assert b.chips_in_play = public.chips_in_play(current_setting('pl.t')::uuid),
    format('chips in spel weken af: %s tegenover %s',
           b.chips_in_play, public.chips_in_play(current_setting('pl.t')::uuid));
  raise notice 'OK  chips in spel is hetzelfde getal als op het floorscherm';

  -- De klokstand zelf, waar de pagina mee rekent.
  assert b.clock = 'running', format('klokstand klopt niet: %s', b.clock);
  assert b.level_idx = 1, format('level klopt niet: %s', b.level_idx);
  assert b.server_now is not null, 'de servertijd ontbreekt';
  raise notice 'OK  de klokstand en de servertijd komen mee';

  -- De structuur hoort bij dezelfde avond en staat op volgorde.
  select count(*) into v_n
  from public.club_screen_levels(current_setting('pl.club'), current_setting('pl.key'));
  assert v_n = 4, format('4 levels verwacht, kreeg %s', v_n);

  select count(*) into v_n
  from public.club_screen_levels(current_setting('pl.club'), 'zomaarwat');
  assert v_n = 0, 'de levels kwamen terug zonder geldige sleutel';
  raise notice 'OK  de levels horen bij dezelfde avond en vragen dezelfde sleutel';
end $$;

reset role;

-- ---------------------------------------------------------------------------
-- Geen avond bezig
-- ---------------------------------------------------------------------------
-- Het scherm mag de hele dag aanstaan. Staat er niets gepland voor vandaag,
-- dan komt er niets terug en blijft de tv rustig wachten.

do $$
declare
  v_club uuid; v_key text; v_n int;
  v_slug text := 'zl-' || substr(gen_random_uuid()::text, 1, 10);
begin
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);

  insert into clubs (slug, name, compliance, is_active, timezone)
  values (v_slug, 'Lege club', jsonb_build_object('enforce','off'), true, 'Europe/Brussels')
  returning id into v_club;
  select screen_key into v_key from clubs where id = v_club;

  select count(*) into v_n from public.club_screen_board(v_slug, v_key);
  assert v_n = 0, 'een club zonder avond gaf toch een rij';
  raise notice 'OK  geen avond bezig betekent geen rij, geen fout';

  -- Een avond van volgende week telt niet mee; een van vandaag wel.
  insert into tournaments (club_id, name, scheduled_at, status, buyin_cents, fee_cents,
                           starting_stack, player_visibility)
  values (v_club, 'Volgende week', now() + interval '7 days', 'scheduled', 3000, 500, 40000, 'public');
  select count(*) into v_n from public.club_screen_board(v_slug, v_key);
  assert v_n = 0, 'een avond van volgende week stond al op het scherm';

  insert into tournaments (club_id, name, scheduled_at, status, buyin_cents, fee_cents,
                           starting_stack, player_visibility)
  values (v_club, 'Vanavond', now() + interval '2 hours', 'scheduled', 3000, 500, 40000, 'public');
  select count(*) into v_n from public.club_screen_board(v_slug, v_key);
  assert v_n = 1, 'de avond van vandaag kwam niet op het scherm';
  raise notice 'OK  vanavond staat al klaar, volgende week nog niet';
end $$;

-- ---------------------------------------------------------------------------
-- De sleutel verzetten
-- ---------------------------------------------------------------------------

do $$
declare
  v_club uuid; v_baas uuid := gen_random_uuid(); v_floor uuid := gen_random_uuid();
  v_slug text := 'zr-' || substr(gen_random_uuid()::text, 1, 10);
  v_oud text; v_nieuw text; v_n int;
begin
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);

  insert into auth.users (id, email) values
    (v_baas,  format('zr1-%s@test.be', substr(v_baas::text,1,8))),
    (v_floor, format('zr2-%s@test.be', substr(v_floor::text,1,8)));
  insert into clubs (slug, name, compliance, is_active)
  values (v_slug, 'Resettest', jsonb_build_object('enforce','off'), true)
  returning id into v_club;
  insert into club_members (club_id, user_id, role) values
    (v_club, v_baas, 'owner'), (v_club, v_floor, 'floor');

  select screen_key into v_oud from clubs where id = v_club;

  -- Een floor mag dit niet: hij zou elke tv in de zaal stilleggen.
  perform set_config('request.jwt.claim.sub', v_floor::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  begin
    perform public.club_reset_screen_key(v_club);
    assert false, 'een floor kon de schermsleutel verzetten';
  exception when insufficient_privilege then
    raise notice 'OK  een floor kan de schermsleutel niet verzetten';
  end;

  perform set_config('request.jwt.claim.sub', v_baas::text, true);
  v_nieuw := public.club_reset_screen_key(v_club);
  assert v_nieuw <> v_oud, 'de nieuwe sleutel was dezelfde als de oude';
  assert length(v_nieuw) = 10, format('nieuwe sleutel heeft de verkeerde lengte: %s', v_nieuw);
  raise notice 'OK  een beheerder kan een verse sleutel zetten';

  -- En de oude doet het meteen niet meer.
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);
  select count(*) into v_n from public.club_screen_board(v_slug, v_oud);
  assert v_n = 0, 'de oude sleutel werkte nog na het verzetten';
  raise notice 'OK  de oude sleutel doet het daarna niet meer';
end $$;

rollback;
