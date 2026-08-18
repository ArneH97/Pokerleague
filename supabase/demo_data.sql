-- Pokerleague — demogegevens voor Cutoff Cardroom
--
-- Waarvoor dit dient: schermen en brochures met echte cijfers erin. Een lege
-- app verkoopt niets — een profiel met één sessie en een grafiek die zegt
-- "kom later terug" ook niet. Dit vult vijf maanden clubgeschiedenis: acht
-- speelavonden, dertien spelers, een klassement, en voor jouw eigen account
-- een verloop dat op een pokerjaar lijkt in plaats van op testdata.
--
-- ---------------------------------------------------------------------------
-- LEES DIT EERST
-- ---------------------------------------------------------------------------
--
--   * Dit zet **verzonnen** avonden in je echte club. Alles wat het aanmaakt
--     draagt het voorvoegsel `Demo ·` in de tornooinaam en `@demo.pokerleague.be`
--     in de spelersadressen, zodat het er in één beweging weer uit kan. Dat
--     opruimscript staat onderaan dit bestand, uitgecommentarieerd.
--   * Er vertrekt geen enkele mail. De demospelers krijgen bewust adressen op
--     een domein dat niet bestaat, en hun uitnodigingen worden meteen op
--     verzonden gezet zodat de wachtrij ze overslaat.
--   * Draai dit in de SQL-editor van Supabase. Daar draai je als beheerder,
--     en dan laten de floor-functies je door zonder dat je bij de club als
--     medewerker hoeft te staan.
--   * Twee keer draaien doet niets dubbel: het script stopt als de
--     demo-avonden er al staan.
--
-- Waarom via `floor_add_entry` / `floor_eliminate` / `floor_finish_tournament`
-- en niet rechtstreeks in de tabellen: dan rekent de app zelf de inleg, de
-- prijzenpot, de knock-outs en de punten uit. Met de hand geschreven rijen
-- zien er goed uit tot je ze naast een klassement legt en de sommen niet
-- kloppen. Achteraf zetten we alleen de datums terug in de tijd.

\set ON_ERROR_STOP on

do $$
declare
  -- --------------------------------------------------------------- instellen
  -- Jouw eigen account. Hier hoort het adres te staan waarmee jij op
  -- PokerLeague aanmeldt; jouw resultaten worden aan dat profiel gehangen.
  c_email  text := 'halsberghe.arne@hotmail.com';
  c_slug   text := 'cutoff';

  v_club   uuid;
  v_struct uuid;
  v_pay    uuid;
  v_me     uuid;
  v_t      uuid;
  v_tp     uuid;
  v_when   timestamptz;

  -- De vaste ploeg. Namen zijn verzonnen; de adressen wijzen naar een domein
  -- dat niet bestaat, zodat er nooit iets naartoe vertrekt.
  c_names  text[] := array[
    'Jens De Backer', 'Karel Van Hoof', 'Miet Blomme', 'Tom Segers',
    'Lieve Maes', 'Wout Peeters', 'Sofie Claes', 'Bram Willems',
    'Nele Janssens', 'Dries Coppens', 'Ilse Verhaeghe', 'Koen Baert'
  ];

  -- Per avond: hoeveel dagen geleden, hoeveel spelers, en op welke plaats jij
  -- eindigde. Bewust een echt verloop: een moeilijke start, een overwinning,
  -- en een paar avonden waarop je niets betaald kreeg. Een profiel waarin
  -- iemand altijd wint gelooft geen enkele pokerspeler.
  c_days   int[] := array[152, 138, 117,  96,  75,  54,  33,  12];
  c_field  int[] := array[  9,  11,  10,  13,  12,  11,  13,  12];
  c_place  int[] := array[  7,   3,   9,   1,   5,   2,   8,   1];
  c_names_of_night text[];

  -- De namen van de avonden. Ze houden allemaal het voorvoegsel `Demo ·`,
  -- want daar herkent het opruimscript ze aan, maar verder lezen ze als een
  -- echte clubkalender in plaats van als testdata.
  c_titles text[] := array[
    'Demo · Zondagavond #1', 'Demo · Woensdagavond #1', 'Demo · Zondagavond #2',
    'Demo · Deepstack',      'Demo · Woensdagavond #2', 'Demo · Zondagavond #3',
    'Demo · Bounty Night',   'Demo · Zondagavond #4'
  ];

  i int;
  j int;
  v_ids uuid[];
  v_pos int;
  v_by_pos uuid[];
