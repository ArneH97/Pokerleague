-- Droogloop van de tornooi-engine. Draait tegen een lege database met de
-- drie migraties erop. Elke sectie faalt hard als de uitkomst niet klopt.

-- Draait in een transactie die aan het eind terugrolt: veilig op een
-- database met echte data, en plakbaar in de SQL Editor van Supabase.
begin;

-- ---------------------------------------------------------------------------
-- 1. Payoutverdeling
-- ---------------------------------------------------------------------------

do $$
declare
  v_tiers jsonb := '[
    {"min_entries":2,"max_entries":8,"percentages":[70,30]},
    {"min_entries":9,"max_entries":17,"percentages":[50,30,20]},
    {"min_entries":18,"max_entries":999,"percentages":[40,25,15,10,10]}
  ]'::jsonb;
  v_sum int;
  v_cnt int;
  v_first int;
begin
  -- Som van de prijzen moet exact de pot zijn, ook met afronding op €5.
  select sum(amount_cents), count(*) into v_sum, v_cnt
  from public.calc_payouts(52500, 21, v_tiers, 500);
  assert v_sum = 52500, format('pot klopt niet: %s', v_sum);
  assert v_cnt = 5,     format('verwacht 5 betaalde plaatsen, kreeg %s', v_cnt);

  -- Nooit meer betaalde plaatsen dan deelnemers.
  select count(*) into v_cnt from public.calc_payouts(10000, 2, v_tiers, 500);
  assert v_cnt = 2, format('bij 2 deelnemers hoort 2 plaatsen, kreeg %s', v_cnt);

  -- Restant gaat naar plaats 1, dus plaats 1 is nooit kleiner dan plaats 2.
  select amount_cents into v_first from public.calc_payouts(33333, 12, v_tiers, 500) where place = 1;
  assert v_first >= (select amount_cents from public.calc_payouts(33333, 12, v_tiers, 500) where place = 2),
    'plaats 1 kleiner dan plaats 2';

  select sum(amount_cents) into v_sum from public.calc_payouts(33333, 12, v_tiers, 500);
  assert v_sum = 33333, format('oneven pot klopt niet: %s', v_sum);

  -- Lege pot geeft geen rijen.
  select count(*) into v_cnt from public.calc_payouts(0, 10, v_tiers, 500);
  assert v_cnt = 0, 'lege pot zou geen uitbetaling mogen geven';

  raise notice 'payouts OK';
end $$;

-- ---------------------------------------------------------------------------
-- 2. Puntenberekening
-- ---------------------------------------------------------------------------

do $$
declare
  p1 numeric; p2 numeric; p3 numeric;
begin
  -- sqrt_ratio: winnaar van een groter veld verdient meer.
  p1 := public.calc_points('sqrt_ratio', '{"multiplier":10}', 1, 36);
  p2 := public.calc_points('sqrt_ratio', '{"multiplier":10}', 1, 9);
  assert p1 = 60.00, format('sqrt_ratio 1/36 verwacht 60, kreeg %s', p1);
  assert p2 = 30.00, format('sqrt_ratio 1/9 verwacht 30, kreeg %s', p2);
  assert p1 > p2, 'groter veld moet meer punten geven';

  -- Monotoniciteit: lagere plaats geeft nooit meer punten.
  p3 := public.calc_points('sqrt_ratio', '{"multiplier":10}', 5, 36);
  assert p1 > p3, 'plaats 1 moet meer opleveren dan plaats 5';

  -- fixed_table met staart voor wie buiten de tabel valt.
  p1 := public.calc_points('fixed_table', '{"table":[100,80,65],"tail":5}', 2, 20);
  p2 := public.calc_points('fixed_table', '{"table":[100,80,65],"tail":5}', 19, 20);
  assert p1 = 80, format('fixed_table plaats 2 verwacht 80, kreeg %s', p1);
  assert p2 = 5,  format('fixed_table staart verwacht 5, kreeg %s', p2);

  -- linear met bodem.
  p1 := public.calc_points('linear', '{"base":100,"decrement":5,"floor":1}', 30, 30);
  assert p1 = 1, format('linear bodem verwacht 1, kreeg %s', p1);

  -- Bonus per knock-out telt erbij op. Halve punten uit een bonus verdwijnen
  -- in de afronding: 30 + 7,5 + 1 = 38,5 en dat wordt 39. Bewust — een
  -- klassement met komma's leest als een berekening en telt niet meer op.
  p1 := public.calc_points('sqrt_ratio', '{"multiplier":10}', 1, 9, 3, 2500, 2.5, 1);
  assert p1 = 39, format('bonussen kloppen niet: %s', p1);

  -- En elke uitkomst is een heel getal, ook als de formule dat niet is.
  p1 := public.calc_points('sqrt_ratio', '{"multiplier":10}', 3, 27);
  assert p1 = round(p1, 0), format('punten horen rond te zijn: %s', p1);

  raise notice 'punten OK';
