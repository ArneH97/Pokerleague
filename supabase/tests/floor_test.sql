-- Tests voor de floor-handelingen: toevoegen, inkopen, uitschakelen,
-- terugdraaien en afsluiten. Draait in een transactie die terugrolt.

begin;

do $$
declare
  v_club uuid; v_season uuid; v_rc uuid; v_pt uuid; v_tour uuid;
  v_tps uuid[] := array[]::uuid[]; v_tp uuid;
  i int; v_pos int; v_n int; v_pot int; v_paid int;
  v_naam text;
begin
  insert into clubs (slug, name, compliance)
  values ('t-' || substr(gen_random_uuid()::text, 1, 12), 'Floortest',
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
                           status, buyin_cents, fee_cents, starting_stack, bounty_mode, bounty_cents)
  values (v_club, v_season, v_pt, 'Floortornooi', now(), 'running', 2000, 500, 20000, 'fixed', 500)
  returning id into v_tour;

  -- ---------------------------------------------------------------- toevoegen
  for i in 1 .. 6 loop
    v_tp := public.floor_add_entry(
      v_tour, null, format('Speler %s', i),
      format('speler%s-%s@test.be', i, substr(gen_random_uuid()::text, 1, 8)));
    v_tps := v_tps || v_tp;
  end loop;

  assert (select count(*) from tournament_players where tournament_id = v_tour) = 6,
    'niet alle spelers werden toegevoegd';
  assert (select count(*) from buyins where tournament_id = v_tour) = 6,
    'niet elke speler kreeg een inkoop';
  assert (select chip_count from tournament_players where id = v_tps[1]) = 20000,
    'startstack werd niet toegekend';
  assert (select bounty_cents from buyins where tournament_player_id = v_tps[1]) = 500,
    'bounty werd niet mee geboekt';

  -- Dezelfde speler nog eens toevoegen mag geen dubbele inkoop geven.
  v_tp := public.floor_add_entry(v_tour, (select player_id from tournament_players where id = v_tps[1]));
  assert v_tp = v_tps[1], 'bestaande deelnemer kreeg een tweede rij';
  assert (select count(*) from buyins where tournament_id = v_tour) = 6,
    'er werd dubbel geboekt';

  -- ------------------------------------------------------------- uitschakelen
  -- Zes spelers: de eerste die afvalt wordt zesde.
  v_pos := public.floor_eliminate(v_tps[6], v_tps[1]);
  assert v_pos = 6, format('eerste afvaller hoort zesde te worden, kreeg %s', v_pos);
  assert (select bounties_won from tournament_players where id = v_tps[1]) = 1,
    'knock-out werd niet bijgeschreven';
  assert (select bounty_cents from eliminations where tournament_player_id = v_tps[6]) = 500,
    'bounty werd niet vastgelegd bij de uitschakeling';

  v_pos := public.floor_eliminate(v_tps[5], v_tps[1]);
  assert v_pos = 5, format('tweede afvaller hoort vijfde te worden, kreeg %s', v_pos);

  -- Nog eens uitschakelen verandert niets.
  v_pos := public.floor_eliminate(v_tps[5], null);
  assert v_pos = 5, 'dubbele uitschakeling gaf een andere plaats';

  -- ---------------------------------------------------------- terugdraaien
  perform public.floor_undo_elimination(v_tps[5]);
  assert (select status from tournament_players where id = v_tps[5]) = 'active',
    'terugdraaien zette de speler niet terug op actief';
  assert (select chip_count from tournament_players where id = v_tps[5]) = 20000,
    'terugdraaien mag de chipcount niet kwijtspelen';
  assert (select finish_position from tournament_players where id = v_tps[6]) = 6,
    'de plaats van de andere afvaller klopt niet meer na terugdraaien';

  -- ------------------------------------------------------------------ rebuy
  perform public.floor_rebuy(v_tps[6], 'reentry');
  assert (select status from tournament_players where id = v_tps[6]) = 'active',
    're-entry bracht de speler niet terug';
  assert (select finish_position from tournament_players where id = v_tps[6]) is null,
    're-entry liet een eindplaats staan';
  assert (select chip_count from tournament_players where id = v_tps[6]) = 20000,
    're-entry hoort precies één verse startstack te geven';
  assert (select reentries_used from tournament_players where id = v_tps[6]) = 1,
    're-entryteller klopt niet';
  assert (select count(*) from buyins where tournament_id = v_tour) = 7,
    're-entry werd niet als inkoop geboekt';

  -- ----------------------------------------------------------------- afsluiten
  -- Geef iedereen een verschillende stack, zodat de eindstand voorspelbaar is.
  for i in 1 .. 6 loop
    update tournament_players set chip_count = i * 1000 where id = v_tps[i];
  end loop;

  v_n := public.floor_finish_tournament(v_tour);
  assert v_n = 6, format('verwacht 6 resultaatrijen, kreeg %s', v_n);
  assert (select status from tournaments where id = v_tour) = 'finished',
    'tornooi staat niet op afgelopen';

  -- Grootste stapel wint.
  select p.display_name into v_naam
  from tournament_results r join players p on p.id = r.player_id
  where r.tournament_id = v_tour and r.position = 1;
  assert v_naam = 'Speler 6', format('winnaar werd %s in plaats van de grootste stack', v_naam);

  -- Iedereen heeft een unieke plaats.
  select count(distinct position) into v_n from tournament_results where tournament_id = v_tour;
  assert v_n = 6, 'er zijn dubbele eindplaatsen';

  -- Pot klopt: 7 inkopen x €20.
  select coalesce(sum(amount_cents),0) into v_pot from buyins where tournament_id = v_tour and not is_void;
  select coalesce(sum(prize_cents),0) into v_paid from tournament_results where tournament_id = v_tour;
  assert v_pot = 7 * 2000, format('pot verwacht %s, kreeg %s', 7 * 2000, v_pot);
  assert v_paid = v_pot, format('uitbetaald %s <> pot %s', v_paid, v_pot);

  raise notice 'floor OK: 6 spelers, 7 inkopen, pot % cent volledig uitbetaald', v_pot;
