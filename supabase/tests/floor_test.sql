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
    v_tp := public.floor_add_entry(v_tour, null, format('Speler %s', i));
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
  v_tp := public.floor_add_entry(v_tour, null, 'Iemand');

  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', gen_random_uuid()::text, true);

  begin perform public.floor_add_entry(v_tour, null, 'Indringer');
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

rollback;
