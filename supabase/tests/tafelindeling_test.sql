-- Tests voor de tafelindeling: indelen, met de hand verzetten, balanceren en
-- een tafel breken.
--
-- De rode draad: de databank rekent voor, de floor beslist. Elk voorstel moet
-- te overschrijven zijn, en na elke handeling hoort er nog altijd hoogstens
-- één speler per stoel te zitten.

begin;

do $$
declare
  v_club uuid; v_tour uuid; v_tps uuid[] := array[]::uuid[]; i int;
  v_n int; v_plan record; v_voorstel jsonb;
  v_dubbel int; v_ander uuid; v_stoel int;
begin
  insert into clubs (slug, name, compliance)
  values ('ti-' || substr(gen_random_uuid()::text, 1, 12), 'Tafelindeling',
          jsonb_build_object('enforce','off'))
  returning id into v_club;

  -- 6-max, zodat er met acht spelers meteen twee tafels nodig zijn.
  insert into tournaments (club_id, name, scheduled_at, status,
                           buyin_cents, fee_cents, starting_stack, seats_per_table)
  values (v_club, 'Indeling', now(), 'running', 4000, 0, 40000, 6)
  returning id into v_tour;

  for i in 1 .. 8 loop
    v_tps := v_tps || public.floor_add_entry(
      v_tour, null, format('Speler %s', i),
      format('ti%s-%s@test.be', i, substr(gen_random_uuid()::text, 1, 8)));
  end loop;

  -- ------------------------------------------------------------- indelen
  v_n := public.floor_autoseat(v_tour);
  assert v_n = 8, format('acht spelers hoorden een stoel te krijgen, kreeg %s', v_n);

  assert (select count(*) from tournament_players
           where tournament_id = v_tour and table_no = 1) = 6,
    'tafel 1 hoort eerst vol te lopen';
  assert (select count(*) from tournament_players
           where tournament_id = v_tour and table_no = 2) = 2,
    'de overige twee horen aan tafel 2 te zitten';
  assert (select count(*) from tournament_tables
           where tournament_id = v_tour and is_open) = 2,
    'er horen twee tafels open te staan';
  raise notice 'OK  tafels lopen één voor één vol en er gaat pas een tweede open als het moet';

  -- Nog eens indelen verandert niets: wie zit, blijft zitten.
  assert public.floor_autoseat(v_tour) = 0, 'opnieuw indelen zette mensen opnieuw';
  raise notice 'OK  opnieuw indelen laat wie al zit met rust';

  -- -------------------------------------------------- met de hand verzetten
  -- Speler 1 naar een vrije stoel aan tafel 2.
  perform public.floor_seat_player(v_tps[1], 2, 5);
  assert (select table_no from tournament_players where id = v_tps[1]) = 2
     and (select seat_no  from tournament_players where id = v_tps[1]) = 5,
    'de handmatige verplaatsing kwam niet aan';
  raise notice 'OK  de floor kan iedereen op elke vrije stoel zetten';

  -- En naar een bezette stoel: dan wisselen de twee.
  --
  -- Wie daar zit, zoeken we op in plaats van te veronderstellen: binnen één
  -- transactie staat `now()` stil, dus alle inschrijvingen dragen hetzelfde
  -- tijdstip en ligt de volgorde van het indelen niet vast. In een echte zaal
  -- komt iedereen op zijn eigen moment binnen.
  select id, seat_no into v_ander, v_stoel from tournament_players
   where tournament_id = v_tour and table_no = 1
     and status in ('active','registered')
   order by seat_no limit 1;
  assert v_ander is not null, 'er zit niemand aan tafel 1 om mee te wisselen';

  perform public.floor_seat_player(v_tps[1], 1, v_stoel);
  assert (select table_no from tournament_players where id = v_tps[1]) = 1
     and (select seat_no  from tournament_players where id = v_tps[1]) = v_stoel,
    'de wissel bracht speler 1 niet op de juiste stoel';
  assert (select table_no from tournament_players where id = v_ander) = 2
     and (select seat_no  from tournament_players where id = v_ander) = 5,
    'de speler die er zat, kwam niet op de vrijgekomen stoel terecht';
  raise notice 'OK  naar een bezette stoel wisselen de twee spelers om';

  -- Onmogelijke stoelen gaan niet door.
  begin
    perform public.floor_seat_player(v_tps[1], 1, 9);
    raise exception 'stoel 9 aan een tafel van zes werd aanvaard';
  exception when check_violation then
    raise notice 'OK  een stoel die niet bestaat wordt geweigerd';
  end;

  -- ------------------------------------------------------------ balanceren
  -- Zelf een scheve verdeling neerzetten in plaats van er eentje te erven.
  -- Binnen één transactie staat `now()` stil, dus de volgorde waarin
  -- `floor_autoseat` indeelt ligt niet vast; wat hieronder getest wordt, moet
  -- van run tot run hetzelfde zijn.
  for i in 1 .. 8 loop
    perform public.floor_unseat_player(v_tps[i]);
  end loop;
  for i in 1 .. 6 loop
    perform public.floor_seat_player(v_tps[i], 1, i);
  end loop;
  perform public.floor_seat_player(v_tps[7], 2, 1);
  perform public.floor_seat_player(v_tps[8], 2, 2);

  assert (select count(*) from tournament_players
           where tournament_id = v_tour and table_no = 1
             and status in ('active','registered')) = 6,
    'de scheve verdeling stond niet zoals bedoeld';
  v_n := 6;

  v_voorstel := public.seating_proposal(v_tour);
  assert v_voorstel ->> 'kind' = 'balance',
    format('een voorstel om te balanceren verwacht, kreeg %s', v_voorstel ->> 'kind');
  assert jsonb_array_length(v_voorstel -> 'moves') > 0, 'het voorstel is leeg';
  raise notice 'OK  een scheve verdeling geeft een voorstel om te verschuiven';

  -- Het voorstel verandert op zichzelf niets.
  assert (select count(*) from tournament_players
           where tournament_id = v_tour and table_no = 1
             and status in ('active','registered')) = v_n,
    'het voorstel heeft zelf spelers verplaatst';
  raise notice 'OK  een voorstel verzet niemand tot de floor het bevestigt';

  -- Uitvoeren, en dan hoort het verschil hoogstens één te zijn.
  perform public.floor_apply_moves(v_tour, v_voorstel -> 'moves');
  assert (select max(n) - min(n) from (
            select count(*) as n from tournament_players
            where tournament_id = v_tour and status in ('active','registered')
              and table_no is not null
            group by table_no) q) <= 1,
    'na het balanceren staan de tafels nog altijd scheef';
  raise notice 'OK  na het uitvoeren verschillen de tafels hoogstens één speler';

  -- Niemand deelt een stoel.
  select count(*) into v_dubbel from (
    select table_no, seat_no from tournament_players
    where tournament_id = v_tour and status in ('active','registered')
      and table_no is not null
    group by table_no, seat_no having count(*) > 1) q;
  assert v_dubbel = 0, 'er zitten twee spelers op dezelfde stoel';
  raise notice 'OK  er zit nooit meer dan één speler op een stoel';

  -- ---------------------------------------------------------------- breken
  -- Drie spelers eruit: dan passen de vijf overblijvers op één tafel van zes.
  perform public.floor_eliminate(v_tps[8], null);
  perform public.floor_eliminate(v_tps[7], null);
  perform public.floor_eliminate(v_tps[6], null);

  assert (select table_no from tournament_players where id = v_tps[8]) is null,
    'wie afvalt hoort zijn stoel los te laten';
  raise notice 'OK  een uitgeschakelde speler laat zijn stoel vrij';

  v_voorstel := public.seating_proposal(v_tour);
  assert v_voorstel ->> 'kind' = 'break',
    format('een voorstel om een tafel te breken verwacht, kreeg %s', v_voorstel ->> 'kind');
  perform public.floor_apply_moves(v_tour, v_voorstel -> 'moves');

  assert (select count(distinct table_no) from tournament_players
           where tournament_id = v_tour and status in ('active','registered')) = 1,
    'na het breken zit iedereen niet aan één tafel';
  raise notice 'OK  past iedereen op één tafel minder, dan stelt hij voor te breken';

  -- De lege tafel kan dicht; een tafel met volk niet.
  perform public.floor_close_table(v_tour, 2);
  assert (select is_open from tournament_tables
           where tournament_id = v_tour and table_no = 2) = false,
    'de lege tafel ging niet dicht';

  begin
    perform public.floor_close_table(v_tour, 1);
    raise exception 'een tafel met spelers ging dicht';
  exception when check_violation then
    raise notice 'OK  een tafel met spelers gaat niet dicht';
  end;

  -- En daarna is er niets meer voor te stellen.
  assert public.seating_proposal(v_tour) ->> 'kind' = 'none',
    'er wordt nog iets voorgesteld terwijl alles klopt';
  raise notice 'OK  staat alles goed, dan is er geen voorstel';

  -- ------------------------------------------- wat de speler op zijn gsm ziet
  -- Het plan is niet alleen voor de floor: wie aan tafel zit hoort te weten
  -- waar hij zit, ook meteen na een verplaatsing.
  select table_no, seat_no into v_n, v_stoel
  from tournament_players where id = v_tps[1];
  assert v_n is not null and v_stoel is not null,
    'de speler zit nergens terwijl hij nog in het tornooi zit';
  raise notice 'OK  een speler die nog speelt heeft altijd een tafel en een stoel';
