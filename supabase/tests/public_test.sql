-- Pokerleague — de publieke clubpagina's
--
-- Het risico van deze laag zit niet in wat ze toont maar in wat ze per
-- ongeluk meeneemt. Vandaar dat dit bestand vooral controleert wat een
-- buitenstaander níét te zien krijgt: het geldregister, de mailadressen, de
-- blindstructuren van de club, en tornooien die niet publiek staan.
--
-- Getest als échte bezoeker: rol anon, geen JWT. Niet als eigenaar van de
-- database, want dan is elke afscherming vanzelf in orde.
\set ON_ERROR_STOP on
begin;

-- ---------------------------------------------------------------------------
-- Opzet: één publieke avond en één besloten avond bij dezelfde club
-- ---------------------------------------------------------------------------

do $$
declare
  v_club uuid; v_struct uuid; v_pay uuid;
  v_open uuid; v_hidden uuid;
  v_tp uuid; i int;
begin
  insert into clubs (slug, name, city, country, locale, timezone, public_names)
  values ('t23', 'Testclub 23', 'Gent', 'BE', 'nl', 'Europe/Brussels', false)
  returning id into v_club;

  insert into blind_structures (club_id, name) values (v_club, 'S') returning id into v_struct;
  insert into blind_levels (structure_id, idx, is_break, small_blind, big_blind, ante, duration_s)
  values (v_struct, 0, false, 25, 50, 0, 1200),
         (v_struct, 1, true,  0,  0,   0, 600),
         (v_struct, 2, false, 50, 100, 0, 1200);

  insert into payout_templates (club_id, name, tiers, rounding)
  values (v_club, 'P', '[{"min_entries":2,"max_entries":99,"percentages":[60,40]}]'::jsonb, 100)
  returning id into v_pay;

  insert into tournaments (club_id, payout_template_id, structure_id, name, scheduled_at,
                           status, player_visibility, buyin_cents, fee_cents,
                           starting_stack, max_reentries, clock, level_idx,
                           level_started_at, started_at)
  values (v_club, v_pay, v_struct, 'Open avond', now(), 'running'::tournament_status,
          'public'::visibility, 2000, 500, 20000, 1, 'running'::clock_status, 0,
          now() - interval '5 minutes', now() - interval '1 hour')
  returning id into v_open;

  insert into tournaments (club_id, payout_template_id, structure_id, name, scheduled_at,
                           status, player_visibility, buyin_cents, fee_cents,
                           starting_stack, max_reentries)
  values (v_club, v_pay, v_struct, 'Besloten avond', now(), 'running'::tournament_status,
          'private'::visibility, 2000, 500, 20000, 1)
  returning id into v_hidden;

  for i in 1 .. 4 loop
    v_tp := public.floor_add_entry(v_open, null, 'Speler ' || i, 's' || i || '@t23.be');
    update tournament_players set chip_count = 20000 where id = v_tp;
  end loop;
  perform public.floor_add_entry(v_hidden, null, 'Geheim Persoon', 'geheim@t23.be');

  -- Eén afvaller, zodat de lijst beide toestanden bevat.
  select tp.id into v_tp from tournament_players tp
  where tp.tournament_id = v_open order by tp.registered_at limit 1;
  perform public.floor_eliminate(v_tp, null);
end $$;

-- ---------------------------------------------------------------------------
-- Vanaf hier zijn we een gewone bezoeker
-- ---------------------------------------------------------------------------

set local role anon;
select set_config('request.jwt.claim.role', 'anon', true);

do $$
declare
  v_open uuid; v_hidden uuid; v_n int; v_naam text; v_pot int;
begin
  select id into v_open   from tournaments where name = 'Open avond';
  select id into v_hidden from tournaments where name = 'Besloten avond';

  -- 1 ------------------------------------------------------------ de klok --
  select entries into v_n from public.club_public_clock(v_open);
  if v_n <> 4 then raise exception 'FOUT: verwacht 4 deelnemers, kreeg %', v_n; end if;

  select prize_pool_cents into v_pot from public.club_public_clock(v_open);
  if v_pot <> 8000 then raise exception 'FOUT: pot verwacht 8000, kreeg %', v_pot; end if;
  raise notice 'OK  de klok is publiek leesbaar: 4 deelnemers, pot % cent', v_pot;

  -- 2 ------------------------------------------------- de besloten avond --
  select count(*) into v_n from public.club_public_clock(v_hidden);
  if v_n <> 0 then raise exception 'FOUT: een besloten avond was zichtbaar'; end if;
  select count(*) into v_n from public.club_public_seats(v_hidden);
  if v_n <> 0 then raise exception 'FOUT: de deelnemers van een besloten avond waren zichtbaar'; end if;
  raise notice 'OK  een besloten avond blijft onzichtbaar';

  -- 3 --------------------------------------------------------- de blinds --
  select count(*) into v_n from public.club_public_levels(v_open);
  if v_n <> 3 then raise exception 'FOUT: verwacht 3 levels, kreeg %', v_n; end if;
  -- Maar de structuur zelf blijft dicht: dit gaat over één avond, niet over
  -- het draaiboek van de club.
  select count(*) into v_n from blind_levels;
  if v_n <> 0 then raise exception 'FOUT: blind_levels was rechtstreeks leesbaar (% rijen)', v_n; end if;
  raise notice 'OK  de blinds van de avond zijn zichtbaar, de structuren van de club niet';

  -- 4 ------------------------------------------------------ de namenregel --
  select player_name into v_naam from public.club_public_seats(v_open) limit 1;
  if v_naam like 'Speler %' and v_naam not like 'Speler 1%' and v_naam not like 'Speler 2%'
     and v_naam not like 'Speler 3%' and v_naam not like 'Speler 4%' then
    raise notice 'OK  zonder toestemming toont de lijst een pseudoniem (%)', v_naam;
  else
    raise exception 'FOUT: er stond een echte naam op de publieke lijst: %', v_naam;
  end if;

  -- 5 ------------------------------------------------------ het geldboek --
  select count(*) into v_n from buyins;
  if v_n <> 0 then raise exception 'FOUT: het geldregister was leesbaar (% rijen)', v_n; end if;
  select count(*) into v_n from players;
  if v_n <> 0 then raise exception 'FOUT: de spelerstabel was leesbaar (% rijen)', v_n; end if;
  raise notice 'OK  geldregister en spelerstabel blijven dicht';

  -- 6 ------------------------------------------------ de kassalijst niet --
  begin
    perform public.tournament_payouts(v_open);
    raise exception 'FOUT: de uitbetaallijst was zichtbaar voor een bezoeker';
  exception
    when insufficient_privilege then
      raise notice 'OK  de uitbetaallijst blijft voor de floor';
  end;
end $$;

reset role;

-- ---------------------------------------------------------------------------
-- En met namen aan
-- ---------------------------------------------------------------------------

update clubs set public_names = true where slug = 't23';

set local role anon;
select set_config('request.jwt.claim.role', 'anon', true);

do $$
declare
  v_open uuid; v_naam text;
begin
  select id into v_open from tournaments where name = 'Open avond';
  select player_name into v_naam from public.club_public_seats(v_open) limit 1;
  if v_naam not like 'Speler %' or v_naam !~ '^Speler [1-4]$' then
    raise exception 'FOUT: met public_names aan hoort de echte naam er te staan, kreeg %', v_naam;
  end if;
  raise notice 'OK  met public_names aan toont de club de naam (%)', v_naam;
end $$;

reset role;
rollback;
