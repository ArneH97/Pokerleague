-- Pokerleague — Aalst Poker Club opzetten
--
-- Dit is `nieuwe_club.sql` met de gegevens van Aalst er al in. Plak het
-- geheel in de SQL-editor van Supabase en druk op Run. Er is niets aan te
-- passen behalve wat hieronder als "nog aan te vullen" gemarkeerd staat.
--
-- Wat het doet:
--   * de club met haar huisstijl, adres en speeldag
--   * een blindstructuur van 20 niveaus met drie pauzes
--   * een uitbetalingsschema dat meeschaalt met het veld
--   * een seizoen met de puntenformule (sqrt_ratio, de gangbare)
--   * het beheerdersaccount als eigenaar, als dat account al bestaat
--
-- Twee keer draaien is veilig: bestaat de slug al, dan stopt het script.
--
-- Let op: de logo's staan in `public/clubs/` en zijn dus pas zichtbaar nadat
-- de code gepusht is. Draai je dit script vóór de push, dan staat er even een
-- letter in plaats van een logo. Verder werkt alles.

do $$
declare
  -- ======================================================================
  -- DE CLUB
  -- ======================================================================
  c_slug        text := 'aalst';
  c_name        text := 'Aalst Poker Club';
  c_city        text := 'Aalst';
  c_locale      text := 'nl';
  c_color       text := '#14B2AD';               -- petrolgroen, zie het logo
  c_intro       text := 'Pokerclub in Aalst, elke donderdag in de Sint-Annakring. Een vaste structuur, een echte klok en een klassement dat het hele seizoen meeloopt. Nieuwe spelers zijn welkom.';
  c_address     text := 'Sint-Annakring, Roklijf 4, 9300 Aalst';
  c_maps        text := 'https://www.google.com/maps/search/?api=1&query=Sint-Annakring%2C+Roklijf+4%2C+9300+Aalst';
  c_rhythm      text := 'Elke donderdag';        -- ← vul het uur aan zodra je het weet: 'Elke donderdag om 20u'
  c_mail        text := null;                    -- ← publiek contactadres van de club
  c_phone       text := null;                    -- ← publiek telefoonnummer
  -- Twee beelden, en het onderscheid doet ertoe.
  --   logo_url  = het vierkante embleem (spade + APC). Dat komt in de balk
  --               bovenaan en als tegel op de spelerspagina, allebei kleine
  --               vierkantjes — een breed woordmerk wordt daar onleesbaar.
  --   mark_url  = alleen de schoppen, vrijstaand. Die staat groot en zacht
  --               achter de klok in de zaal en in de kop van de clubpagina.
  -- Het brede woordmerk (`aalst-logo.png`) is voor affiches en drukwerk en
  -- hoort niet in de database.
  c_logo        text := '/clubs/aalst-badge.png';
  c_mark        text := '/clubs/aalst-mark.png';
  c_opens_on    date := null;                    -- ze draaien al, dus geen openingsdatum
  c_open_signup boolean := true;

  -- Wie de club beheert. Dit account moet al bestaan op pokerleague.be.
  -- Voor de demo staat jouw adres hier; vervang het door dat van hun
  -- verantwoordelijke zodra hij zich geregistreerd heeft.
  c_owner_email text := 'arne@halcoservices.be';

  -- ======================================================================
  -- HOE ER GESPEELD WORDT — aanpassen zodra je hun echte structuur kent
  -- ======================================================================

  -- small blind, big blind, ante, minuten
  c_levels int[][] := array[
    [25,50,0,20], [50,100,0,20], [75,150,0,20], [100,200,0,20],
    [150,300,300,20], [200,400,400,20], [300,600,600,20], [400,800,800,20],
    [500,1000,1000,20], [600,1200,1200,20], [800,1600,1600,20], [1000,2000,2000,20],
    [1500,3000,3000,20], [2000,4000,4000,20], [2500,5000,5000,20], [3000,6000,6000,20],
    [4000,8000,8000,20], [5000,10000,10000,20], [6000,12000,12000,20], [8000,16000,16000,20]
  ];
  c_breaks int[] := array[4, 8, 12];             -- pauze van 10 minuten ná deze niveaus

  c_payouts jsonb := '[
    {"min_entries": 2,  "max_entries": 7,  "percentages": [70, 30]},
    {"min_entries": 8,  "max_entries": 15, "percentages": [50, 30, 20]},
    {"min_entries": 16, "max_entries": 29, "percentages": [40, 25, 18, 17]},
    {"min_entries": 30, "max_entries": 99, "percentages": [35, 22, 15, 12, 9, 7]}
  ]'::jsonb;

  c_points_method text  := 'sqrt_ratio';
  c_points_params jsonb := '{"multiplier": 10}'::jsonb;
  c_points_per_ko numeric := 0;
  c_points_entry  numeric := 0;
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

  insert into clubs (
    slug, name, city, country, locale, currency, timezone,
    primary_color, intro, address_line, maps_url, play_rhythm,
    contact_email, contact_phone, logo_url, mark_url,
    opens_on, open_signup, is_active
  ) values (
    c_slug, c_name, c_city, 'BE', c_locale, 'EUR', 'Europe/Brussels',
    c_color, c_intro, c_address, c_maps, c_rhythm,
    c_mail, c_phone, c_logo, c_mark,
    c_opens_on, c_open_signup, true
  )
  returning id into v_club;

  insert into blind_structures (club_id, name)
  values (v_club, 'Standaard')
  returning id into v_struct;

  for i in 1 .. array_length(c_levels, 1) loop
    insert into blind_levels (structure_id, idx, is_break, small_blind, big_blind, ante, duration_s)
    values (v_struct, v_idx, false, c_levels[i][1], c_levels[i][2], c_levels[i][3], c_levels[i][4] * 60);
    v_idx := v_idx + 1;

    if i = any (c_breaks) then
      insert into blind_levels (structure_id, idx, is_break, small_blind, big_blind, ante, duration_s, label)
      values (v_struct, v_idx, true, 0, 0, 0, 10 * 60, 'Pauze');
      v_idx := v_idx + 1;
    end if;
  end loop;

  insert into payout_templates (club_id, name, tiers, rounding)
  values (v_club, 'Standaard', c_payouts, 100);

  insert into ranking_configs (club_id, name, method, params, bonus_per_ko, bonus_entry)
  values (v_club, 'Standaard', c_points_method::ranking_method, c_points_params,
          c_points_per_ko, c_points_entry)
  returning id into v_rank;

  insert into seasons (club_id, name, starts_on, ranking_config_id, is_active)
  values (v_club, c_season_name, c_season_start, v_rank, true);

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

  raise notice 'Klaar. % staat op pokerleague.be/c/%', c_name, c_slug;
end $$;

select slug, name, city, primary_color, play_rhythm, logo_url,
       (select count(*) from blind_levels bl
        join blind_structures bs on bs.id = bl.structure_id
        where bs.club_id = clubs.id)                                as niveaus,
       (select count(*) from seasons s where s.club_id = clubs.id)  as seizoenen,
       (select count(*) from club_members m where m.club_id = clubs.id) as medewerkers
from clubs
order by created_at;
