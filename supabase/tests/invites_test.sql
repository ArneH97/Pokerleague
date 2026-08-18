-- Pokerleague — de uitnodiging van wachtrij tot afgevinkt
--
-- Wat hier bewaakt wordt is de hele keten, want elke schakel is ooit stil
-- kapot gegaan:
--
--   * de floor tikt iemand in → er hoort een uitnodiging klaar te staan
--   * de landingspagina moet die op token kunnen tonen, zonder rechten
--   * maar alleen dát — het token mag geen sleutel tot het profiel zijn
--   * wie registreert, vinkt de uitnodiging af, ook al ging hij niet via de link
--   * een verlopen uitnodiging zegt dat ook, in plaats van te doen alsof
--   * en het overzicht voor de club blijft dicht voor wie er niet bij hoort
\set ON_ERROR_STOP on

begin;

do $$
declare
  v_club uuid; v_struct uuid; v_pay uuid; v_tour uuid;
  v_owner uuid; v_uid uuid;
  v_tp uuid; v_player uuid;
  v_token text; v_token2 text;
  v_n int; v_state text; v_naam text; v_mail text;
begin
  insert into clubs (slug, name, city, country, locale, timezone, contact_email)
  values ('t30', 'Testclub 30', 'Aalst', 'BE', 'nl', 'Europe/Brussels', 'info@t30.be')
  returning id into v_club;

  insert into blind_structures (club_id, name) values (v_club, 'S') returning id into v_struct;
  insert into blind_levels (structure_id, idx, is_break, small_blind, big_blind, ante, duration_s)
  values (v_struct, 0, false, 25, 50, 0, 1200);
  insert into payout_templates (club_id, name, tiers, rounding)
  values (v_club, 'P', '[{"min_entries":2,"max_entries":99,"percentages":[100]}]'::jsonb, 100)
  returning id into v_pay;

  insert into tournaments (club_id, payout_template_id, structure_id, name, scheduled_at,
                           status, player_visibility, buyin_cents, fee_cents,
                           starting_stack, max_reentries)
  values (v_club, v_pay, v_struct, 'Avond', now(), 'running'::tournament_status,
          'public'::visibility, 2000, 0, 20000, 1)
  returning id into v_tour;

  -- --------------------------------------------------------------------- 1 ---
  -- De floor tikt iemand in die nog nergens bestaat.
  v_tp := public.floor_add_entry(v_tour, null, 'Nieuwe Speler', 'nieuw@t30.be');
  select player_id into v_player from tournament_players where id = v_tp;

  select count(*) into v_n from player_invites
  where player_id = v_player and sent_at is null and accepted_at is null and attempts = 0;
  if v_n <> 1 then
    raise exception 'FOUT: verwacht 1 openstaande uitnodiging, kreeg %', v_n;
  end if;
  raise notice 'OK  de floor tikt iemand in en er staat een uitnodiging klaar';

  select token into v_token from player_invites where player_id = v_player;

  -- --------------------------------------------------------------------- 2 ---
  -- Wat de landingspagina ziet. Dit draait als anon: wie hier komt heeft per
  -- definitie nog geen account.
  perform set_config('request.jwt.claims', '', true);
  set local role anon;

  select state, player_name, email into v_state, v_naam, v_mail
  from public.invite_lookup(v_token);

  if v_state is distinct from 'open' then
    raise exception 'FOUT: verwacht state open, kreeg %', coalesce(v_state, '<niets>');
  end if;
  if v_naam <> 'Nieuwe Speler' then raise exception 'FOUT: verkeerde naam: %', v_naam; end if;
  if v_mail <> 'nieuw@t30.be' then raise exception 'FOUT: verkeerd adres: %', v_mail; end if;
  raise notice 'OK  een bezoeker zonder account ziet de uitnodiging op token';

  -- --------------------------------------------------------------------- 3 ---
  -- Een token dat niet bestaat geeft niets. Geen fout, geen hint.
  select count(*) into v_n from public.invite_lookup('nietbestaand');
  if v_n <> 0 then raise exception 'FOUT: onbekend token gaf % rijen', v_n; end if;
  raise notice 'OK  een onbekend token levert niets op';

  -- --------------------------------------------------------------------- 4 ---
  -- En het belangrijkste: de tabel zelf blijft dicht. Kon anon hierin lezen,
  -- dan was invite_lookup een schaamlapje — dan haal je gewoon alle tokens op
  -- en heb je elk mailadres van elke club.
  begin
    select count(*) into v_n from player_invites;
    if v_n > 0 then
      raise exception 'FOUT: anon kon % rijen uit player_invites lezen', v_n;
    end if;
  exception
    when insufficient_privilege then
      null;  -- Ook goed: geweigerd voordat RLS eraan te pas komt.
  end;
  raise notice 'OK  player_invites zelf blijft dicht voor een bezoeker';

  reset role;

  -- --------------------------------------------------------------------- 5 ---
  -- Hij registreert. Niet via de link — gewoon op /registreren met hetzelfde
  -- adres, wat de meest waarschijnlijke weg is. De uitnodiging hoort evengoed
  -- afgevinkt te worden, want ze is achterhaald.
  insert into auth.users (email) values ('nieuw@t30.be') returning id into v_uid;
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_uid, 'role', 'authenticated', 'email', 'nieuw@t30.be')::text, true);
  perform set_config('request.jwt.claim.sub', v_uid::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  if public.claim_my_player('Nieuwe', 'Speler', null, false) <> v_player then
    raise exception 'FOUT: hij kreeg niet zijn bestaande profiel';
  end if;

  if (select accepted_at from player_invites where token = v_token) is null then
    raise exception 'FOUT: de uitnodiging staat nog altijd open na registratie';
  end if;
  raise notice 'OK  registreren buiten de link om vinkt de uitnodiging toch af';

  -- --------------------------------------------------------------------- 6 ---
  -- En de link zegt dat dan ook, in plaats van een formulier te tonen dat
  -- alleen maar "dit adres bestaat al" kan antwoorden.
  select state into v_state from public.invite_lookup(v_token);
  if v_state not in ('accepted', 'has_account') then
    raise exception 'FOUT: verwacht accepted/has_account, kreeg %', v_state;
  end if;
  raise notice 'OK  de link meldt daarna dat het al in orde is';

  -- --------------------------------------------------------------------- 7 ---
  -- Een verlopen uitnodiging.
  perform set_config('request.jwt.claims', '', true);
  insert into players (display_name, email) values ('Trage Beslisser', 'traag@t30.be')
  returning id into v_player;
  -- Ook lid maken van de club, want dat is wat floor_add_entry doet. Zonder
  -- die rij mag de staf hem niet lezen (staff_sees_player kijkt naar
  -- club_players) en test controle 9 hieronder iets anders dan de werkelijkheid.
  insert into club_players (club_id, player_id) values (v_club, v_player);
  insert into player_invites (club_id, player_id, email, token, expires_at)
  values (v_club, v_player, 'traag@t30.be', public.new_invite_token(), now() - interval '1 day')
  returning token into v_token2;

  select state into v_state from public.invite_lookup(v_token2);
  if v_state <> 'expired' then raise exception 'FOUT: verwacht expired, kreeg %', v_state; end if;
  raise notice 'OK  een verlopen uitnodiging zegt dat ze verlopen is';

  -- En de verzender pikt hem niet meer op, want die filtert op expires_at.
  select count(*) into v_n from player_invites
  where sent_at is null and accepted_at is null and attempts < 3 and expires_at > now();
  if v_n <> 0 then
    raise exception 'FOUT: er staat nog % iets in de wachtrij dat er niet hoort', v_n;
  end if;
  raise notice 'OK  de wachtrij bevat niets verlopens meer';

  -- --------------------------------------------------------------------- 8 ---
  -- Het cluboverzicht is voor het bestuur.
  insert into auth.users (email) values ('baas@t30.be') returning id into v_owner;
  insert into club_members (club_id, user_id, role) values (v_club, v_owner, 'owner');

  perform set_config('request.jwt.claims',
    json_build_object('sub', v_owner, 'role', 'authenticated', 'email', 'baas@t30.be')::text, true);
  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  set local role authenticated;

  select count(*) into v_n from public.club_invites(v_club);
  if v_n <> 2 then raise exception 'FOUT: het bestuur ziet % uitnodigingen in plaats van 2', v_n; end if;
  raise notice 'OK  het bestuur ziet de uitnodigingen van zijn club';

  -- --------------------------------------------------------------------- 9 ---
  -- De verzender kan ook met een gewone sessie draaien: dan filtert RLS mee
  -- en gaan er alleen uitnodigingen van eigen clubs buiten. Dat werkt alleen
  -- als het bestuur naast de uitnodiging óók de speler erachter mag zien —
  -- anders komt de naam leeg binnen en kan hij niet zien wie zich intussen
  -- zelf al registreerde. Vandaar dat de join hier meegetest wordt en niet
  -- alleen de tabel.
  select count(*) into v_n
  from player_invites i
  join players p on p.id = i.player_id
  where i.club_id = v_club and p.display_name is not null;
  if v_n <> 2 then
    raise exception 'FOUT: de join met players gaf % rijen in plaats van 2 — de verzender ziet dan geen namen', v_n;
  end if;

  -- En afvinken mag hij ook, anders blijft dezelfde mail eeuwig terugkomen.
  update player_invites set last_try_at = now() where club_id = v_club and token = v_token2;
  if (select last_try_at from player_invites where token = v_token2) is null then
    raise exception 'FOUT: het bestuur kon de verzendstatus niet bijwerken';
  end if;
  raise notice 'OK  met een gewone sessie ziet en schrijft het bestuur zijn eigen wachtrij';

  reset role;

  -- Iemand met een account maar zonder rol bij deze club: niets.
  insert into auth.users (email) values ('buiten@t30.be') returning id into v_uid;
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_uid, 'role', 'authenticated', 'email', 'buiten@t30.be')::text, true);
  perform set_config('request.jwt.claim.sub', v_uid::text, true);
  set local role authenticated;

  begin
    select count(*) into v_n from public.club_invites(v_club);
    raise exception 'FOUT: een buitenstaander kreeg het overzicht (% rijen)', v_n;
  exception
    when insufficient_privilege then
      raise notice 'OK  een buitenstaander wordt geweigerd';
  end;

  reset role;
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.role', '', true);
end $$;

