-- Pokerleague — een speler eist zijn profiel op
--
-- Het gevaarlijke scenario staat hier vooraan, want dat is waarom deze functie
-- security definer is: iemand die zich registreert mag het profiel van een
-- ander niet kunnen inpikken. De enige sleutel is het geverifieerde mailadres
-- uit zijn token, en dat kan hij niet zelf schrijven.
--
-- Verder wordt gecontroleerd wat er in de praktijk misgaat bij zulke koppelingen:
--
--   * dezelfde man mag geen tweede profiel krijgen — dan staat hij twee keer in
--     het ledenbestand met zijn historie bij de verkeerde helft
--   * twee keer opeisen hoort niets te doen; de spelerspagina roept dit bij
--     elk bezoek aan
--   * wie nog nooit speelde krijgt gewoon een nieuw profiel
--   * zijn resultaten komen mee, en alleen de zijne
\set ON_ERROR_STOP on
begin;

do $$
declare
  v_club uuid; v_struct uuid; v_pay uuid; v_tour uuid;
  v_oud uuid; v_vreemde uuid;
  v_uid uuid; v_uid2 uuid; v_uid3 uuid;
  v_geclaimd uuid; v_nogeens uuid; v_nieuw uuid;
  v_n int; v_prijs int;
  v_tp uuid;