end $$;

-- ---------------------------------------------------------------------------
-- 3. Volledig tornooi van inschrijving tot eindklassement
-- ---------------------------------------------------------------------------

do $$
declare
  v_club     uuid;
  v_season   uuid;
  v_rc       uuid;
  v_pt       uuid;
  v_tour     uuid;
  v_player   uuid;
  v_tp       uuid;
  v_ids      uuid[] := array[]::uuid[];
  v_tps      uuid[] := array[]::uuid[];
  i          int;
  n          int := 21;
  v_pot      int;
  v_paid     int;
  v_rows     int;
  v_winner   uuid;
begin
  insert into clubs (slug, name, city)
  values ('t-' || substr(gen_random_uuid()::text, 1, 12), 'Cutoff Poker Club', 'Gent')
  returning id into v_club;

  insert into ranking_configs (club_id, name, method, params, bonus_per_ko)
  values (v_club, 'Seizoensranking', 'sqrt_ratio', '{"multiplier":10}', 1)
  returning id into v_rc;

  insert into seasons (club_id, name, starts_on, ranking_config_id)
  values (v_club, 'Seizoen 2026-2027', date '2026-09-01', v_rc)
  returning id into v_season;

  insert into payout_templates (club_id, name, tiers, rounding)
  values (v_club, 'Standaard', '[
    {"min_entries":2,"max_entries":8,"percentages":[70,30]},
    {"min_entries":9,"max_entries":17,"percentages":[50,30,20]},
    {"min_entries":18,"max_entries":999,"percentages":[40,25,15,10,10]}
  ]'::jsonb, 500)
  returning id into v_pt;

  insert into tournaments (club_id, season_id, payout_template_id, name, scheduled_at,
                           buyin_cents, fee_cents, max_reentries, status)
  values (v_club, v_season, v_pt, 'Opening 6 september', timestamptz '2026-09-06 20:00+02',
          2000, 500, 1, 'running')
  returning id into v_tour;

  -- 21 spelers inschrijven en laten inkopen.
  for i in 1 .. n loop
    insert into players (display_name, email)
    values (format('Speler %s', i), format('speler%s.%s@test.invalid', i, substr(gen_random_uuid()::text, 1, 8)))
    returning id into v_player;
    v_ids := v_ids || v_player;

    insert into club_players (club_id, player_id, member_number)
    values (v_club, v_player, lpad(i::text, 3, '0'));

    insert into tournament_players (club_id, tournament_id, player_id, status)
    values (v_club, v_tour, v_player, 'active')
    returning id into v_tp;
    v_tps := v_tps || v_tp;

    insert into buyins (club_id, tournament_id, tournament_player_id, player_id,
                        kind, amount_cents, fee_cents)
    values (v_club, v_tour, v_tp, v_player, 'buyin', 2000, 500);
  end loop;

  -- Drie spelers nemen een re-entry.
  for i in 1 .. 3 loop
    insert into buyins (club_id, tournament_id, tournament_player_id, player_id,
                        kind, amount_cents, fee_cents)
    values (v_club, v_tour, v_tps[i], v_ids[i], 'reentry', 2000, 500);
  end loop;

  -- Tellers moeten automatisch bijgewerkt zijn door de trigger.
  select reentries_used into i from tournament_players where id = v_tps[1];
  assert i = 1, format('re-entryteller niet gesynchroniseerd: %s', i);

  -- Iedereen valt af, speler 1 wint. Elke uitschakeling op naam van de
  -- eerstvolgende overlevende, zodat er knock-outs te tellen zijn.
  for i in reverse n .. 2 loop
    update tournament_players
    set status = 'eliminated', finish_position = i, eliminated_at = now()
    where id = v_tps[i];

    insert into eliminations (club_id, tournament_id, tournament_player_id,
                              eliminated_by_id, position)
    values (v_club, v_tour, v_tps[i], v_tps[i - 1], i);
  end loop;

  update tournament_players set finish_position = 1, status = 'active' where id = v_tps[1];
  update tournaments set ended_at = now() where id = v_tour;

  v_rows := public.finalize_tournament(v_tour);
  assert v_rows = n, format('verwacht %s resultaatrijen, kreeg %s', n, v_rows);

  -- De pot is alleen amount_cents: 24 inkopen x €20.
  select coalesce(sum(amount_cents), 0) into v_pot
  from buyins where tournament_id = v_tour and not is_void;
  assert v_pot = 24 * 2000, format('pot verwacht %s, kreeg %s', 24 * 2000, v_pot);

  select coalesce(sum(prize_cents), 0) into v_paid
  from tournament_results where tournament_id = v_tour;
  assert v_paid = v_pot, format('uitbetaald %s <> pot %s', v_paid, v_pot);

  -- Fee blijft bij de club en zit niet in de prijzenpot.
  assert (select sum(fee_cents) from buyins where tournament_id = v_tour) = 24 * 500,
    'clubbijdrage klopt niet';

  -- Winnaar heeft punten en de meeste van iedereen.
  select player_id into v_winner
  from tournament_results where tournament_id = v_tour order by points desc limit 1;
  assert v_winner = v_ids[1], 'winnaar heeft niet de meeste punten';

  assert (select points from tournament_results
          where tournament_id = v_tour and position = 1) > 0, 'winnaar zonder punten';

  -- Alleen de eerste vijf krijgen prijzengeld.
  assert (select count(*) from tournament_results
          where tournament_id = v_tour and prize_cents > 0) = 5,
    'aantal betaalde plaatsen klopt niet';

  -- Idempotent: nog eens afsluiten geeft hetzelfde resultaat, geen dubbels.
  v_rows := public.finalize_tournament(v_tour);
  assert (select count(*) from tournament_results where tournament_id = v_tour) = n,
    'opnieuw afsluiten maakte dubbele rijen';

  -- Seizoensklassement.
  assert (select count(*) from public.season_standings(v_season)) = n,
    'klassement mist spelers';
  assert (select display_name from public.season_standings(v_season) limit 1) = 'Speler 1',
    'verkeerde leider in het klassement';

  raise notice 'tornooi OK: pot % cent, % spelers, % uitbetaald', v_pot, n, v_paid;