rollback;

-- ---------------------------------------------------------------------------
-- Een uitnodiging hoort bij het lidmaatschap, niet bij het profiel
-- ---------------------------------------------------------------------------
-- Dit is het gat uit 0032. Alle drie de gevallen hieronder gingen fout omdat
-- de uitnodiging alleen bij een nieuw spelersprofiel werd aangemaakt.

begin;
do $$
declare
  v_a uuid; v_b uuid; v_struct uuid; v_pay uuid; v_tour uuid;
  v_p uuid; v_tp uuid; v_uid uuid; v_n int; v_tok text;
begin
  insert into clubs (slug, name, city, country, locale, timezone)
  values ('t33a', 'Club A', 'Gent', 'BE', 'nl', 'Europe/Brussels') returning id into v_a;
  insert into clubs (slug, name, city, country, locale, timezone)
  values ('t33b', 'Club B', 'Aalst', 'BE', 'nl', 'Europe/Brussels') returning id into v_b;

  insert into blind_structures (club_id, name) values (v_b, 'S') returning id into v_struct;
  insert into blind_levels (structure_id, idx, is_break, small_blind, big_blind, ante, duration_s)
  values (v_struct, 0, false, 25, 50, 0, 1200);
  insert into payout_templates (club_id, name, tiers, rounding)
  values (v_b, 'P', '[{"min_entries":2,"max_entries":99,"percentages":[100]}]'::jsonb, 100)
  returning id into v_pay;
  insert into tournaments (club_id, payout_template_id, structure_id, name, scheduled_at,
                           status, player_visibility, buyin_cents, fee_cents,
                           starting_stack, max_reentries)
  values (v_b, v_pay, v_struct, 'Avond bij B', now(), 'running'::tournament_status,
          'public'::visibility, 2000, 0, 20000, 0)
  returning id into v_tour;

  -- 1 --- Hij bestaat al bij club A en komt voor het eerst bij club B.
  insert into players (display_name, email, link_state)
  values ('Reiziger', 'reiziger@t33.be', 'invited') returning id into v_p;
  insert into club_players (club_id, player_id) values (v_a, v_p);

  perform public.floor_add_entry(v_tour, null, 'Reiziger', 'reiziger@t33.be');

  select count(*) into v_n from player_invites where club_id = v_b and player_id = v_p;
  if v_n <> 1 then
    raise exception 'FOUT: club B zette % uitnodigingen klaar voor een bestaand profiel', v_n;
  end if;
  raise notice 'OK  een bestaand profiel dat hier voor het eerst komt krijgt wel een uitnodiging';

  -- 2 --- Nog eens toevoegen mag er geen tweede opleveren. Twee keer dezelfde
  --       mail is erger dan geen mail.
  select token into v_tok from player_invites where club_id = v_b and player_id = v_p;
  update player_invites set sent_at = now() where token = v_tok;
  perform public.floor_add_entry(v_tour, v_p);

  select count(*) into v_n from player_invites where club_id = v_b and player_id = v_p;
  if v_n <> 1 then raise exception 'FOUT: er staan nu % uitnodigingen; hij krijgt dubbel post', v_n; end if;
  raise notice 'OK  opnieuw toevoegen levert geen tweede uitnodiging op';

  -- 3 --- Maar een verlopen uitnodiging bij iemand die nog altijd geen account
  --       heeft, mag wél vernieuwd worden. Anders komt er nooit meer iets.
  update player_invites set expires_at = now() - interval '1 day' where token = v_tok;
  perform public.floor_add_entry(v_tour, v_p);

  select count(*) into v_n from player_invites
  where club_id = v_b and player_id = v_p and expires_at > now() and accepted_at is null;
  if v_n <> 1 then raise exception 'FOUT: na het verlopen kwam er geen nieuwe (% open)', v_n; end if;
  raise notice 'OK  een verlopen uitnodiging wordt vernieuwd bij wie nog geen account heeft';

  -- 4 --- En wie zijn account intussen heeft, krijgt niets meer.
  delete from player_invites where club_id = v_b and player_id = v_p;
  insert into auth.users (email) values ('reiziger@t33.be') returning id into v_uid;
  update players set auth_user_id = v_uid, link_state = 'claimed' where id = v_p;

  perform public.floor_add_entry(v_tour, v_p);
  select count(*) into v_n from player_invites where club_id = v_b and player_id = v_p;
  if v_n <> 0 then raise exception 'FOUT: iemand met een account kreeg toch een uitnodiging'; end if;
  raise notice 'OK  wie zijn account al heeft krijgt geen uitnodiging meer';

  -- 5 --- Zonder mailadres is er niets om naartoe te sturen.
  v_tp := public.floor_add_entry(v_tour, null, 'Geen Adres', null, 'wilde niet');
  select tp.player_id into v_p from tournament_players tp where tp.id = v_tp;
  select count(*) into v_n from player_invites where player_id = v_p;
  if v_n <> 0 then raise exception 'FOUT: uitnodiging aangemaakt zonder mailadres'; end if;
  raise notice 'OK  zonder mailadres komt er geen uitnodiging';