begin
  select id into v_club from clubs where slug = c_slug;
  if v_club is null then
    raise exception 'Geen club met slug %. Pas c_slug hierboven aan.', c_slug;
  end if;

  if exists (select 1 from tournaments where club_id = v_club and name like 'Demo ·%') then
    raise notice 'De demo-avonden staan er al. Niets gedaan.';
    return;
  end if;

  -- ------------------------------------------------------------- jouw speler
  select p.id into v_me
  from players p
  where p.merged_into_id is null
    and (lower(p.email) = lower(c_email)
         or p.auth_user_id = (select u.id from auth.users u where lower(u.email) = lower(c_email)))
  order by (p.auth_user_id is not null) desc
  limit 1;

  if v_me is null then
    raise exception 'Geen speler gevonden voor %. Meld je eerst één keer aan op pokerleague.be/ik.', c_email;
  end if;

  -- Lid van de club, anders staat je clubkaart er straks niet bij.
  insert into club_players (club_id, player_id)
  values (v_club, v_me)
  on conflict do nothing;

  -- --------------------------------------------------- structuur en uitbetaling
  -- Bestaat er al een blindstructuur bij deze club, dan gebruiken we die; zo
  -- ziet de demo eruit zoals jullie echt spelen.
  select id into v_struct from blind_structures where club_id = v_club order by created_at limit 1;
  if v_struct is null then
    insert into blind_structures (club_id, name)
    values (v_club, 'Demo · standaard') returning id into v_struct;
    insert into blind_levels (structure_id, idx, is_break, small_blind, big_blind, ante, duration_s)
    values (v_struct, 0, false, 25, 50, 0, 1200),
           (v_struct, 1, false, 50, 100, 0, 1200),
           (v_struct, 2, false, 100, 200, 25, 1200);
  end if;

  select id into v_pay from payout_templates where club_id = v_club order by created_at limit 1;
  if v_pay is null then
    insert into payout_templates (club_id, name, tiers, rounding)
    values (v_club, 'Demo · 50/30/20',
            '[{"min_entries":2,"max_entries":99,"percentages":[50,30,20]}]'::jsonb, 100)
    returning id into v_pay;
  end if;

  -- ------------------------------------------------------------- de avonden
  for i in 1 .. array_length(c_days, 1) loop
    v_when := date_trunc('hour', now()) - (c_days[i] || ' days')::interval;
    v_when := date_trunc('day', v_when) + interval '20 hours';

    insert into tournaments (
      club_id, payout_template_id, structure_id, name, scheduled_at,
      status, player_visibility, buyin_cents, fee_cents, starting_stack, max_reentries
    ) values (
      v_club, v_pay, v_struct,
      c_titles[i],
      v_when,
      'running'::tournament_status, 'public'::visibility,
      2000, 500, 20000, 1
    ) returning id into v_t;

    -- Jij plus zoveel tegenstanders als het veld groot is.
    v_ids := array[]::uuid[];
    v_tp := public.floor_add_entry(v_t, v_me);
    v_ids := v_ids || v_tp;

    c_names_of_night := c_names[1 : c_field[i] - 1];
    for j in 1 .. array_length(c_names_of_night, 1) loop
      v_ids := v_ids || public.floor_add_entry(
        v_t, null, c_names_of_night[j],
        -- Een adres dat niet bestaat: lower(naam) zonder spaties.
        replace(lower(c_names_of_night[j]), ' ', '.') || '@demo.pokerleague.be'
      );
    end loop;

    -- Herinkopen. Eentje voor iemand anders zodat de pot niet elke avond
    -- hetzelfde getal is, en op de avonden waarop jij vroeg sneuvelde ook
    -- eentje voor jou — dan varieert je inleg, en dat is precies het getal
    -- waar je netto op steunt.
    if c_field[i] >= 12 then
      perform public.floor_rebuy(v_ids[3]);
    end if;
    if c_place[i] > c_field[i] / 2 then
      perform public.floor_rebuy(v_ids[1]);
    end if;

    -- Wie eindigt waar, vooraf vastgelegd.
    --
    -- Eerst een rij van plaats 1 tot en met de laatste: op jouw plaats sta
    -- jij, de rest schuift op. Daarna schakelen we van achteren naar voren
    -- uit, telkens door de speler die één plaats hoger eindigt. De laatste
    -- die overblijft wint.
    --
    -- Eerder liet ik hier een formule kiezen wie eruit ging, en dat ging mis:
    -- ze koos soms iemand die al uitgeschakeld was, er bleven twee spelers
    -- over, en de avond die jij zou winnen eindigde op een tweede plaats.
    v_by_pos := array_fill(null::uuid, array[c_field[i]]);
    j := 0;
    for v_pos in 1 .. c_field[i] loop
      if v_pos = c_place[i] then
        v_by_pos[v_pos] := v_ids[1];
      else
        -- De tegenstanders schuiven elke avond drie plaatsen op. Zonder die
        -- verschuiving eindigt dezelfde man acht keer op rij eerste en staat
        -- er een klassement dat niemand gelooft.
        v_by_pos[v_pos] := v_ids[2 + ((j + i * 3) % (c_field[i] - 1))];
        j := j + 1;
      end if;
    end loop;

    for v_pos in reverse c_field[i] .. 2 loop
      perform public.floor_eliminate(v_by_pos[v_pos], v_by_pos[v_pos - 1]);
    end loop;

    perform public.floor_finish_tournament(v_t);

    -- Terug in de tijd. De functies stempelen alles op nu; zonder deze regels
    -- staan acht avonden op dezelfde dag en is elke grafiek een streep.
    update tournaments
    set started_at = v_when, ended_at = v_when + interval '4 hours'
    where id = v_t;

    update tournament_results
    set finished_at = v_when + interval '4 hours'
    where tournament_id = v_t;

    update tournament_players
    set registered_at = v_when,
        eliminated_at = v_when + interval '3 hours'
    where tournament_id = v_t;

    update buyins set occurred_at = v_when where tournament_id = v_t;
  end loop;

  -- ------------------------------------------------------ en wat er nog komt
  -- Twee avonden in de toekomst. Zonder die twee staat er op de clubpagina
  -- "niets gepland" en in de agenda niets — een club die alleen verleden
  -- heeft ziet er verlaten uit, ook al draait ze.
  for i in 1 .. 2 loop
    insert into tournaments (
      club_id, payout_template_id, structure_id, name, scheduled_at,
      status, player_visibility, buyin_cents, fee_cents, starting_stack, max_reentries
    ) values (
      v_club, v_pay, v_struct,
      case i when 1 then 'Demo · Zondagavond #5' else 'Demo · Woensdagavond #3' end,
      date_trunc('day', now() + (case i when 1 then 4 else 11 end || ' days')::interval)
        + interval '20 hours',
      'scheduled'::tournament_status, 'public'::visibility,
      2000, 500, 20000, 1
    );
  end loop;

  -- ------------------------------------------------------ namen in de lijst
  -- Zonder toestemming toont het klassement een pseudoniem — "Speler 6fdb" —
  -- en dat is juist: een echte speler bepaalt zelf of zijn naam publiek is.
  -- Maar een klassement dat uit acht keer "Speler ####" bestaat, laat op een
  -- schermafbeelding niet zien wat het doet. Deze mensen bestaan niet, dus
  -- hier mag het.
  -- Twee vinkjes en niet één: `public_name` toont pas een echte naam als de
  -- speler zowel in ranglijsten mag verschijnen als een publiek profiel heeft.
  -- Met alleen het eerste blijft het pseudoniem staan — dat kostte me hier
  -- een ronde zoeken.
  update players
  set public_listing = true, public_profile = true
  where email like '%@demo.pokerleague.be';

  if not (select public_listing and public_profile from players where id = v_me) then
    raise notice 'Let op: jouw eigen naam staat op pseudoniem, je verschijnt in het klassement als "%".',
      (select coalesce(username, 'Speler ...') from players where id = v_me);
    raise notice 'Wil je je echte naam zien staan: zet het vinkje aan bij pokerleague.be/ik/gegevens.';
  end if;

  -- ---------------------------------------------------------- geen post, aub
  -- De demospelers hebben een adres op een domein dat niet bestaat. Zet hun
  -- uitnodigingen op verzonden, dan probeert de wachtrij het niet.
  update player_invites
  set sent_at = now(), last_error = 'demo — niet verzonden'
  where sent_at is null
    and player_id in (
      select id from players where email like '%@demo.pokerleague.be'
    );

  raise notice 'Klaar: % demo-avonden bij %.', array_length(c_days, 1), c_slug;
