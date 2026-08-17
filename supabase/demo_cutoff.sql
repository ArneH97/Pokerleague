-- Pokerleague — demodata voor Cutoff Cardroom
--
-- Vult de database met een geloofwaardig half jaar: 28 verzonnen spelers,
-- 14 afgesloten tornooiavonden verspreid over zes maanden, met inkopen,
-- rebuys, uitschakelingen, prijzengeld en punten. Genoeg om het klassement,
-- de cijfers en de grafieken te laten zien zonder dat je een avond moet
-- spelen.
--
-- ALLES IS GEMARKEERD. Elke verzonnen speler heeft een mailadres op
-- @demo.pokerleague.be en elk tornooi begint met "Demo ". Draai
-- demo_cutoff_wissen.sql en er blijft niets van over.
--
-- Draai dit pas nadat setup.sql en seed_cutoff.sql erdoor zijn.
-- Je mag het meerdere keren draaien: het ruimt zichzelf eerst op.

do $$
declare
  v_club    uuid;
  v_season  uuid;
  v_payout  uuid;
  v_struct  uuid;
  v_tour    uuid;
  v_tp      uuid;
  v_player  uuid;

  -- Namen die in een Vlaamse pokerclub niet uit de toon vallen.
  v_namen text[] := array[
    'Jan Peeters','Bart Verhoeven','Kevin De Smet','Nico Maes','Tom Willems',
    'Dries Janssens','Wouter Claes','Stijn Goossens','Koen Wouters','Filip Aerts',
    'Steven Mertens','Gert Van Dam','Pieter Declercq','Sam Verstraete','Jonas Lemmens',
    'Michel Dubois','Olivier Lambert','Thierry Renard','Sébastien Moreau','Laurent Piret',
    'Nathalie Vermeulen','Sofie De Backer','Els Vandenberghe','Kim Segers',
    'Leen Coppens','Ann Van Hoof','Ruben Smets','Yves Delcourt'
  ];
  v_naam    text;
  v_mail    text;
  v_spelers uuid[] := array[]::uuid[];

  i         int;
  d         int;
  v_veld    int;
  v_aantal  int;
  v_datum   timestamptz;
  v_start   timestamptz;
  v_seed    int;
  v_tornooien text[] := array[
    'Demo Vrijdagavond','Demo Deepstack','Demo Bounty Night','Demo Turbo',
    'Demo Clubkampioenschap','Demo Freezeout'
  ];