begin
  insert into clubs (slug, name, city, country, locale, timezone)
  values ('t27', 'Testclub 27', 'Gent', 'BE', 'nl', 'Europe/Brussels') returning id into v_club;

  insert into blind_structures (club_id, name) values (v_club, 'S') returning id into v_struct;
  insert into blind_levels (structure_id, idx, is_break, small_blind, big_blind, ante, duration_s)
  values (v_struct, 0, false, 25, 50, 0, 1200);
  insert into payout_templates (club_id, name, tiers, rounding)
  values (v_club, 'P', '[{"min_entries":2,"max_entries":99,"percentages":[60,40]}]'::jsonb, 100)
  returning id into v_pay;

  insert into tournaments (club_id, payout_template_id, structure_id, name, scheduled_at,
                           status, player_visibility, buyin_cents, fee_cents,
                           starting_stack, max_reentries)
  values (v_club, v_pay, v_struct, 'Avond', now(), 'running'::tournament_status,
          'public'::visibility, 2000, 0, 20000, 1)
  returning id into v_tour;

  -- De floor typte deze twee ooit aan de deur in.
  v_tp := public.floor_add_entry(v_tour, null, 'Arne Halsberghe', 'arne@t27.be');
  select player_id into v_oud from tournament_players where id = v_tp;
  v_tp := public.floor_add_entry(v_tour, null, 'Iemand Anders', 'anders@t27.be');
  select player_id into v_vreemde from tournament_players where id = v_tp;

  -- Twee spelers, dus de avond kan afgesloten worden en er komen uitslagen.
  select tp.id into v_tp from tournament_players tp
  where tp.tournament_id = v_tour and tp.player_id = v_vreemde;
  perform public.floor_eliminate(v_tp, null);
  perform public.floor_finish_tournament(v_tour);

  insert into auth.users (email) values ('arne@t27.be')   returning id into v_uid;
  insert into auth.users (email) values ('nieuw@t27.be')  returning id into v_uid2;
  insert into auth.users (email) values ('dief@t27.be')   returning id into v_uid3;

  -- ------------------------------------------------------------------- 1 ---
  -- Opeisen op basis van het mailadres uit het token.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_uid, 'role', 'authenticated', 'email', 'arne@t27.be')::text, true);
  perform set_config('request.jwt.claim.sub', v_uid::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  v_geclaimd := public.claim_my_player('Arne', 'Halsberghe', 'arneh', true);
  if v_geclaimd <> v_oud then
    raise exception 'FOUT: hij kreeg een nieuw profiel in plaats van zijn bestaande';
  end if;
  raise notice 'OK  het bestaande profiel is opgeeist, met de historie eraan';

  -- ------------------------------------------------------------------- 2 ---
  -- Nog eens aanroepen mag niets veranderen.
  v_nogeens := public.claim_my_player();
  if v_nogeens <> v_oud then raise exception 'FOUT: tweede aanroep maakte iets nieuws'; end if;
  select count(*) into v_n from players where lower(email) = 'arne@t27.be' and merged_into_id is null;
  if v_n <> 1 then raise exception 'FOUT: er staan nu % profielen op dat adres', v_n; end if;
  raise notice 'OK  twee keer opeisen levert nog altijd één profiel op';

  -- ------------------------------------------------------------------- 3 ---
  -- Wat de speler zelf opgeeft wint van wat de floor intikte.
  if (select first_name from players where id = v_oud) <> 'Arne' then
    raise exception 'FOUT: de eigen voornaam is niet overgenomen';
  end if;
  if (select link_state from players where id = v_oud) <> 'claimed' then
    raise exception 'FOUT: de koppeling staat niet op claimed';
  end if;
  raise notice 'OK  eigen naam en gebruikersnaam overgenomen, status op claimed';

  -- ------------------------------------------------------------------- 4 ---
  -- Zijn resultaten, en alleen de zijne.
  select count(*) into v_n from public.my_results();
  if v_n <> 1 then raise exception 'FOUT: verwacht 1 eigen resultaat, kreeg %', v_n; end if;
  select prize_cents into v_prijs from public.my_results();
  if v_prijs is null then raise exception 'FOUT: eigen prijzengeld hoort zichtbaar te zijn'; end if;
  raise notice 'OK  eigen resultaten zichtbaar, met eigen prijzengeld';

  -- ------------------------------------------------------------------- 5 ---
  -- Een nieuwe speler die nog nooit ergens zat.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_uid2, 'role', 'authenticated', 'email', 'nieuw@t27.be')::text, true);
  perform set_config('request.jwt.claim.sub', v_uid2::text, true);

  v_nieuw := public.claim_my_player('Nieuwe', 'Speler', 'nieuwtje', false);
  if v_nieuw is null then raise exception 'FOUT: geen profiel aangemaakt'; end if;
  if v_nieuw = v_oud then raise exception 'FOUT: hij kreeg andermans profiel'; end if;
  select count(*) into v_n from public.my_results();
  if v_n <> 0 then raise exception 'FOUT: een nieuwe speler heeft geen resultaten'; end if;
  raise notice 'OK  wie nog nooit speelde krijgt een leeg eigen profiel';

  -- ------------------------------------------------------------------- 6 ---
  -- En het geval waarvoor dit allemaal bestaat: iemand met een ander
  -- mailadres mag het profiel van een vreemde niet opeisen. Hij kan het
  -- adres niet meesturen — het komt uit zijn token — dus hij krijgt gewoon
  -- een eigen, leeg profiel.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_uid3, 'role', 'authenticated', 'email', 'dief@t27.be')::text, true);
  perform set_config('request.jwt.claim.sub', v_uid3::text, true);

  if public.claim_my_player('Iemand', 'Anders', null, false) = v_vreemde then
    raise exception 'FOUT: het profiel van een vreemde was over te nemen';
  end if;
  if (select auth_user_id from players where id = v_vreemde) is not null then
    raise exception 'FOUT: het profiel van de vreemde is toch gekoppeld';
  end if;
  raise notice 'OK  andermans profiel blijft onaanraakbaar';

  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.role', '', true);
end $$;

rollback;

-- ---------------------------------------------------------------------------
-- De floor vindt iemand die elders op het platform speelt
-- ---------------------------------------------------------------------------
-- Zonder dit tikt de floor een bestaande speler in als nieuwe man. Dat gaat
-- goed dankzij het mailadres als sleutel, maar hij ziet het niet — en wat je
-- niet ziet, controleer je niet.

begin;
do $$
declare
  v_club uuid; v_ander uuid; v_owner uuid; v_p uuid;
  v_naam text; v_lid boolean; v_n int;
