\set ON_ERROR_STOP on
begin;
do $$
declare
  v_club uuid; v_struct uuid; v_tour uuid; v_pay uuid;
  v_a uuid; v_b uuid; v_c uuid;
  v_clock text; v_started timestamptz; v_el bigint; v_status text;
  v_shares jsonb;
begin
  insert into clubs (slug, name, city, country, locale, timezone)
  values ('t20', 'Testclub 20', 'Gent', 'BE', 'nl', 'Europe/Brussels') returning id into v_club;

  insert into blind_structures (club_id, name) values (v_club, 'S') returning id into v_struct;
  insert into blind_levels (structure_id, idx, is_break, small_blind, big_blind, ante, duration_s)
  values (v_struct, 0, false, 25, 50, 0, 1200), (v_struct, 1, false, 50, 100, 0, 1200);

  insert into payout_templates (club_id, name, tiers, rounding)
  values (v_club, 'P', '[{"min_entries":2,"max_entries":99,"percentages":[50,30,20]}]'::jsonb, 100)
  returning id into v_pay;

  insert into tournaments (club_id, payout_template_id, structure_id, name, scheduled_at,
                           status, buyin_cents, fee_cents, starting_stack, max_reentries,
                           clock, level_idx, level_started_at, level_elapsed_ms, started_at)
  values (v_club, v_pay, v_struct, 'Deal test', now(), 'running'::tournament_status,
          2000, 0, 20000, 1, 'running'::clock_status, 1, now() - interval '4 minutes', 60000,
          now() - interval '1 hour')
  returning id into v_tour;

  v_a := public.floor_add_entry(v_tour, null, 'Speler A', 'a@t20.be');
  v_b := public.floor_add_entry(v_tour, null, 'Speler B', 'b@t20.be');
  v_c := public.floor_add_entry(v_tour, null, 'Speler C', 'c@t20.be');
  update tournament_players set chip_count = 30000 where id = v_a;
  update tournament_players set chip_count = 20000 where id = v_b;
  update tournament_players set chip_count = 10000 where id = v_c;

  v_shares := jsonb_build_array(
    jsonb_build_object('tournament_player_id', v_a, 'name','Speler A','chips',30000,'agreed_cents',2500),
    jsonb_build_object('tournament_player_id', v_b, 'name','Speler B','chips',20000,'agreed_cents',2000),
    jsonb_build_object('tournament_player_id', v_c, 'name','Speler C','chips',10000,'agreed_cents',1500));

  perform public.deal_propose(v_tour, 'icm', v_shares);
  perform public.deal_accept(v_tour);

  select clock::text, level_started_at, level_elapsed_ms, status::text
    into v_clock, v_started, v_el, v_status
  from tournaments where id = v_tour;

  if v_status <> 'finished' then raise exception 'FOUT: status is %', v_status; end if;
  if v_clock <> 'stopped' then raise exception 'FOUT: klok loopt nog (%)', v_clock; end if;
  if v_started is not null then raise exception 'FOUT: startmoment staat nog ingevuld'; end if;
  if v_el < 290000 or v_el > 310000 then
    raise exception 'FOUT: opgebouwde tijd niet bijgeboekt (% ms, verwacht ~300000)', v_el;
  end if;
  raise notice 'OK  deal_accept: status=% klok=% opgebouwd=%ms', v_status, v_clock, v_el;

  -- En de uitslag heeft de afgesproken bedragen, niet de ladder.
  if (select prize_cents from tournament_results tr join tournament_players tp
      on tp.player_id = tr.player_id and tp.id = v_a
      where tr.tournament_id = v_tour) <> 2500 then
    raise exception 'FOUT: afgesproken bedrag niet overgenomen';
  end if;
  raise notice 'OK  afgesproken bedragen staan in de uitslag';

  -- De klok mag ook niet opnieuw aangezet kunnen worden op een dicht tornooi.
  update tournaments set clock = 'running', level_started_at = now() where id = v_tour;
  select clock::text into v_clock from tournaments where id = v_tour;
  if v_clock <> 'stopped' then raise exception 'FOUT: klok kon opnieuw starten (%)', v_clock; end if;
  raise notice 'OK  klok blijft stil op een afgesloten tornooi';
end $$;
rollback;
