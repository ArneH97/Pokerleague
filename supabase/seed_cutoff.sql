-- Pokerleague — startgegevens voor Cutoff Poker Club
--
-- VOORAF: maak in Supabase onder Authentication > Users een gebruiker aan
-- met e-mailadres en wachtwoord, en vul dat adres hieronder in. Zonder dat
-- koppelt dit script niemand aan de club en zie je na het aanmelden niets.
--
-- Dit script mag je meerdere keren draaien; het werkt bestaande gegevens bij
-- in plaats van te verdubbelen.

do $$
declare
  -- >>> PAS DIT AAN <<<
  v_email      text := 'arne@halcoservices.be';

  v_club       uuid;
  v_user       uuid;
  v_struct     uuid;
  v_payout     uuid;
  v_ranking    uuid;
  v_season     uuid;
  v_tour       uuid;
  v_idx        int := 0;

  -- small blind, big blind, ante, minuten, pauze?, label
  v_levels     jsonb := '[
    [25,    50,     0,    20, false, null],
    [50,    100,    0,    20, false, null],
    [75,    150,    0,    20, false, null],
    [100,   200,    0,    20, false, null],
    [0,     0,      0,    10, true,  "Pauze"],
    [150,   300,    300,  20, false, null],
    [200,   400,    400,  20, false, null],
    [300,   600,    600,  20, false, null],
    [400,   800,    800,  20, false, null],
    [0,     0,      0,    10, true,  "Pauze"],
    [500,   1000,   1000, 20, false, null],
    [700,   1400,   1400, 20, false, null],
    [1000,  2000,   2000, 20, false, null],
    [1500,  3000,   3000, 20, false, null],
    [0,     0,      0,    10, true,  "Pauze"],
    [2000,  4000,   4000, 20, false, null],
    [3000,  6000,   6000, 20, false, null],
    [4000,  8000,   8000, 20, false, null],
    [5000,  10000,  10000,20, false, null],
    [8000,  16000,  16000,20, false, null]
  ]'::jsonb;
  v_lvl        jsonb;
begin
  -- --------------------------------------------------------------- club ---
  insert into clubs (slug, name, city, country, locale, timezone)
  values ('cutoff', 'Cutoff Poker Club', 'Gent', 'BE', 'nl', 'Europe/Brussels')
  on conflict (slug) do update set name = excluded.name
  returning id into v_club;

  -- ---------------------------------------------------------------- staf ---
  select id into v_user from auth.users where lower(email) = lower(v_email);

  if v_user is null then
    raise warning
      'Geen gebruiker gevonden met e-mailadres %. Maak hem aan onder Authentication > Users en draai dit script opnieuw.',
      v_email;
  else
    insert into club_members (club_id, user_id, role)
    values (v_club, v_user, 'owner')
    on conflict (club_id, user_id) do update set role = 'owner';
  end if;

  -- --------------------------------------------------- blindstructuur ---
  select id into v_struct
  from blind_structures where club_id = v_club and name = 'Standaard 20 min';

  if v_struct is null then
    insert into blind_structures (club_id, name, description)
    values (v_club, 'Standaard 20 min',
            'Levels van 20 minuten, pauze na elke vier levels. Ante vanaf level 6.')
    returning id into v_struct;
  end if;

  delete from blind_levels where structure_id = v_struct;

  for v_lvl in select * from jsonb_array_elements(v_levels) loop
    insert into blind_levels (structure_id, idx, small_blind, big_blind, ante,
                              duration_s, is_break, label)
    values (
      v_struct, v_idx,
      (v_lvl->>0)::int, (v_lvl->>1)::int, (v_lvl->>2)::int,
      (v_lvl->>3)::int * 60,
      (v_lvl->>4)::boolean,
      nullif(v_lvl->>5, 'null')
    );
    v_idx := v_idx + 1;
  end loop;

  -- ------------------------------------------------------------ payouts ---
  select id into v_payout from payout_templates where club_id = v_club and name = 'Standaard';
  if v_payout is null then
    insert into payout_templates (club_id, name, tiers, rounding)
    values (v_club, 'Standaard', '[
      {"min_entries": 2,  "max_entries": 8,   "percentages": [65, 35]},
      {"min_entries": 9,  "max_entries": 17,  "percentages": [50, 30, 20]},
      {"min_entries": 18, "max_entries": 29,  "percentages": [40, 25, 15, 12, 8]},
      {"min_entries": 30, "max_entries": 999, "percentages": [33, 21, 14, 10, 8, 6, 4, 4]}
    ]'::jsonb, 500)
    returning id into v_payout;
  end if;

  -- ------------------------------------------------------------ ranking ---
  select id into v_ranking from ranking_configs where club_id = v_club and name = 'Seizoensranking';
  if v_ranking is null then
    -- sqrt_ratio schaalt punten met de grootte van het veld, zodat een
    -- overwinning tegen 40 spelers meer waard is dan tegen 10.
    insert into ranking_configs (club_id, name, method, params, bonus_per_ko, bonus_entry)
    values (v_club, 'Seizoensranking', 'sqrt_ratio', '{"multiplier": 10}', 1, 2)
    returning id into v_ranking;
  end if;

  -- ------------------------------------------------------------ seizoen ---
  select id into v_season from seasons where club_id = v_club and name = 'Seizoen 2026-2027';
  if v_season is null then
    insert into seasons (club_id, name, starts_on, ends_on, ranking_config_id, is_active)
    values (v_club, 'Seizoen 2026-2027', date '2026-09-01', date '2027-06-30', v_ranking, true)
    returning id into v_season;
  end if;

  -- ------------------------------------------------------------ tornooi ---
  select id into v_tour
  from tournaments where club_id = v_club and name = 'Openingstornooi';

  if v_tour is null then
    insert into tournaments (
      club_id, season_id, structure_id, payout_template_id, name, scheduled_at,
      status, player_visibility, buyin_cents, fee_cents, starting_stack,
      max_reentries, late_reg_level
    ) values (
      v_club, v_season, v_struct, v_payout, 'Openingstornooi',
      timestamptz '2026-09-06 20:00:00+02',
      'scheduled', 'members', 2000, 500, 20000, 1, 6
    )
    returning id into v_tour;
  else
    update tournaments
    set structure_id = v_struct, payout_template_id = v_payout, season_id = v_season
    where id = v_tour;
  end if;

  raise notice 'Cutoff klaar. Tornooi-id: %', v_tour;
  raise notice 'Zaalscherm: /klok/%', v_tour;
  raise notice 'Floor:      /floor/%', v_tour;
end $$;