end $$;

-- ---------------------------------------------------------------------------
-- Rechten
-- ---------------------------------------------------------------------------

do $$
declare
  v_club uuid; v_tour uuid; v_tp uuid; v_user uuid := gen_random_uuid();
begin
  insert into clubs (slug, name, compliance)
  values ('ti-' || substr(gen_random_uuid()::text, 1, 12), 'Rechten',
          jsonb_build_object('enforce','off'))
  returning id into v_club;
  insert into tournaments (club_id, name, scheduled_at, status,
                           buyin_cents, fee_cents, starting_stack)
  values (v_club, 'R', now(), 'running', 4000, 0, 40000)
  returning id into v_tour;
  v_tp := public.floor_add_entry(v_tour, null, 'Iemand',
    format('tir-%s@test.be', substr(gen_random_uuid()::text, 1, 8)));
  perform public.floor_autoseat(v_tour);

  insert into auth.users (id, email) values (v_user, 'vreemde-ti@test.be');
  perform set_config('request.jwt.claim.sub', v_user::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  begin
    perform public.floor_seat_player(v_tp, 1, 3);
    raise exception 'een vreemde kon iemand verzetten';
  exception when insufficient_privilege then
    raise notice 'OK  zonder rol bij de club kan je niemand verzetten';
  end;

  begin
    perform public.floor_autoseat(v_tour);
    raise exception 'een vreemde kon de tafels indelen';
  exception when insufficient_privilege then
    raise notice 'OK  zonder rol bij de club kan je niet indelen';
  end;

  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);
end $$;

rollback;
