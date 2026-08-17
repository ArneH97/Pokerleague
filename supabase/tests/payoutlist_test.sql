-- Pokerleague — de uitbetaallijst
--
-- Wat hier bewezen moet worden is niet ingewikkeld maar wel belangrijk: de
-- lijst die de floor aan de kassa gebruikt moet op elk moment kloppen, en na
-- een deal de afgesproken bedragen tonen en niet de ladder.
\set ON_ERROR_STOP on
begin;
do $$
declare
  v_club uuid; v_struct uuid; v_pay uuid; v_tour uuid;
  v_tp uuid[] := array[]::uuid[]; v_id uuid;
  i int; v_n int; v_cents int; v_naam text; v_paid timestamptz;
  v_shares jsonb;
begin
  insert into clubs (slug, name, city, country, locale, timezone)
  values ('t21', 'Testclub 21', 'Gent', 'BE', 'nl', 'Europe/Brussels') returning id into v_club;

  insert into blind_structures (club_id, name) values (v_club, 'S') returning id into v_struct;
  insert into blind_levels (structure_id, idx, is_break, small_blind, big_blind, ante, duration_s)
  values (v_struct, 0, false, 25, 50, 0, 1200);

  insert into payout_templates (club_id, name, tiers, rounding)
  values (v_club, 'P', '[{"min_entries":2,"max_entries":99,"percentages":[50,30,20]}]'::jsonb, 100)
  returning id into v_pay;

  insert into tournaments (club_id, payout_template_id, structure_id, name, scheduled_at,
                           status, buyin_cents, fee_cents, starting_stack, max_reentries,
                           clock, level_idx, started_at)
  values (v_club, v_pay, v_struct, 'Uitbetaling', now(), 'running'::tournament_status,
          2000, 0, 20000, 1, 'running'::clock_status, 0, now())
  returning id into v_tour;

  for i in 1 .. 10 loop
    v_tp := v_tp || public.floor_add_entry(v_tour, null, 'Speler ' || i, 's' || i || '@t21.be');
    update tournament_players set chip_count = 20000 where id = v_tp[i];
  end loop;

  -- Pot 200 euro. Vier betaalde plaatsen zodat de bubbel op 5 ligt.
  perform public.set_payouts(v_tour, array[10000, 6000, 3000, 1000]);

  -- ------------------------------------------------------------------ 1 ---
  -- Wie buiten het geld valt staat niet op de lijst.
  perform public.floor_eliminate(v_tp[1], v_tp[2]);   -- plaats 10
  select count(*) into v_n from public.tournament_payouts(v_tour);
  if v_n <> 0 then raise exception 'FOUT: plaats 10 hoort niets te krijgen (% rijen)', v_n; end if;
  raise notice 'OK  buiten het geld staat er niets op de lijst';

  -- ------------------------------------------------------------------ 2 ---
  -- Zodra iemand in het geld valt staat hij erop, met bedrag en naam.
  for i in 3 .. 7 loop
    perform public.floor_eliminate(v_tp[i], v_tp[2]);  -- plaatsen 9 t/m 5
  end loop;
  perform public.floor_eliminate(v_tp[8], v_tp[2]);    -- plaats 4: het geld in

  select count(*) into v_n from public.tournament_payouts(v_tour);
  if v_n <> 1 then raise exception 'FOUT: verwacht 1 uit te betalen speler, kreeg %', v_n; end if;

  select player_name, amount_cents, place into v_naam, v_cents, i
  from public.tournament_payouts(v_tour);
  if v_cents <> 1000 then raise exception 'FOUT: plaats 4 hoort 1000 cent te krijgen, kreeg %', v_cents; end if;
  raise notice 'OK  bij uitschakelen in het geld: % op plaats % krijgt % cent', v_naam, i, v_cents;

  -- ------------------------------------------------------------------ 3 ---
  -- Afstrepen aan de kassa, en het weer terugdraaien.
  select tournament_player_id into v_id from public.tournament_payouts(v_tour);
  perform public.floor_mark_paid(v_id, true);
  select paid_at into v_paid from public.tournament_payouts(v_tour);
  if v_paid is null then raise exception 'FOUT: afstrepen werkte niet'; end if;

  perform public.floor_mark_paid(v_id, false);
  select paid_at into v_paid from public.tournament_payouts(v_tour);
  if v_paid is not null then raise exception 'FOUT: afvinken kon niet terug'; end if;
  raise notice 'OK  afstrepen en terugdraaien';

  -- ------------------------------------------------------------------ 4 ---
  -- Na een deal staan de afgesproken bedragen op de lijst, niet de ladder.
  -- Drie over: v_tp[2], v_tp[9], v_tp[10]. Samen 100+60+30 = 190 euro; de
  -- tafel spreekt iets anders af binnen datzelfde bedrag.
  v_shares := jsonb_build_array(
    jsonb_build_object('tournament_player_id', v_tp[2],  'name','Speler 2', 'chips',60000,'agreed_cents',7000),
    jsonb_build_object('tournament_player_id', v_tp[9],  'name','Speler 9', 'chips',40000,'agreed_cents',6500),
    jsonb_build_object('tournament_player_id', v_tp[10], 'name','Speler 10','chips',20000,'agreed_cents',5500));
  perform public.deal_propose(v_tour, 'icm', v_shares);
  perform public.deal_accept(v_tour);

  select count(*) into v_n from public.tournament_payouts(v_tour);
  if v_n <> 4 then raise exception 'FOUT: verwacht 4 uitbetalingen na de deal, kreeg %', v_n; end if;

  -- Per naam, niet per plaats: de eindplaatsen van wie meedeelt liggen vast
  -- door de stapels, maar het afgesproken bedrag hoort bij de persoon.
  select amount_cents into v_cents from public.tournament_payouts(v_tour) where player_name = 'Speler 2';
  if v_cents <> 7000 then raise exception 'FOUT: Speler 2 hoort 7000 te krijgen, kreeg %', v_cents; end if;
  select amount_cents into v_cents from public.tournament_payouts(v_tour) where player_name = 'Speler 10';
  if v_cents <> 5500 then raise exception 'FOUT: Speler 10 hoort 5500 te krijgen, kreeg %', v_cents; end if;

  select amount_cents into v_cents from public.tournament_payouts(v_tour) where place = 4;
  if v_cents <> 1000 then raise exception 'FOUT: wie voor de deal afviel houdt zijn ladderbedrag, kreeg %', v_cents; end if;

  select sum(amount_cents) into v_cents from public.tournament_payouts(v_tour);
  if v_cents <> 20000 then raise exception 'FOUT: de lijst telt niet op tot de pot (%)', v_cents; end if;
  raise notice 'OK  na de deal: 4 namen, afgesproken bedragen, samen % cent', v_cents;

  -- ------------------------------------------------------------------ 5 ---
  -- En een buitenstaander mag deze lijst niet zien.
  begin
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform set_config('request.jwt.claim.sub', gen_random_uuid()::text, true);
    perform public.tournament_payouts(v_tour);
    perform set_config('request.jwt.claim.role', '', true);
    raise exception 'FOUT: de kassalijst was zichtbaar voor een buitenstaander';
  exception
    when insufficient_privilege then
      perform set_config('request.jwt.claim.role', '', true);
      perform set_config('request.jwt.claim.sub', '', true);
      raise notice 'OK  de kassalijst is afgeschermd';
  end;
end $$;
rollback;
