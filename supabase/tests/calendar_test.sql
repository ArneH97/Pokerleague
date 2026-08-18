-- Pokerleague — de agenda van een speler over al zijn clubs heen
--
-- Deze lijst is het eerste scherm waar gegevens van twee clubs door elkaar
-- staan zonder dat er een clubomgeving omheen zit. Dat maakt de
-- zichtbaarheidsregel hier belangrijker dan waar ook: één te ruime regel en
-- een speler leest de agenda van een club waar hij niets mee te maken heeft.
--
-- Bewaakt wordt:
--
--   1. hij ziet de komende avonden van al zijn clubs, in volgorde van datum
--   2. een club waar hij niet bij hoort komt er niet in
--   3. een besloten avond blijft besloten, ook bij zijn eigen club
--   4. een avond die nu bezig is staat er wél in, een afgesloten avond niet
--   5. `i_play` klopt: staat hij al ingeschreven of niet
--   6. zonder aanmelding krijgt hij niets

begin;

do $$
declare
  v_club_a uuid; v_club_b uuid; v_club_x uuid;
  v_struct uuid; v_pay uuid;
  v_user uuid; v_me uuid;
  v_open uuid; v_dicht uuid; v_bezig uuid; v_klaar uuid; v_ander uuid; v_later uuid;
  v_tp uuid;
  v_n int; v_slug text; v_i boolean;
  r record;
