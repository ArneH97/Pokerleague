-- Pokerleague — een nieuwe club opzetten
--
-- Alles wat een club nodig heeft om vanavond te kunnen draaien, in één script:
-- de club zelf met haar huisstijl, een blindstructuur, een uitbetalingsschema,
-- een seizoen met een puntenformule, en de koppeling van het beheerdersaccount.
--
-- ---------------------------------------------------------------------------
-- VOORAF
-- ---------------------------------------------------------------------------
--
--   1. De beheerder van de club maakt eerst zelf een account op
--      pokerleague.be/registreren. Eén account is genoeg — hetzelfde account
--      is speler op het platform én staf bij de club. Zonder dat account kan
--      dit script hem nergens aan koppelen; het zegt dat dan ook.
--
--   2. Vul hieronder de blok "instellen" in en draai het geheel in de
--      SQL-editor van Supabase.
--
--   3. Meteen daarna bereikbaar op:
--        pokerleague.be/c/<slug>        — de clubpagina voor spelers
--        <slug>.pokerleague.be          — hetzelfde, op het eigen subdomein
--        <slug>.pokerleague.be/c/<slug>/login — het personeelsscherm
--      Een eigen domein (app.club.be) is een aparte stap: de club zet een
--      CNAME, wij zetten het domein bij de hosting, en dan vul je
--      `clubs.custom_domain` in. Niet nodig om te starten.
--
-- Twee keer draaien is veilig: bestaat de slug al, dan stopt het script.

do $$
declare
  -- ======================================================================
  -- INSTELLEN — alleen dit blok aanpassen
  -- ======================================================================

  -- Wie de club is.
  c_slug        text := 'aalst';
  c_name        text := 'Aalst Poker Club';
  c_city        text := 'Aalst';
  c_locale      text := 'nl';                    -- 'nl' | 'fr' | 'en'
  c_color       text := '#2f7fd4';               -- huisstijlkleur, hex
  c_intro       text := 'Pokerclub in Aalst. Elke woensdag een tornooi met een vaste structuur, een echte klok en een klassement over het seizoen.';
  c_address     text := null;                    -- 'Straat 1, 9300 Aalst'
  c_maps        text := null;                    -- link naar Google Maps
  c_rhythm      text := 'Elke woensdag om 20u';
  c_mail        text := null;                    -- contactadres van de club
  c_phone       text := null;
  c_opens_on    date := null;                    -- opening, of null als ze al draaien
  c_open_signup boolean := true;                 -- mogen spelers zich hier zelf aansluiten?

  -- Wie de club beheert. Dit account moet al bestaan (zie VOORAF, punt 1).
  c_owner_email text := 'arne@halcoservices.be';

  -- De blindstructuur: small blind, big blind, ante, minuten.
  -- Ante vanaf niveau 5, en een pauze na elk vierde niveau — pas gerust aan.
  -- Inkoop, fee en startstapel horen hier niet: die staan per tornooi, want
  -- een club speelt niet elke avond dezelfde formule.
  c_levels int[][] := array[
    [25,50,0,20], [50,100,0,20], [75,150,0,20], [100,200,0,20],
    [150,300,300,20], [200,400,400,20], [300,600,600,20], [400,800,800,20],
    [500,1000,1000,20], [600,1200,1200,20], [800,1600,1600,20], [1000,2000,2000,20],
    [1500,3000,3000,20], [2000,4000,4000,20], [2500,5000,5000,20], [3000,6000,6000,20],
    [4000,8000,8000,20], [5000,10000,10000,20], [6000,12000,12000,20], [8000,16000,16000,20]
  ];
  c_breaks int[] := array[4, 8, 12];             -- pauze ná deze niveaus

  -- Wie er betaald wordt, per veldgrootte. Percentages moeten optellen tot 100.
  c_payouts jsonb := '[
    {"min_entries": 2,  "max_entries": 7,  "percentages": [70, 30]},
    {"min_entries": 8,  "max_entries": 15, "percentages": [50, 30, 20]},
    {"min_entries": 16, "max_entries": 29, "percentages": [40, 25, 18, 17]},
    {"min_entries": 30, "max_entries": 99, "percentages": [35, 22, 15, 12, 9, 7]}
  ]'::jsonb;

  -- De puntenformule van het klassement.
  --   sqrt_ratio : multiplier * sqrt(veld) / sqrt(plaats)   ← de gangbare
  --   linear     : base - (plaats-1) * decrement, met een bodem
  --   fixed_table: een vaste tabel, plaats voor plaats
  --   pokerstars : als sqrt_ratio, maar zwaarder voor grote inkopen
  c_points_method text  := 'sqrt_ratio';
  c_points_params jsonb := '{"multiplier": 10}'::jsonb;
  c_points_per_ko numeric := 0;                  -- extra punten per knock-out
  c_points_entry  numeric := 0;                  -- deelnamepunten
  c_season_name   text := 'Seizoen 2026';
  c_season_start  date := date_trunc('year', current_date)::date;

  -- ======================================================================

  v_club   uuid;
  v_struct uuid;
  v_rank   uuid;
  v_user   uuid;
  i int;
  v_idx int := 0;