end $$;

-- ---------------------------------------------------------------------------
-- 4. Compliance: daglimiet en re-entrylimiet blokkeren
-- ---------------------------------------------------------------------------

do $$
declare
  v_club uuid; v_tour uuid; v_player uuid; v_tp uuid;
  v_failed boolean := false;
  v_spend int;
begin
  insert into clubs (slug, name, compliance)
  values ('t-' || substr(gen_random_uuid()::text, 1, 12), 'Strikte Club', jsonb_build_object(
    'profile','be_tolerance','max_buyin_cents',5000,'max_daily_cents',10000,
    'max_reentries',1,'allow_cash_games',false,'min_age',18,'enforce','block'))
  returning id into v_club;

  insert into tournaments (club_id, name, scheduled_at, buyin_cents, status)
  values (v_club, 'Limiettest', now(), 5000, 'running') returning id into v_tour;

  insert into players (display_name) values ('Grote Inzetter') returning id into v_player;
  insert into club_players (club_id, player_id) values (v_club, v_player);
  insert into tournament_players (club_id, tournament_id, player_id, status)
  values (v_club, v_tour, v_player, 'active') returning id into v_tp;

  -- €50 + €50 = €100, precies op de limiet: moet lukken.
  insert into buyins (club_id, tournament_id, tournament_player_id, player_id, kind, amount_cents)
  values (v_club, v_tour, v_tp, v_player, 'buyin', 5000);
  insert into buyins (club_id, tournament_id, tournament_player_id, player_id, kind, amount_cents)
  values (v_club, v_tour, v_tp, v_player, 'reentry', 5000);

  v_spend := public.player_daily_spend_cents(v_player, public.club_today(v_club));
  assert v_spend = 10000, format('dagtotaal verwacht 10000, kreeg %s', v_spend);

  -- De volgende euro moet geweigerd worden.
  begin
    insert into buyins (club_id, tournament_id, tournament_player_id, player_id, kind, amount_cents)
    values (v_club, v_tour, v_tp, v_player, 'rebuy', 100);
  exception when check_violation then
    v_failed := true;
  end;
  assert v_failed, 'daglimiet werd niet afgedwongen';

  raise notice 'compliance OK: daglimiet en re-entrylimiet worden geblokkeerd';
end $$;

-- Regressie: de dag hoort bij de tijdzone van de club, niet bij die van de
-- server. Een inkoop om 00:30 Brusselse tijd valt in UTC nog op de vorige
-- dag — wie dat verwart, telt de daglimiet tegen de verkeerde dag.

do $$
declare
  v_club uuid; v_tour uuid; v_player uuid; v_tp uuid;
  v_laat timestamptz := timestamptz '2026-09-07 00:30:00+02';  -- 22:30 UTC op de 6e
  v_brussel int; v_utc int;
