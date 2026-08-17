-- Test op de lus tussen players_read en club_players_read.
--
-- Deze draait bewust als de rol `authenticated`, want row level security
-- geldt niet voor de eigenaar van de tabellen. Zonder rolwissel test je
-- niets: dan slaagt alles altijd.
--
-- Draait in een transactie die terugrolt.

begin;

do $$
declare
  v_club   uuid;
  v_user   uuid;
  v_player uuid;
  v_n      int;
begin
  -- Leen een bestaande auth-gebruiker; in dit project is er altijd minstens
  -- één, en zelf een rij in auth.users maken vraagt kolommen die wij hier
  -- niet horen te kennen.
  select id into v_user from auth.users limit 1;
  if v_user is null then
    raise notice 'overgeslagen: geen enkele auth-gebruiker om mee te testen';
    return;
  end if;

  insert into clubs (slug, name)
  values ('t-' || substr(gen_random_uuid()::text, 1, 12), 'RLS-test')
  returning id into v_club;

  insert into club_members (club_id, user_id, role) values (v_club, v_user, 'floor');

  insert into players (display_name) values ('Testspeler') returning id into v_player;
  insert into club_players (club_id, player_id, joined_on) values (v_club, v_player, current_date);

  -- Vanaf hier zijn we een gewone ingelogde gebruiker.
  perform set_config('request.jwt.claim.sub', v_user::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  execute 'set local role authenticated';

  -- Dit is precies wat het spelersbeheer aan de floor doet: de clubleden
  -- ophalen mét hun naam. Vóór de fix knalde deze query eruit met
  -- "infinite recursion detected in policy for relation players".
  select count(*) into v_n
  from club_players cp
  join players p on p.id = cp.player_id
  where cp.club_id = v_club;

  assert v_n = 1, format('staf hoort 1 clublid te zien, kreeg %s', v_n);

  -- En andersom: de speler rechtstreeks lezen.
  select count(*) into v_n from players where id = v_player;
  assert v_n = 1, 'staf hoort de speler van zijn eigen club te kunnen lezen';

  -- De deelnemerslijst met namen erbij, zoals useFloorPlayers hem opvraagt.
  select count(*) into v_n
  from players p
  where exists (select 1 from club_players cp
                where cp.player_id = p.id and cp.club_id = v_club);
  assert v_n = 1, 'de omgekeerde richting geeft nog altijd een lus';

  execute 'reset role';
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);

  raise notice 'RLS OK: geen lus meer tussen players en club_players';
end $$;

-- ---------------------------------------------------------------------------
-- Een buitenstaander ziet niets van die club
-- ---------------------------------------------------------------------------

do $$
declare
  v_club uuid; v_player uuid; v_n int;
begin
  insert into clubs (slug, name)
  values ('t-' || substr(gen_random_uuid()::text, 1, 12), 'Afgeschermd')
  returning id into v_club;
  insert into players (display_name) values ('Onzichtbaar') returning id into v_player;
  insert into club_players (club_id, player_id, joined_on) values (v_club, v_player, current_date);

  perform set_config('request.jwt.claim.sub', gen_random_uuid()::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  execute 'set local role authenticated';

  select count(*) into v_n from players where id = v_player;
  assert v_n = 0, 'een buitenstaander mag deze speler niet zien';

  select count(*) into v_n from club_players where club_id = v_club;
  assert v_n = 0, 'een buitenstaander mag het ledenbestand niet zien';

  execute 'reset role';
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);

  raise notice 'afscherming OK: buitenstaander ziet geen spelers of leden';
end $$;

rollback;
