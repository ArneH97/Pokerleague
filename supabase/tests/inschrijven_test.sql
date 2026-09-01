-- Pokerleague — vooraf inschrijven voor een avond
--
-- Dit is de eerste functie in het product die openstaat voor iemand zonder
-- account. Dat verdient scherpere bewaking dan de rest: ze draait als
-- eigenaar, ze schrijft in drie tabellen, en iedereen op internet kan ze
-- aanroepen. Wat hier getest wordt is dus niet alleen of ze werkt, maar
-- vooral of ze niets méér doet dan afgesproken.
--
-- Bewaakt wordt:
--
--   1. de kaart voor de affiche wijst naar de eerstvolgende avond en verklapt
--      geen namen
--   2. inschrijven maakt een speler, koppelt hem aan de club en zet een
--      uitnodiging klaar — zonder account
--   3. twee keer hetzelfde adres levert geen tweede inschrijving op
--   4. te jong gaat niet door, en een onmogelijk mailadres ook niet
--   5. een avond die al bezig of afgelopen is, staat dicht
--   6. wie vooraf inschreef, krijgt aan de deur de bonuschips; wie niet
--      inschreef krijgt de gewone stapel
--   7. de lijst met namen is alleen voor de staf
--   8. iemand die al bij een andere club speelt, krijgt geen tweede profiel

begin;

do $$
declare
  v_club uuid; v_ander uuid; v_struct uuid; v_pay uuid;
  v_t uuid; v_oud uuid; v_bezig uuid;
  v_user uuid; v_floor uuid; v_speler uuid;
  v_p uuid; v_tp uuid;
  v_res jsonb; v_n int; v_chips int;
  r record;