begin
  insert into clubs (slug, name, city, country, locale, timezone, primary_color)
  values ('tc1', 'Agendaclub A', 'Aalst', 'BE', 'nl', 'Europe/Brussels', '#14B2AD')
  returning id into v_club_a;
  insert into clubs (slug, name, city, country, locale, timezone, primary_color)
  values ('tc2', 'Agendaclub B', 'Gent', 'BE', 'nl', 'Europe/Brussels', '#c8a15c')
  returning id into v_club_b;
  insert into clubs (slug, name, city, country, locale, timezone, primary_color)
  values ('tc3', 'Vreemde club', 'Brugge', 'BE', 'nl', 'Europe/Brussels', '#888888')
  returning id into v_club_x;

  insert into blind_structures (club_id, name) values (v_club_a, 'S') returning id into v_struct;
  insert into blind_levels (structure_id, idx, is_break, small_blind, big_blind, ante, duration_s)
  values (v_struct, 0, false, 25, 50, 0, 1200);
  insert into payout_templates (club_id, name, tiers, rounding)
  values (v_club_a, 'P', '[{"min_entries":2,"max_entries":99,"percentages":[100]}]'::jsonb, 100)
  returning id into v_pay;

  -- De speler. Hij hoort bij A en B, niet bij de vreemde club.
  insert into auth.users (email) values ('speler@tc.be') returning id into v_user;
  insert into players (display_name, email, auth_user_id, link_state)
  values ('Speler Agenda', 'speler@tc.be', v_user, 'claimed') returning id into v_me;
  insert into club_players (club_id, player_id) values (v_club_a, v_me);
  insert into club_players (club_id, player_id) values (v_club_b, v_me);

  -- Bij A: een open avond volgende week, een besloten avond, een avond die nu
  -- bezig is en een die al afgelopen is.
  insert into tournaments (club_id, payout_template_id, structure_id, name, scheduled_at,
                           status, player_visibility, buyin_cents, fee_cents, starting_stack)
  values (v_club_a, v_pay, v_struct, 'Volgende donderdag', now() + interval '7 days',
          'scheduled'::tournament_status, 'members'::visibility, 1800, 200, 20000)
  returning id into v_open;

  insert into tournaments (club_id, payout_template_id, structure_id, name, scheduled_at,
                           status, player_visibility, buyin_cents, fee_cents, starting_stack)
  values (v_club_a, v_pay, v_struct, 'Besloten avond', now() + interval '8 days',
          'scheduled'::tournament_status, 'private'::visibility, 1800, 200, 20000)
  returning id into v_dicht;

  insert into tournaments (club_id, payout_template_id, structure_id, name, scheduled_at,
                           status, player_visibility, buyin_cents, fee_cents, starting_stack)
  values (v_club_a, v_pay, v_struct, 'Nu bezig', now() - interval '2 hours',
          'running'::tournament_status, 'members'::visibility, 1800, 200, 20000)
  returning id into v_bezig;

  insert into tournaments (club_id, payout_template_id, structure_id, name, scheduled_at,
                           status, player_visibility, buyin_cents, fee_cents, starting_stack)
  values (v_club_a, v_pay, v_struct, 'Vorige week', now() - interval '7 days',
          'finished'::tournament_status, 'members'::visibility, 1800, 200, 20000)
  returning id into v_klaar;

  -- Bij B: eentje morgen. Bij de vreemde club: eentje overmorgen, publiek —
  -- dus zichtbaar op hún pagina, maar niet in zíjn agenda.
  insert into tournaments (club_id, name, scheduled_at, status, player_visibility,
                           buyin_cents, fee_cents, starting_stack)
  values (v_club_b, 'Morgenavond', now() + interval '1 day',
          'scheduled'::tournament_status, 'public'::visibility, 2500, 500, 20000)
  returning id into v_ander;

  insert into tournaments (club_id, name, scheduled_at, status, player_visibility,
                           buyin_cents, fee_cents, starting_stack)
  values (v_club_x, 'Niet van jou', now() + interval '2 days',
          'scheduled'::tournament_status, 'public'::visibility, 2000, 0, 20000)
  returning id into v_later;

  -- Hij schrijft zich in voor de avond die bezig is.
  v_tp := public.floor_add_entry(v_bezig, v_me, null, null);

  -- ------------------------------------------------------------------- 1 ---
  perform set_config('request.jwt.claim.sub', v_user::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_user, 'role', 'authenticated')::text, true);
  set local role authenticated;

  select count(*) into v_n from public.my_calendar();
  if v_n <> 3 then
    raise exception 'FOUT: % afspraken in de agenda in plaats van 3', v_n;
  end if;

  -- Op datum, en de avond die bezig is staat vooraan.
  select name into v_slug from public.my_calendar() limit 1;
  if v_slug <> 'Nu bezig' then
    raise exception 'FOUT: bovenaan staat % in plaats van de avond die bezig is', v_slug;
  end if;

  select club_slug into v_slug from public.my_calendar() offset 1 limit 1;
  if v_slug <> 'tc2' then
    raise exception 'FOUT: op de tweede plaats staat % in plaats van tc2', v_slug;
  end if;
  raise notice 'OK  de agenda toont beide clubs, op datum, met de lopende avond vooraan';

  -- ------------------------------------------------------------------- 2 ---
  if exists (select 1 from public.my_calendar() where club_slug = 'tc3') then
    raise exception 'FOUT: een club waar hij niet bij hoort staat in zijn agenda';
  end if;
  raise notice 'OK  een vreemde club komt er niet in, ook niet als de avond publiek is';

  -- ------------------------------------------------------------------- 3 ---
  if exists (select 1 from public.my_calendar() where name = 'Besloten avond') then
    raise exception 'FOUT: een besloten avond staat in de agenda';
  end if;
  raise notice 'OK  een besloten avond blijft besloten, ook bij zijn eigen club';

  -- ------------------------------------------------------------------- 4 ---
  if exists (select 1 from public.my_calendar() where name = 'Vorige week') then
    raise exception 'FOUT: een afgesloten avond staat nog in de agenda';
  end if;
  raise notice 'OK  wat gespeeld is verdwijnt uit de agenda';

  -- ------------------------------------------------------------------- 5 ---
  select i_play into v_i from public.my_calendar() where name = 'Nu bezig';
  if not v_i then raise exception 'FOUT: hij staat ingeschreven maar i_play is onwaar'; end if;

  select * into r from public.my_calendar() where name = 'Morgenavond';
  if r.i_play then raise exception 'FOUT: hij staat niet ingeschreven maar i_play is waar'; end if;
  if r.buyin_cents <> 2500 or r.fee_cents <> 500 then
    raise exception 'FOUT: de prijs klopt niet (% + %)', r.buyin_cents, r.fee_cents;
  end if;
  if r.primary_color is null or r.club_name <> 'Agendaclub B' then
    raise exception 'FOUT: de club staat er niet goed bij';
  end if;

  select entries into v_n from public.my_calendar() where name = 'Nu bezig';
  if v_n <> 1 then raise exception 'FOUT: % ingeschreven in plaats van 1', v_n; end if;
  raise notice 'OK  prijs, club, aantal ingeschreven en "ik speel mee" kloppen';

  -- Een venster van één dag laat alleen wat er binnen die dag valt.
  select count(*) into v_n from public.my_calendar(1);
  if v_n <> 2 then
    raise exception 'FOUT: % afspraken binnen één dag in plaats van 2', v_n;
  end if;
  raise notice 'OK  het venster in dagen doet wat het zegt';

  reset role;

  -- ------------------------------------------------------------------- 6 ---
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.role', 'anon', true);
  set local role anon;

  -- De rechten zijn ingetrokken bij `public`, dus een bezoeker botst al op de
  -- deur voor de functie iets kan teruggeven. Zou dat ooit veranderen, dan
  -- moet het antwoord in elk geval leeg zijn — beide zijn goed, doorlaten niet.
  begin
    select count(*) into v_n from public.my_calendar();
    if v_n <> 0 then raise exception 'FOUT: een bezoeker kreeg % afspraken', v_n; end if;
  exception when insufficient_privilege then
    null;
  end;
  reset role;
  raise notice 'OK  zonder aanmelding komt er niets uit de agenda';

  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);
  perform set_config('request.jwt.claims', '', true);
end $$;

rollback;