begin
  insert into clubs (slug, name, city, country, locale, timezone)
  values ('t29', 'Testclub 29', 'Gent', 'BE', 'nl', 'Europe/Brussels') returning id into v_club;
  insert into clubs (slug, name, city, country, locale, timezone)
  values ('t29b', 'Andere club', 'Aalst', 'BE', 'nl', 'Europe/Brussels') returning id into v_ander;

  insert into auth.users (email) values ('baas@t29.be') returning id into v_owner;
  insert into club_members (club_id, user_id, role) values (v_club, v_owner, 'owner');

  -- Iemand die bij de ándere club speelt.
  insert into players (display_name, email) values ('Reiziger Vanelders', 'reiziger@t29.be')
  returning id into v_p;
  insert into club_players (club_id, player_id) values (v_ander, v_p);

  perform set_config('request.jwt.claims',
    json_build_object('sub', v_owner, 'role', 'authenticated', 'email', 'baas@t29.be')::text, true);
  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  set local role authenticated;

  select display_name, is_member into v_naam, v_lid
  from public.floor_find_by_email(v_club, 'reiziger@t29.be');
  if v_naam is null then raise exception 'FOUT: bestaande speler niet gevonden op mailadres'; end if;
  if v_lid then raise exception 'FOUT: hij hoort geen lid van deze club te zijn'; end if;
  raise notice 'OK  de floor vindt % en ziet dat hij hier nog geen lid is', v_naam;

  -- Maar niet op een halve zoekterm: anders is dit een zoekmachine door de
  -- ledenbestanden van alle andere clubs.
  select count(*) into v_n from public.floor_find_by_email(v_club, 'reiziger');
  if v_n <> 0 then raise exception 'FOUT: een naamfragment gaf resultaten'; end if;
  select count(*) into v_n from public.floor_find_by_email(v_club, '@t29.be');
  if v_n <> 0 then raise exception 'FOUT: een half adres gaf resultaten'; end if;
  raise notice 'OK  alleen een volledig mailadres geeft een resultaat';

  reset role;
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.role', '', true);
end $$;
rollback;

-- ---------------------------------------------------------------------------
-- Het welkomstscherm wordt één keer doorlopen
-- ---------------------------------------------------------------------------
-- De spelerspagina stuurt door zolang `onboarded_at` leeg is. Zou dat veld bij
-- elk bezoek opnieuw gezet worden, dan komt iemand er nooit meer uit — of hij
-- krijgt het scherm elke keer opnieuw.

begin;
do $$
declare
  v_uid uuid; v_eerst timestamptz; v_daarna timestamptz;