begin
  insert into clubs (slug, name, city, country, locale, timezone, primary_color,
                     address_line)
  values ('ti1', 'Inschrijfclub', 'Baardegem', 'BE', 'nl', 'Europe/Brussels',
          '#c8a15c', 'Dorpsstraat 1, 9310 Baardegem')
  returning id into v_club;

  insert into clubs (slug, name, city, country, locale, timezone)
  values ('ti2', 'Andere club', 'Gent', 'BE', 'nl', 'Europe/Brussels')
  returning id into v_ander;

  insert into blind_structures (club_id, name) values (v_club, 'S') returning id into v_struct;
  insert into blind_levels (structure_id, idx, is_break, small_blind, big_blind, ante, duration_s)
  values (v_struct, 0, false, 25, 50, 0, 1200);
  insert into payout_templates (club_id, name, tiers, rounding)
  values (v_club, 'P', '[{"min_entries":2,"max_entries":99,"percentages":[100]}]'::jsonb, 100)
  returning id into v_pay;

  -- De openingsavond: over een week, 25 euro, 20.000 chips, 5.000 bonus.
  insert into tournaments (club_id, payout_template_id, structure_id, name, scheduled_at,
                           status, buyin_cents, fee_cents, starting_stack,
                           prereg_bonus_stack)
  values (v_club, v_pay, v_struct, 'Openingsavond', now() + interval '7 days',
          'scheduled'::tournament_status, 2000, 500, 20000, 5000)
  returning id into v_t;

  -- Eentje verder in de toekomst, om te zien dat de kaart de eerstvolgende pakt.
  insert into tournaments (club_id, payout_template_id, structure_id, name, scheduled_at,
                           status, buyin_cents, fee_cents, starting_stack)
  values (v_club, v_pay, v_struct, 'Later dit jaar', now() + interval '40 days',
          'scheduled'::tournament_status, 2000, 500, 20000);

  -- ------------------------------------------------------------------- 1 ---
  select * into r from public.tournament_signup_card('ti1');
  if r.name <> 'Openingsavond' then
    raise exception 'FOUT: de kaart wijst naar % in plaats van de eerstvolgende avond', r.name;
  end if;
  if r.bonus_stack <> 5000 or r.starting_stack <> 20000 or r.buyin_cents <> 2000 then
    raise exception 'FOUT: de cijfers op de kaart kloppen niet';
  end if;
  if not r.is_open then raise exception 'FOUT: de inschrijving staat dicht terwijl ze open hoort'; end if;
  if r.registered <> 0 then raise exception 'FOUT: % inschrijvingen op een lege avond', r.registered; end if;
  if r.address_line is null or r.club_name <> 'Inschrijfclub' then
    raise exception 'FOUT: de clubgegevens staan niet op de kaart';
  end if;
  raise notice 'OK  de kaart wijst naar de eerstvolgende avond, met de juiste cijfers';

  -- ------------------------------------------------------------------- 2 ---
  -- Als bezoeker zonder account.
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.role', 'anon', true);
  set local role anon;

  v_res := public.rsvp_for_tournament(v_t, 'Jan', 'Peeters', 'jan@test.be', '1988-04-12');
  if v_res->>'status' <> 'ok' then raise exception 'FOUT: inschrijven gaf % in plaats van ok', v_res; end if;

  reset role;

  select id into v_p from players where lower(email) = 'jan@test.be';
  if v_p is null then raise exception 'FOUT: er is geen spelersprofiel aangemaakt'; end if;

  select count(*) into v_n from club_players where club_id = v_club and player_id = v_p;
  if v_n <> 1 then raise exception 'FOUT: hij is niet aan de club gekoppeld'; end if;

  select count(*) into v_n from player_invites where club_id = v_club and player_id = v_p;
  if v_n <> 1 then raise exception 'FOUT: er staat geen uitnodiging klaar'; end if;

  select count(*) into v_n from tournament_registrations
   where tournament_id = v_t and player_id = v_p and cancelled_at is null;
  if v_n <> 1 then raise exception 'FOUT: de inschrijving staat er niet'; end if;

  select * into r from public.tournament_signup_card('ti1');
  if r.registered <> 1 then raise exception 'FOUT: de teller staat op %', r.registered; end if;
  raise notice 'OK  zonder account: speler aangemaakt, gekoppeld, uitgenodigd en ingeschreven';

  -- ------------------------------------------------------------------- 3 ---
  set local role anon;
  v_res := public.rsvp_for_tournament(v_t, 'Jan', 'Peeters', 'JAN@test.be', '1988-04-12');
  reset role;
  if v_res->>'status' <> 'already' then
    raise exception 'FOUT: tweede keer inschrijven gaf % in plaats van already', v_res;
  end if;

  select count(*) into v_n from tournament_registrations where tournament_id = v_t;
  if v_n <> 1 then raise exception 'FOUT: % inschrijvingen na een dubbele poging', v_n; end if;

  select count(*) into v_n from players where lower(email) = 'jan@test.be';
  if v_n <> 1 then raise exception 'FOUT: er staan % profielen op hetzelfde adres', v_n; end if;
  raise notice 'OK  hetzelfde adres levert geen tweede inschrijving en geen tweede profiel';

  -- ------------------------------------------------------------------- 4 ---
  set local role anon;
  v_res := public.rsvp_for_tournament(v_t, 'Kind', 'Jong', 'kind@test.be',
                                      (current_date - interval '15 years')::date);
  if v_res->>'status' <> 'too_young' then raise exception 'FOUT: een 15-jarige kreeg %', v_res->>'status'; end if;

  v_res := public.rsvp_for_tournament(v_t, 'Geen', 'Adres', 'nietsmail', '1990-01-01');
  if v_res->>'status' <> 'bad_email' then raise exception 'FOUT: een kapot adres gaf %', v_res->>'status'; end if;

  v_res := public.rsvp_for_tournament(v_t, null, null, 'naamloos@test.be', '1990-01-01');
  if v_res->>'status' <> 'bad_name' then raise exception 'FOUT: zonder naam gaf %', v_res->>'status'; end if;
  reset role;

  select count(*) into v_n from players
   where lower(email) in ('kind@test.be', 'naamloos@test.be');
  if v_n <> 0 then raise exception 'FOUT: een geweigerde inschrijving maakte toch % profielen', v_n; end if;
  raise notice 'OK  te jong, een kapot adres en een lege naam gaan niet door en laten niets achter';

  -- ------------------------------------------------------------------- 5 ---
  insert into tournaments (club_id, payout_template_id, structure_id, name, scheduled_at,
                           status, buyin_cents, fee_cents, starting_stack)
  values (v_club, v_pay, v_struct, 'Gisteren', now() - interval '1 day',
          'finished'::tournament_status, 2000, 500, 20000)
  returning id into v_oud;

  insert into tournaments (club_id, payout_template_id, structure_id, name, scheduled_at,
                           status, buyin_cents, fee_cents, starting_stack)
  values (v_club, v_pay, v_struct, 'Nu bezig', now() - interval '1 hour',
          'running'::tournament_status, 2000, 500, 20000)
  returning id into v_bezig;

  set local role anon;
  v_res := public.rsvp_for_tournament(v_oud, 'Te', 'Laat', 'laat@test.be', '1990-01-01');
  if v_res->>'status' <> 'closed' then raise exception 'FOUT: een afgelopen avond gaf %', v_res->>'status'; end if;

  v_res := public.rsvp_for_tournament(v_bezig, 'Te', 'Laat', 'laat@test.be', '1990-01-01');
  if v_res->>'status' <> 'closed' then raise exception 'FOUT: een lopende avond gaf %', v_res->>'status'; end if;
  reset role;
  raise notice 'OK  een avond die bezig of afgelopen is, staat dicht';

  -- ------------------------------------------------------------------- 6 ---
  -- De bonus aan de deur. Jan schreef in, Piet niet.
  --
  -- De rolclaim moet hier leeg: `reset role` zet de databankrol terug, maar
  -- de JWT-claim blijft op 'anon' staan en dan telt dit niet als
  -- servicecontext — en dan weigert de floor-functie, terecht.
  perform set_config('request.jwt.claim.role', '', true);

  v_tp := public.floor_add_entry(v_t, v_p, null, null);
  select chip_count into v_chips from tournament_players where id = v_tp;
  if v_chips <> 25000 then
    raise exception 'FOUT: wie inschreef begint met % chips in plaats van 25000', v_chips;
  end if;

  v_tp := public.floor_add_entry(v_t, null, 'Piet Zonder', 'piet@test.be');
  select chip_count into v_chips from tournament_players where id = v_tp;
  if v_chips <> 20000 then
    raise exception 'FOUT: wie niet inschreef begint met % chips in plaats van 20000', v_chips;
  end if;

  -- En de inschrijving is nu een deelname geworden, dus de teller loopt terug.
  select * into r from public.tournament_signup_card('ti1');
  if r.registered <> 0 then
    raise exception 'FOUT: de teller staat nog op % nadat hij aan tafel zat', r.registered;
  end if;
  raise notice 'OK  wie vooraf inschreef krijgt 5.000 chips extra, wie niet inschreef niet';

  -- Twee keer aan tafel komen mag de bonus niet twee keer geven: de tweede
  -- aanroep geeft dezelfde rij terug en er wordt niets ingevoegd.
  v_tp := public.floor_add_entry(v_t, v_p, null, null);
  select chip_count into v_chips from tournament_players where id = v_tp;
  if v_chips <> 25000 then
    raise exception 'FOUT: de bonus is dubbel gegeven (% chips)', v_chips;
  end if;
  raise notice 'OK  de bonus wordt niet dubbel gegeven';

  -- ------------------------------------------------------------------- 7 ---
  insert into auth.users (email) values ('floor@ti1.be') returning id into v_floor;
  insert into auth.users (email) values ('speler@ti1.be') returning id into v_speler;
  insert into club_members (club_id, user_id, role)
  values (v_club, v_floor, 'floor'::club_role);

  perform set_config('request.jwt.claim.sub', v_floor::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_floor, 'role', 'authenticated')::text, true);
  set local role authenticated;

  select count(*) into v_n from public.tournament_rsvp_list(v_t);
  if v_n <> 0 then
    raise exception 'FOUT: de floor ziet % inschrijvingen terwijl iedereen al aan tafel zit', v_n;
  end if;
  reset role;

  -- Nog eentje inschrijven zodat er iets te zien is.
  set local role anon;
  v_res := public.rsvp_for_tournament(v_t, 'Marie', 'Claes', 'marie@test.be', '1979-09-09');
  reset role;
  if v_res->>'status' <> 'ok' then raise exception 'FOUT: Marie kreeg %', v_res->>'status'; end if;

  perform set_config('request.jwt.claim.sub', v_floor::text, true);
  set local role authenticated;
  select * into r from public.tournament_rsvp_list(v_t) limit 1;
  if r.display_name <> 'Marie Claes' or r.has_account then
    raise exception 'FOUT: de lijst toont % (account: %)', r.display_name, r.has_account;
  end if;
  if r.at_table then raise exception 'FOUT: Marie zit al aan tafel volgens de lijst'; end if;
  reset role;

  -- Een gewone speler mag die lijst niet zien.
  perform set_config('request.jwt.claim.sub', v_speler::text, true);
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_speler, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin
    perform * from public.tournament_rsvp_list(v_t);
    raise exception 'FOUT: een gewone speler kreeg de namenlijst te zien';
  exception when insufficient_privilege then
    null;
  end;
  reset role;
  raise notice 'OK  de namenlijst is alleen voor de staf';

  -- ------------------------------------------------------------------- 8 ---
  -- Marie speelt ook bij de andere club. Ze hoort daar één profiel te houden.
  insert into club_players (club_id, player_id)
  select v_ander, id from players where lower(email) = 'marie@test.be';

  set local role anon;
  v_res := public.rsvp_for_tournament(v_t, 'Marie', 'Claes', 'marie@test.be', '1979-09-09');
  reset role;

  select count(*) into v_n from players where lower(email) = 'marie@test.be';
  if v_n <> 1 then raise exception 'FOUT: Marie heeft % profielen', v_n; end if;

  select count(*) into v_n from club_players cp
   join players p on p.id = cp.player_id
   where lower(p.email) = 'marie@test.be';
  if v_n <> 2 then raise exception 'FOUT: Marie hoort bij % clubs in plaats van 2', v_n; end if;
  raise notice 'OK  wie al ergens speelt, houdt één profiel over alle clubs heen';

  -- ------------------------------------------------------------------- 9 ---
  -- Een inschrijving intrekken, en daarna weer inschrijven.
  perform set_config('request.jwt.claim.sub', v_floor::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_floor, 'role', 'authenticated')::text, true);
  set local role authenticated;

  select p.id into v_p from players p where lower(p.email) = 'marie@test.be';
  if not public.cancel_rsvp(v_t, v_p) then
    raise exception 'FOUT: intrekken gaf onwaar terug';
  end if;

  select count(*) into v_n from public.tournament_rsvp_list(v_t);
  if v_n <> 0 then raise exception 'FOUT: na het intrekken staan er nog % namen', v_n; end if;

  -- Een tweede keer intrekken verandert niets meer en mag geen fout geven.
  if public.cancel_rsvp(v_t, v_p) then
    raise exception 'FOUT: twee keer intrekken deed alsof er iets veranderde';
  end if;
  reset role;

  -- En daarna kan ze zich gewoon opnieuw inschrijven.
  perform set_config('request.jwt.claim.role', 'anon', true);
  set local role anon;
  v_res := public.rsvp_for_tournament(v_t, 'Marie', 'Claes', 'marie@test.be', '1979-09-09');
  reset role;
  if v_res->>'status' <> 'ok' then
    raise exception 'FOUT: opnieuw inschrijven na intrekken gaf %', v_res->>'status';
  end if;

  perform set_config('request.jwt.claim.sub', v_floor::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  set local role authenticated;
  select count(*) into v_n from public.tournament_rsvp_list(v_t);
  if v_n <> 1 then raise exception 'FOUT: na opnieuw inschrijven staan er % namen', v_n; end if;
  reset role;

  -- Een gewone speler mag niemand van de lijst halen.
  perform set_config('request.jwt.claim.sub', v_speler::text, true);
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_speler, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin
    perform public.cancel_rsvp(v_t, v_p);
    raise exception 'FOUT: een gewone speler kon een inschrijving intrekken';
  exception when insufficient_privilege then
    null;
  end;
  reset role;
  raise notice 'OK  staf kan een inschrijving intrekken; daarna kan die persoon zich opnieuw inschrijven';

  -- ------------------------------------------------------------------ 10 ---
  -- Het antwoord zegt of er al een account is. Daar hangt aan af of het
  -- scherm naar "registreren" of naar "aanmelden" wijst.
  select id into v_p from players where lower(email) = 'jan@test.be';
  if (select auth_user_id from players where id = v_p) is not null then
    raise exception 'FOUT: Jan heeft al een account en dat hoort niet in deze opzet';
  end if;

  perform set_config('request.jwt.claim.role', 'anon', true);
  set local role anon;
  v_res := public.rsvp_for_tournament(v_t, 'Jan', 'Peeters', 'jan@test.be', '1988-04-12');
  reset role;
  if (v_res->>'has_account')::boolean then
    raise exception 'FOUT: Jan heeft geen account maar het antwoord zegt van wel';
  end if;

  -- En nu wél. Zijn profiel krijgt een account gekoppeld.
  update players set auth_user_id = v_speler, link_state = 'claimed' where id = v_p;

  perform set_config('request.jwt.claim.role', 'anon', true);
  set local role anon;
  v_res := public.rsvp_for_tournament(v_t, 'Jan', 'Peeters', 'jan@test.be', '1988-04-12');
  reset role;
  if not (v_res->>'has_account')::boolean then
    raise exception 'FOUT: Jan heeft een account maar het antwoord zegt van niet';
  end if;

  -- Een gloednieuw adres kan per definitie geen account hebben.
  perform set_config('request.jwt.claim.role', 'anon', true);
  set local role anon;
  v_res := public.rsvp_for_tournament(v_t, 'Nieuwe', 'Speler', 'nieuw@test.be', '1985-05-05');
  reset role;
  if v_res->>'status' <> 'ok' or (v_res->>'has_account')::boolean then
    raise exception 'FOUT: een nieuw adres gaf % / %', v_res->>'status', v_res->>'has_account';
  end if;
  raise notice 'OK  het antwoord zegt of er al een PokerLeague-account op dat adres staat';

  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);
  perform set_config('request.jwt.claims', '', true);
end $$;

rollback;
