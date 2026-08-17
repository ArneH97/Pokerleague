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