end $$;

-- ---------------------------------------------------------------------------
-- Rechten: een buitenstaander mag niets van dit alles
-- ---------------------------------------------------------------------------

do $$
declare
  v_club uuid; v_tour uuid; v_tp uuid; v_geweigerd int := 0;
begin
  insert into clubs (slug, name)
  values ('t-' || substr(gen_random_uuid()::text, 1, 12), 'Afgeschermd') returning id into v_club;
  insert into tournaments (club_id, name, scheduled_at, status)
  values (v_club, 'X', now(), 'running') returning id into v_tour;
  v_tp := public.floor_add_entry(v_tour, null, 'Iemand', null, 'test');

  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', gen_random_uuid()::text, true);

  begin perform public.floor_add_entry(v_tour, null, 'Indringer', null, 'test');
  exception when insufficient_privilege then v_geweigerd := v_geweigerd + 1; end;

  begin perform public.floor_eliminate(v_tp, null);
  exception when insufficient_privilege then v_geweigerd := v_geweigerd + 1; end;

  begin perform public.floor_rebuy(v_tp, 'reentry');
  exception when insufficient_privilege then v_geweigerd := v_geweigerd + 1; end;

  begin perform public.floor_finish_tournament(v_tour);
  exception when insufficient_privilege then v_geweigerd := v_geweigerd + 1; end;

  perform set_config('request.jwt.claim.role', '', true);
  perform set_config('request.jwt.claim.sub', '', true);

  assert v_geweigerd = 4, format('verwacht 4 weigeringen, kreeg %s', v_geweigerd);
  raise notice 'rechten OK: 4 van 4 handelingen geweigerd voor een buitenstaander';
end $$;


-- ---------------------------------------------------------------------------
-- Het mailadres als sleutel bij een nieuwe speler
-- ---------------------------------------------------------------------------

do $$
declare
  v_club1 uuid; v_club2 uuid; v_t1 uuid; v_t2 uuid;
  v_tp uuid; v_tp2 uuid; v_p1 uuid; v_p2 uuid;
  v_mail text := 'jan-' || substr(gen_random_uuid()::text, 1, 8) || '@voorbeeld.be';
  v_geweigerd int := 0; v_n int;