end $$;

-- Wat er nu staat, ter controle.
select t.name,
       (t.ended_at at time zone 'Europe/Brussels')::date as gespeeld,
       r.position as jouw_plaats,
       r.entries_total as veld,
       (r.prize_cents / 100.0) as gewonnen,
       (r.invested_cents / 100.0) as ingelegd,
       round(r.points) as punten
from tournament_results r
join tournaments t on t.id = r.tournament_id
join players p on p.id = r.player_id
where t.name like 'Demo ·%'
  and lower(p.email) = 'halsberghe.arne@hotmail.com'
order by t.scheduled_at;


-- ===========================================================================
-- OPRUIMEN — haal het commentaar weg en draai dit blok om alles te wissen
-- ===========================================================================
--
-- Verwijdert precies wat hierboven is aangemaakt en niets anders: de
-- demo-avonden (met hun deelnemers, inkopen en uitslagen, via de
-- cascade-regels) en daarna de demospelers die verder nergens meer in
-- voorkomen. Jouw eigen profiel en je echte resultaten blijven staan.
--
-- do $$
-- declare
--   v_club uuid;
-- begin
--   select id into v_club from clubs where slug = 'cutoff';
--
--   delete from tournaments
--   where club_id = v_club and name like 'Demo ·%';
--
--   delete from player_invites
--   where player_id in (select id from players where email like '%@demo.pokerleague.be');
--
--   delete from club_players
--   where player_id in (select id from players where email like '%@demo.pokerleague.be');
--
--   delete from players
--   where email like '%@demo.pokerleague.be'
--     and not exists (select 1 from tournament_results r where r.player_id = players.id)
--     and not exists (select 1 from tournament_players tp where tp.player_id = players.id);
--
--   delete from blind_structures where club_id = v_club and name like 'Demo ·%';
--   delete from payout_templates where club_id = v_club and name like 'Demo ·%';
--
--   raise notice 'Demogegevens verwijderd.';
-- end $$;