begin
  insert into auth.users (email) values ('welkom@t35.be') returning id into v_uid;
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_uid, 'role', 'authenticated', 'email', 'welkom@t35.be')::text, true);
  perform set_config('request.jwt.claim.sub', v_uid::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  perform public.claim_my_player('Nieuwe', 'Speler', null, false);

  if (select onboarded_at from public.my_player()) is not null then
    raise exception 'FOUT: een verse speler staat al als afgerond gemarkeerd';
  end if;
  raise notice 'OK  een verse speler moet nog door het welkomstscherm';

  perform public.finish_onboarding();
  select onboarded_at into v_eerst from public.my_player();
  if v_eerst is null then raise exception 'FOUT: afvinken deed niets'; end if;

  perform pg_sleep(0.01);
  perform public.finish_onboarding();
  select onboarded_at into v_daarna from public.my_player();
  if v_daarna <> v_eerst then
    raise exception 'FOUT: nog eens afvinken verzette de datum van % naar %', v_eerst, v_daarna;
  end if;
  raise notice 'OK  nog eens afvinken laat het oorspronkelijke moment staan';

  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.role', '', true);
end $$;
rollback;

-- ---------------------------------------------------------------------------
-- Wat er bij registratie afgedwongen wordt
-- ---------------------------------------------------------------------------
-- Een formulier is een suggestie. Deze drie regels moeten in de database
-- staan, want anders houden ze alleen stand zolang iedereen het formulier
-- gebruikt.

begin;
do $$
declare
  v_uid uuid; v_uid2 uuid; v_p uuid; v_n int; v_toen timestamptz;
begin
  -- 1 --- Achttien. Zelf ingetikt bewijst niets, maar wie zegt dat hij vijftien
  --       is, hoort geen account te krijgen.
  insert into auth.users (email) values ('kind@t36.be') returning id into v_uid;
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_uid, 'role', 'authenticated', 'email', 'kind@t36.be')::text, true);
  perform set_config('request.jwt.claim.sub', v_uid::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  begin
    perform public.claim_my_player('Te', 'Jong', 'tejong', false, 'nl',
                                   (current_date - interval '15 years')::date, true);
    raise exception 'FOUT: een vijftienjarige kreeg een account';
  exception
    when check_violation then raise notice 'OK  onder de achttien komt er geen account';
  end;

  -- En ook niet via de achterdeur, met een rechtstreekse update.
  v_p := public.claim_my_player('Te', 'Jong', 'tejong', false, 'nl', null, true);
  begin
    update players set birthdate = (current_date - interval '15 years')::date where id = v_p;
    raise exception 'FOUT: de geboortedatum was alsnog naar minderjarig te zetten';
  exception
    when check_violation then raise notice 'OK  ook een rechtstreekse update wordt geweigerd';
  end;

  -- 2 --- Toestemming wordt vastgelegd met het moment erbij, en een tweede
  --       argumentloze aanroep wist ze niet.
  select stats_consent_at into v_toen from players where id = v_p;
  if v_toen is null then raise exception 'FOUT: de toestemming is niet vastgelegd'; end if;

  perform public.claim_my_player();
  if (select stats_consent_at from players where id = v_p) is distinct from v_toen then
    raise exception 'FOUT: een bezoek aan /ik veranderde het toestemmingsmoment';
  end if;
  raise notice 'OK  toestemming wordt met tijdstip bewaard en blijft staan';

  -- 3 --- Gebruikersnamen zijn uniek, ongeacht hoofdletters.
  if public.username_available('tejong')  then raise exception 'FOUT: bezette naam gold als vrij'; end if;
  if public.username_available('TeJong')  then raise exception 'FOUT: hoofdletters omzeilden de controle'; end if;
  if not public.username_available('vrij') then raise exception 'FOUT: een vrije naam gold als bezet'; end if;
  if public.username_available('ab')      then raise exception 'FOUT: te kort werd toegelaten'; end if;
  if public.username_available('met spatie') then raise exception 'FOUT: een spatie werd toegelaten'; end if;
  raise notice 'OK  gebruikersnamen zijn uniek en de vorm wordt bewaakt';

  -- En de database weigert het dubbel ook echt, niet alleen de controlefunctie.
  insert into auth.users (email) values ('twee@t36.be') returning id into v_uid2;
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_uid2, 'role', 'authenticated', 'email', 'twee@t36.be')::text, true);
  perform set_config('request.jwt.claim.sub', v_uid2::text, true);

  -- En het belangrijkste: een bezette naam mag het account niet kosten. Dit
  -- ging in productie mis — iemand bevestigde zijn mailadres, kreeg
  -- "we konden je profiel niet vinden of aanmaken", en had een account in
  -- auth.users dat nergens anders bestond. Het profiel is het punt; de
  -- gebruikersnaam is een voorkeur.
  declare v_ander uuid;
  begin
    v_ander := public.claim_my_player('Iemand', 'Anders', 'TeJong', false, 'nl',
                                      (current_date - interval '30 years')::date, true);
    if v_ander is null then raise exception 'FOUT: een bezette naam kostte hem zijn profiel'; end if;
    if v_ander = v_p then raise exception 'FOUT: hij kreeg het profiel van iemand anders'; end if;
    if (select username from players where id = v_ander) is not null then
      raise exception 'FOUT: de bezette naam werd toch toegekend';
    end if;
    select count(*) into v_n from players where lower(username) = 'tejong' and merged_into_id is null;
    if v_n <> 1 then raise exception 'FOUT: % spelers met dezelfde gebruikersnaam', v_n; end if;
    raise notice 'OK  een bezette naam kost geen account; het profiel komt er zonder naam';
  end;

  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.role', '', true);
end $$;
rollback;

-- ---------------------------------------------------------------------------
-- Wat een speler ziet van de avond waar hij nu in zit
-- ---------------------------------------------------------------------------
-- En vooral: dat hij alleen zijn eigen stapel kan wijzigen. Die functie geeft
-- geen rechten, maar de startpagina hangt eraan — dus als hier ooit iets
-- verschuift, moet dat opvallen.

begin;
do $$
declare
  v_club uuid; v_struct uuid; v_pay uuid; v_tour uuid;
  v_tp_a uuid; v_tp_b uuid; v_a uuid; v_b uuid; v_uid uuid;
  v_n int; v_chips int; v_avg int; v_left int;