begin
  insert into clubs (slug, name, compliance)
  values ('t-' || substr(gen_random_uuid()::text, 1, 12), 'Mailclub A',
          jsonb_build_object('enforce','off'))
  returning id into v_club1;
  insert into clubs (slug, name, compliance)
  values ('t-' || substr(gen_random_uuid()::text, 1, 12), 'Mailclub B',
          jsonb_build_object('enforce','off'))
  returning id into v_club2;

  insert into tournaments (club_id, name, scheduled_at, status, buyin_cents, starting_stack)
  values (v_club1, 'A', now(), 'running', 2000, 20000) returning id into v_t1;
  insert into tournaments (club_id, name, scheduled_at, status, buyin_cents, starting_stack)
  values (v_club2, 'B', now(), 'running', 2000, 20000) returning id into v_t2;

  -- Zonder mailadres én zonder reden gaat het niet door.
  begin
    perform public.floor_add_entry(v_t1, null, 'Naamloos');
  exception when check_violation then v_geweigerd := v_geweigerd + 1;
  end;
  assert v_geweigerd = 1, 'toevoegen zonder mailadres en zonder reden hoort te falen';

  -- Een adres dat geen adres is, ook niet.
  begin
    perform public.floor_add_entry(v_t1, null, 'Fout', 'geen adres');
  exception when check_violation then v_geweigerd := v_geweigerd + 1;
  end;
  assert v_geweigerd = 2, 'een ongeldig mailadres hoort geweigerd te worden';

  -- Met mailadres: speler krijgt de status 'invited' en een uitnodiging.
  v_tp := public.floor_add_entry(v_t1, null, 'Jan Peeters', upper(v_mail));
  select player_id into v_p1 from tournament_players where id = v_tp;

  assert (select email from players where id = v_p1) = v_mail,
    'het mailadres hoort in kleine letters bewaard te worden';
  assert (select link_state from players where id = v_p1) = 'invited',
    'een speler met mailadres hoort op invited te staan';
  select count(*) into v_n from player_invites
  where player_id = v_p1 and sent_at is null;
  assert v_n = 1, format('verwacht 1 uitnodiging in de wachtrij, kreeg %s', v_n);

  -- Dezelfde man bij een andere club: hetzelfde profiel, geen tweede.
  v_tp2 := public.floor_add_entry(v_t2, null, 'Jan P.', v_mail);
  select player_id into v_p2 from tournament_players where id = v_tp2;
  assert v_p1 = v_p2, 'hetzelfde mailadres hoorde dezelfde speler op te leveren';
  assert (select display_name from players where id = v_p1) = 'Jan Peeters',
    'een bestaande naam mag niet overschreven worden door een tweede club';
  select count(*) into v_n from club_players where player_id = v_p1;
  assert v_n = 2, format('speler hoort bij 2 clubs te staan, kreeg %s', v_n);

  -- Zonder mailadres mág, maar dan met een reden.
  v_tp := public.floor_add_entry(v_t1, null, 'Geen Mail', null, 'kent het niet uit het hoofd');
  select player_id into v_p2 from tournament_players where id = v_tp;
  assert (select email from players where id = v_p2) is null, 'er hoort geen adres te staan';
  assert (select no_email_reason from players where id = v_p2) = 'kent het niet uit het hoofd',
    'de reden werd niet vastgelegd';
  assert (select link_state from players where id = v_p2) = 'shadow',
    'zonder mailadres hoort de speler een schaduwprofiel te zijn';
  assert (select count(*) from club_players_without_email where player_id = v_p2) >= 0,
    'de aanvullijst is niet bevraagbaar';

  -- Achteraf alsnog invullen.
  perform public.set_player_email(v_p2, 'later-' || v_mail, v_club1);
  assert (select email from players where id = v_p2) = 'later-' || v_mail,
    'het adres werd niet bijgewerkt';
  assert (select no_email_reason from players where id = v_p2) is null,
    'de reden hoort te verdwijnen zodra het adres er is';
  assert (select link_state from players where id = v_p2) = 'invited',
    'na het invullen hoort de speler uitgenodigd te zijn';

  -- Blijkt het adres van iemand anders te zijn, dan krijg je die terug in
  -- plaats van een unieke-index-fout in het gezicht.
  assert public.set_player_email(v_p2, v_mail, v_club1) = v_p1,
    'een bestaand adres hoort naar de bestaande speler te wijzen';

  raise notice 'mailadres OK: sleutel over clubs heen, uitweg met reden, aanvullen achteraf';
end $$;

rollback;