end $$;
rollback;

-- ---------------------------------------------------------------------------
-- Je online aansluiten bij een club
-- ---------------------------------------------------------------------------
-- Sinds 0033 kan dat, en dan moet het ook precies doen wat er staat: je erbij
-- zetten, niet twee keer, en niet bij een club die op uitnodiging werkt.

begin;
do $$
declare
  v_open uuid; v_dicht uuid; v_uid uuid; v_p uuid;
  v_res text; v_n int; v_self boolean;
begin
  insert into clubs (slug, name, city, country, locale, timezone, open_signup)
  values ('t34', 'Open club', 'Gent', 'BE', 'nl', 'Europe/Brussels', true)
  returning id into v_open;
  insert into clubs (slug, name, city, country, locale, timezone, open_signup)
  values ('t34b', 'Besloten club', 'Aalst', 'BE', 'nl', 'Europe/Brussels', false)
  returning id into v_dicht;

  insert into auth.users (email) values ('nieuw@t34.be') returning id into v_uid;
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_uid, 'role', 'authenticated', 'email', 'nieuw@t34.be')::text, true);
  perform set_config('request.jwt.claim.sub', v_uid::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  set local role authenticated;

  -- 1 --- Aansluiten zonder ooit een spelersprofiel te hebben gehad. Dat is
  --       het gewone geval: registreren en meteen doorklikken.
  v_res := public.join_club('t34');
  if v_res <> 'joined' then raise exception 'FOUT: verwacht joined, kreeg %', v_res; end if;

  select p.id into v_p from players p where p.auth_user_id = v_uid;
  if v_p is null then raise exception 'FOUT: er is geen spelersprofiel aangemaakt'; end if;

  select cp.self_joined into v_self
  from club_players cp where cp.club_id = v_open and cp.player_id = v_p;
  if v_self is not true then
    raise exception 'FOUT: self_joined staat niet aan; de floor ziet niet dat hij hier nooit was';
  end if;
  raise notice 'OK  aansluiten maakt het profiel aan en markeert hem als online aangesloten';

  -- 2 --- Nog eens: niets dubbels.
  v_res := public.join_club('t34');
  if v_res <> 'already' then raise exception 'FOUT: verwacht already, kreeg %', v_res; end if;
  select count(*) into v_n from club_players where club_id = v_open and player_id = v_p;
  if v_n <> 1 then raise exception 'FOUT: hij staat % keer in het ledenbestand', v_n; end if;
  raise notice 'OK  twee keer aansluiten levert één lidmaatschap op';

  -- 3 --- Een club die op uitnodiging werkt laat dit niet toe.
  v_res := public.join_club('t34b');
  if v_res <> 'closed' then raise exception 'FOUT: verwacht closed, kreeg %', v_res; end if;
  select count(*) into v_n from club_players where club_id = v_dicht;
  if v_n <> 0 then raise exception 'FOUT: hij kwam toch in een besloten ledenbestand'; end if;
  raise notice 'OK  een besloten club houdt de deur dicht';

  -- 4 --- En een club die niet bestaat geeft geen fout maar een antwoord.
  v_res := public.join_club('bestaat-niet');
  if v_res <> 'unknown' then raise exception 'FOUT: verwacht unknown, kreeg %', v_res; end if;
  raise notice 'OK  een onbekende club geeft netjes unknown terug';

  -- 5 --- De lijst met suggesties laat niet zien waar hij al bij hoort, en ook
  --       de besloten club niet.
  select count(*) into v_n from public.clubs_open_to_join() where slug = 't34';
  if v_n <> 0 then raise exception 'FOUT: zijn eigen club stond in de suggesties'; end if;
  select count(*) into v_n from public.clubs_open_to_join() where slug = 't34b';
  if v_n <> 0 then raise exception 'FOUT: een besloten club stond in de suggesties'; end if;
  raise notice 'OK  de suggesties tonen alleen clubs waar hij zich echt kan aansluiten';

  reset role;
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.role', '', true);
end $$;
rollback;