begin
  select id into v_club from clubs where slug = 'cutoff';
  if v_club is null then
    raise exception 'Club cutoff bestaat niet. Draai eerst seed_cutoff.sql.';
  end if;

  -- ------------------------------------------------------------- opruimen ---
  -- Eerst weg wat er van een vorige keer nog staat, zodat je dit bestand
  -- gerust twee keer kan draaien.
  delete from tournaments t
  where t.club_id = v_club and t.name like 'Demo %';

  delete from players p
  where p.email like '%@demo.pokerleague.be';

  -- --------------------------------------------------------------- basis ---
  select id into v_season from seasons
  where club_id = v_club and is_active order by starts_on desc limit 1;
  select id into v_payout from payout_templates
  where club_id = v_club or club_id is null order by club_id nulls last limit 1;
  select id into v_struct from blind_structures
  where club_id = v_club or club_id is null order by club_id nulls last limit 1;

  if v_season is null then
    raise exception 'Geen seizoen gevonden voor cutoff. Draai eerst seed_cutoff.sql.';
  end if;

  -- ------------------------------------------------------------- spelers ---
  for i in 1 .. array_length(v_namen, 1) loop
    v_naam := v_namen[i];
    v_mail := lower(
      regexp_replace(translate(v_naam, ' éèêëïîôûüàçÉÈÊËÏÎÔÛÜÀÇ', '.eeeeiiouuacEEEEIIOUUAC'),
                     '[^a-zA-Z.]', '', 'g')
    ) || '@demo.pokerleague.be';

    insert into players (display_name, email, link_state, public_listing, listing_consent_source)
    values (v_naam, v_mail, 'invited', i % 3 <> 0, case when i % 3 <> 0 then 'import' end)
    returning id into v_player;

    insert into club_players (club_id, player_id, joined_on)
    values (v_club, v_player, current_date - (200 - i * 5))
    on conflict (club_id, player_id) do nothing;

    v_spelers := v_spelers || v_player;
  end loop;

  -- ------------------------------------------------------------ tornooien ---
  -- Veertien avonden, om de twee weken teruggerekend vanaf vorige week. Het
  -- veld groeit langzaam: een jonge club die aanslaat, en dat is precies wat
  -- je op een grafiek wil kunnen tonen.
  for d in 0 .. 13 loop
    v_datum := (current_date - ((13 - d) * 14) - 1)::timestamptz + interval '20 hours';
    v_start := v_datum + interval '10 minutes';
    v_seed  := d;

    -- Tussen 8 en 22 spelers, oplopend met wat ruis erin.
    v_veld := 8 + d + (d * 7) % 5;
    if v_veld > array_length(v_spelers, 1) then
      v_veld := array_length(v_spelers, 1);
    end if;

    insert into tournaments (
      club_id, season_id, payout_template_id, structure_id, name, scheduled_at,
      status, player_visibility,
      buyin_cents, fee_cents, rebuy_cents, rebuy_fee_cents,
      bounty_mode, bounty_cents,
      starting_stack, max_reentries, late_reg_level,
      started_at
    ) values (
      v_club, v_season, v_payout, v_struct,
      v_tornooien[1 + (d % array_length(v_tornooien, 1))],
      v_datum,
      'running'::tournament_status, 'public'::visibility,
      2000, 500, 2000, 500,
      (case when d % 4 = 2 then 'fixed' else 'none' end)::bounty_mode,
      case when d % 4 = 2 then 500 else 0 end,
      20000, 1, 6,
      v_start
    )
    returning id into v_tour;

    -- Inschrijven. Wie meedoet rouleert per avond, zodat niet telkens
    -- dezelfde koppen bovenaan het klassement staan.
    for i in 1 .. v_veld loop
      v_player := v_spelers[1 + ((i * 3 + d * 5) % array_length(v_spelers, 1))];

      -- Kan al ingeschreven zijn door de rotatie; floor_add_entry vangt dat
      -- zelf op en boekt dan niets dubbel.
      v_tp := public.floor_add_entry(v_tour, v_player);

      -- Ongeveer een op de vijf koopt opnieuw in.
      if (i * 7 + d) % 5 = 0 then
        perform public.floor_rebuy(v_tp, 'rebuy');
      end if;
    end loop;

    -- Iedereen op een verschillende stapel zetten, zodat de eindstand niet
    -- elke avond dezelfde volgorde heeft.
    update tournament_players tp
    set chip_count = 5000 + ((extract(epoch from tp.registered_at)::bigint * 7 + d * 13) % 60) * 1000
    where tp.tournament_id = v_tour;

    -- Uitspelen: telkens de kortste stapel eruit, tot er één overblijft. De
    -- server bepaalt de eindplaatsen, net als op een echte avond.
    loop
      select tp.id into v_tp
      from tournament_players tp
      where tp.tournament_id = v_tour and tp.status in ('active', 'registered')
      order by tp.chip_count asc, tp.registered_at asc
      limit 1;

      exit when v_tp is null;
      exit when (select count(*) from tournament_players
                 where tournament_id = v_tour and status in ('active','registered')) <= 1;

      perform public.floor_eliminate(
        v_tp,
        (select tp2.id from tournament_players tp2
         where tp2.tournament_id = v_tour and tp2.status in ('active','registered')
           and tp2.id <> v_tp
         order by tp2.chip_count desc limit 1)
      );
    end loop;

    perform public.floor_finish_tournament(v_tour);

    -- De avond eindigt ergens tussen drie en vijf uur na de start.
    update tournaments
    set ended_at = v_start + make_interval(mins => 180 + (d * 17) % 120)
    where id = v_tour;
  end loop;

  raise notice 'Demodata klaar: % spelers, 14 afgesloten avonden.', array_length(v_spelers, 1);
end $$;

-- Controle: zo ziet het eruit.
select
  (select count(*) from players where email like '%@demo.pokerleague.be')            as demospelers,
  (select count(*) from tournaments t join clubs c on c.id = t.club_id
    where c.slug = 'cutoff' and t.name like 'Demo %')                                as demotornooien,
  (select count(*) from tournament_results r join tournaments t on t.id = r.tournament_id
    where t.name like 'Demo %')                                                      as uitslagen;