begin
  insert into clubs (slug, name, timezone, compliance)
  values ('t-' || substr(gen_random_uuid()::text, 1, 12), 'Late Uurtjes', 'Europe/Brussels',
          jsonb_build_object('enforce','off'))
  returning id into v_club;

  insert into tournaments (club_id, name, scheduled_at, status)
  values (v_club, 'Nachtsessie', v_laat, 'running') returning id into v_tour;
  insert into players (display_name) values ('Nachtbraker') returning id into v_player;
  insert into club_players (club_id, player_id) values (v_club, v_player);
  insert into tournament_players (club_id, tournament_id, player_id, status)
  values (v_club, v_tour, v_player, 'active') returning id into v_tp;

  insert into buyins (club_id, tournament_id, tournament_player_id, player_id,
                      kind, amount_cents, occurred_at)
  values (v_club, v_tour, v_tp, v_player, 'buyin', 5000, v_laat);

  v_brussel := public.player_daily_spend_cents(v_player, date '2026-09-07', v_club);
  v_utc     := public.player_daily_spend_cents(v_player, date '2026-09-06', v_club);

  assert v_brussel = 5000,
    format('inkoop hoort op de Brusselse dag 7 sept, kreeg %s', v_brussel);
  assert v_utc = 0,
    format('inkoop mag niet op de UTC-dag 6 sept staan, kreeg %s', v_utc);

  raise notice 'tijdzone OK: dagen volgen de club, niet de server';
end $$;

-- ---------------------------------------------------------------------------
-- 5. Autorisatie op de SECURITY DEFINER-functies
-- ---------------------------------------------------------------------------
-- Deze functies omzeilen RLS. Een gewone gebruiker zonder clubrol mag ze
-- daarom niet kunnen aanroepen voor een club waar hij niets te zoeken heeft.

do $$
declare
  v_club uuid; v_tour uuid; v_season uuid; v_player uuid;
begin
  insert into clubs (slug, name) values ('t-' || substr(gen_random_uuid()::text, 1, 12), 'Vreemde Club') returning id into v_club;
  insert into seasons (club_id, name, starts_on)
  values (v_club, 'Seizoen', current_date) returning id into v_season;
  insert into tournaments (club_id, season_id, name, scheduled_at, status)
  values (v_club, v_season, 'Afgeschermd', now(), 'running') returning id into v_tour;
  insert into players (display_name) values ('Buitenstaander') returning id into v_player;

  create temporary table _ctx (club uuid, tour uuid, season uuid, player uuid) on commit drop;
  insert into _ctx values (v_club, v_tour, v_season, v_player);
end $$;

do $$
declare
  v_blocked int := 0;
  c record;
  v_day date;
begin
  select * into c from _ctx;
  v_day := public.club_today(c.club);

  -- Doe alsof dit een gewoon webverzoek is van een ingelogde gebruiker die
  -- niets met deze club te maken heeft. Dit is wat PostgREST per verzoek zet.
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', gen_random_uuid()::text, true);

  assert not public.is_service_context(),
    'is_service_context() hoort hier onwaar te zijn';

  begin
    perform public.finalize_tournament(c.tour);
  exception when insufficient_privilege then v_blocked := v_blocked + 1;
  end;

  begin
    perform public.player_daily_spend_cents(c.player, v_day);
  exception when insufficient_privilege then v_blocked := v_blocked + 1;
  end;

  begin
    perform public.player_daily_spend_cents(c.player, v_day, c.club);
  exception when insufficient_privilege then v_blocked := v_blocked + 1;
  end;

  begin
    perform * from public.season_standings(c.season);
  exception when insufficient_privilege then v_blocked := v_blocked + 1;
  end;

  assert v_blocked = 4,
    format('verwacht 4 geblokkeerde aanroepen, kreeg %s', v_blocked);

  -- Terug naar serverkant: geen JWT meer.
  perform set_config('request.jwt.claim.role', '', true);
  perform set_config('request.jwt.claim.sub', '', true);

  assert public.is_service_context(), 'zonder JWT hoort dit serverside te zijn';
  perform public.player_daily_spend_cents(c.player, v_day);
  perform * from public.season_standings(c.season);

  raise notice 'autorisatie OK: 4 van 4 aanroepen geweigerd voor een buitenstaander';
end $$;

-- De ongecontroleerde variant mag voor geen enkele webrol aanroepbaar zijn.
-- Dit is de echte grendel; de rolcontrole hierboven is de tweede laag.
do $$
declare
  r text;
begin
  foreach r in array array['anon', 'authenticated'] loop
    if exists (select 1 from pg_roles where rolname = r) then
      assert not has_function_privilege(
        r, 'public.daily_spend_unchecked(uuid, date, uuid)', 'execute'),
        format('%s mag daily_spend_unchecked niet kunnen aanroepen', r);
    end if;
  end loop;

  assert not has_function_privilege(
    'public', 'public.daily_spend_unchecked(uuid, date, uuid)', 'execute'),
    'PUBLIC mag daily_spend_unchecked niet kunnen aanroepen';

  raise notice 'grants OK: interne functie is afgeschermd';
end $$;

rollback;