begin
  insert into clubs (slug, name, city, country, locale, timezone)
  values ('t37', 'Testclub 37', 'Gent', 'BE', 'nl', 'Europe/Brussels') returning id into v_club;
  insert into blind_structures (club_id, name) values (v_club, 'S') returning id into v_struct;
  insert into blind_levels (structure_id, idx, is_break, small_blind, big_blind, ante, duration_s)
  values (v_struct, 0, false, 25, 50, 0, 1200);
  insert into payout_templates (club_id, name, tiers, rounding)
  values (v_club, 'P', '[{"min_entries":2,"max_entries":99,"percentages":[100]}]'::jsonb, 100)
  returning id into v_pay;
  insert into tournaments (club_id, payout_template_id, structure_id, name, scheduled_at,
                           status, player_visibility, buyin_cents, fee_cents,
                           starting_stack, max_reentries)
  values (v_club, v_pay, v_struct, 'Loopt nu', now(), 'running'::tournament_status,
          'public'::visibility, 2000, 0, 20000, 0)
  returning id into v_tour;

  v_tp_a := public.floor_add_entry(v_tour, null, 'Speler A', 'a@t37.be');
  v_tp_b := public.floor_add_entry(v_tour, null, 'Speler B', 'b@t37.be');
  select player_id into v_a from tournament_players where id = v_tp_a;
  select player_id into v_b from tournament_players where id = v_tp_b;

  insert into auth.users (email) values ('a@t37.be') returning id into v_uid;
  update players set auth_user_id = v_uid, link_state = 'claimed' where id = v_a;

  perform set_config('request.jwt.claims',
    json_build_object('sub', v_uid, 'role', 'authenticated', 'email', 'a@t37.be')::text, true);
  perform set_config('request.jwt.claim.sub', v_uid::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  set local role authenticated;

  select count(*) into v_n from public.my_live_tournaments();
  if v_n <> 1 then raise exception 'FOUT: verwacht 1 lopend tornooi, kreeg %', v_n; end if;

  select players_left, avg_stack into v_left, v_avg from public.my_live_tournaments();
  if v_left <> 2 then raise exception 'FOUT: verwacht 2 spelers over, kreeg %', v_left; end if;
  if v_avg <> 20000 then raise exception 'FOUT: gemiddelde stapel klopt niet: %', v_avg; end if;
  raise notice 'OK  hij ziet de avond waar hij in zit, met de juiste cijfers';

  -- Zijn eigen stapel mag hij wijzigen.
  update tournament_players set chip_count = 31500 where id = v_tp_a;
  select my_chips into v_chips from public.my_live_tournaments();
  if v_chips <> 31500 then raise exception 'FOUT: zijn eigen stapel bleef op %', v_chips; end if;
  raise notice 'OK  hij geeft zijn eigen stapel in';

  -- Die van zijn buurman niet.
  begin
    update tournament_players set chip_count = 1 where id = v_tp_b;
    if (select chip_count from tournament_players where id = v_tp_b) = 1 then
      raise exception 'FOUT: hij wijzigde de stapel van iemand anders';
    end if;
    raise notice 'OK  de stapel van een ander bleef ongemoeid';
  exception
    when insufficient_privilege then
      raise notice 'OK  de stapel van een ander wordt geweigerd';
  end;

  reset role;

  -- Een afgesloten avond hoort hier niet meer bij.
  --
  -- De claims moeten even weg voor deze twee: met een spelerstoken in de
  -- sessie is `is_service_context()` onwaar, en dan weigert de floorfunctie
  -- terecht — deze speler is geen staf. Dat de test daarop viel is dus geen
  -- storing maar het bewijs dat de afscherming werkt.
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.role', '', true);
  perform public.floor_eliminate(v_tp_b, null);
  perform public.floor_finish_tournament(v_tour);

  perform set_config('request.jwt.claims',
    json_build_object('sub', v_uid, 'role', 'authenticated', 'email', 'a@t37.be')::text, true);
  perform set_config('request.jwt.claim.sub', v_uid::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  set local role authenticated;
  select count(*) into v_n from public.my_live_tournaments();
  if v_n <> 0 then raise exception 'FOUT: een afgesloten avond staat nog bij de lopende'; end if;
  raise notice 'OK  een afgesloten avond verdwijnt uit de lijst';

  reset role;
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.role', '', true);
end $$;
rollback;