begin
  if exists (select 1 from clubs where slug = c_slug) then
    raise notice 'Er bestaat al een club met slug "%". Niets gedaan.', c_slug;
    return;
  end if;

  -- ------------------------------------------------------------- de club ---
  insert into clubs (
    slug, name, city, country, locale, currency, timezone,
    primary_color, intro, address_line, maps_url, play_rhythm,
    contact_email, contact_phone, opens_on, open_signup, is_active
  ) values (
    c_slug, c_name, c_city, 'BE', c_locale, 'EUR', 'Europe/Brussels',
    c_color, c_intro, c_address, c_maps, c_rhythm,
    c_mail, c_phone, c_opens_on, c_open_signup, true
  )
  returning id into v_club;

  -- --------------------------------------------------------- blindniveaus ---
  insert into blind_structures (club_id, name)
  values (v_club, 'Standaard')
  returning id into v_struct;

  for i in 1 .. array_length(c_levels, 1) loop
    insert into blind_levels (structure_id, idx, is_break, small_blind, big_blind, ante, duration_s)
    values (v_struct, v_idx, false, c_levels[i][1], c_levels[i][2], c_levels[i][3], c_levels[i][4] * 60);
    v_idx := v_idx + 1;

    -- Een pauze is een niveau zonder blinds. Zo telt de klok hem mee in de
    -- tijd, maar niet in de nummering die de zaal ziet.
    if i = any (c_breaks) then
      insert into blind_levels (structure_id, idx, is_break, small_blind, big_blind, ante, duration_s, label)
      values (v_struct, v_idx, true, 0, 0, 0, 10 * 60, 'Pauze');
      v_idx := v_idx + 1;
    end if;
  end loop;

  -- ------------------------------------------------------------ uitbetaling ---
  insert into payout_templates (club_id, name, tiers, rounding)
  values (v_club, 'Standaard', c_payouts, 100);

  -- ------------------------------------------------ klassement en seizoen ---
  insert into ranking_configs (club_id, name, method, params, bonus_per_ko, bonus_entry)
  values (v_club, 'Standaard', c_points_method::ranking_method, c_points_params,
          c_points_per_ko, c_points_entry)
  returning id into v_rank;

  insert into seasons (club_id, name, starts_on, ranking_config_id, is_active)
  values (v_club, c_season_name, c_season_start, v_rank, true);

  -- --------------------------------------------------------- de beheerder ---
  select id into v_user from auth.users where lower(email) = lower(c_owner_email);

  if v_user is null then
    raise notice '----------------------------------------------------------';
    raise notice 'De club staat er, maar er is nog geen account voor %.', c_owner_email;
    raise notice 'Laat die persoon zich registreren op pokerleague.be/registreren';
    raise notice 'en draai daarna alleen dit stukje:';
    raise notice '';
    raise notice '  insert into club_members (club_id, user_id, role)';
    raise notice '  select c.id, u.id, ''owner''::club_role';
    raise notice '  from clubs c, auth.users u';
    raise notice '  where c.slug = % and lower(u.email) = %;',
      quote_literal(c_slug), quote_literal(lower(c_owner_email));
    raise notice '----------------------------------------------------------';
  else
    insert into club_members (club_id, user_id, role)
    values (v_club, v_user, 'owner')
    on conflict (club_id, user_id) do update set role = 'owner';
    raise notice 'Beheerder % gekoppeld als owner.', c_owner_email;
  end if;

  raise notice 'Klaar. % staat klaar op pokerleague.be/c/% en op %.pokerleague.be',
    c_name, c_slug, c_slug;
end $$;

-- Wat er nu staat.
select c.slug, c.name, c.city, c.primary_color,
       (select count(*) from blind_levels bl
        join blind_structures bs on bs.id = bl.structure_id
        where bs.club_id = c.id)                                   as niveaus,
       (select count(*) from payout_templates p where p.club_id = c.id) as schemas,
       (select count(*) from seasons s where s.club_id = c.id)          as seizoenen,
       (select count(*) from club_members m where m.club_id = c.id)     as medewerkers
from clubs c
order by c.created_at;
