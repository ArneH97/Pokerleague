-- Pokerleague — de cijfers van het platform zelf
--
-- Dit dashboard is het enige scherm waar de gegevens van álle clubs samenkomen.
-- Twee dingen moeten daarom kloppen, en de tweede is de belangrijkste:
--
--   * de getallen zijn juist — een omzet die er tien euro naast zit is erger
--     dan geen omzet, want je gaat hem geloven;
--   * niemand anders komt erbij. Niet een clubeigenaar, niet een floor, niet
--     een speler, niet een bezoeker. Ook niet half: de functie hoort te
--     wéigeren, niet stilletjes een lege lijst te geven waar iemand uit
--     afleidt dat het platform leeg is.
--
-- Bewaakt wordt:
--
--   1. de kerncijfers tellen clubs, mensen, avonden en geld correct op
--   2. het geld staat op de juiste hoop: pot, clubbijdrage en prijzen apart
--   3. de omzet volgt de afspraak per club, inclusief opstartkost
--   4. per club kloppen leden, avonden en gemiddeld veld
--   5. de maandreeks laat lege maanden staan
--   6. een clubeigenaar, een speler en een bezoeker krijgen een foutmelding

begin;

do $$
declare
  v_club_a uuid; v_club_b uuid;
  v_struct uuid; v_pay uuid;
  v_t1 uuid; v_t2 uuid; v_t3 uuid;
  v_admin uuid; v_owner uuid; v_speler uuid;
  v_tp_a uuid; v_tp_b uuid; v_tp_c uuid; v_tp_d uuid;
  v_pa uuid;
  v_n int; v_geld bigint; v_num numeric; v_d date;
  r record;
begin
  -- ------------------------------------------------------------------ opzet --
  -- Twee clubs: eentje die speelt en eentje die net begonnen is. Dat tweede
  -- geval is het interessante — een club zonder avonden mag de gemiddeldes
  -- niet omlaag trekken en moet wél in de omzet staan.
  insert into clubs (slug, name, city, country, locale, timezone, primary_color)
  values ('tp1', 'Testclub Alfa', 'Aalst', 'BE', 'nl', 'Europe/Brussels', '#14B2AD')
  returning id into v_club_a;

  insert into clubs (slug, name, city, country, locale, timezone, primary_color)
  values ('tp2', 'Testclub Beta', 'Gent', 'BE', 'nl', 'Europe/Brussels', '#c81e2d')
  returning id into v_club_b;

  -- De trigger hoort er meteen een facturatieregel bij gezet te hebben.
  select count(*) into v_n from club_billing where club_id in (v_club_a, v_club_b);
  if v_n <> 2 then
    raise exception 'FOUT: nieuwe clubs kregen % facturatieregels in plaats van 2', v_n;
  end if;
  raise notice 'OK  een nieuwe club krijgt vanzelf een facturatieregel';

  -- Vaste voorwaarden, anders hangt de test aan de dag waarop ze draait.
  update club_billing set setup_cents = 50000, monthly_cents = 3900,
         started_on = (current_date - interval '3 months')::date
   where club_id = v_club_a;
  update club_billing set setup_cents = 0, monthly_cents = 3900,
         started_on = current_date
   where club_id = v_club_b;

  insert into blind_structures (club_id, name) values (v_club_a, 'S') returning id into v_struct;
  insert into blind_levels (structure_id, idx, is_break, small_blind, big_blind, ante, duration_s)
  values (v_struct, 0, false, 25, 50, 0, 1200);
  insert into payout_templates (club_id, name, tiers, rounding)
  values (v_club_a, 'P', '[{"min_entries":2,"max_entries":99,"percentages":[100]}]'::jsonb, 100)
  returning id into v_pay;

  -- Twee avonden bij Alfa: vier man en drie man. Buy-in 20 euro, waarvan
  -- 2 euro clubbijdrage — dat is precies het onderscheid dat het dashboard
  -- moet maken.
  insert into tournaments (club_id, payout_template_id, structure_id, name, scheduled_at,
                           status, player_visibility, buyin_cents, fee_cents,
                           starting_stack, max_reentries)
  values (v_club_a, v_pay, v_struct, 'Avond 1', now() - interval '20 days',
          'running'::tournament_status, 'members'::visibility, 1800, 200, 20000, 0)
  returning id into v_t1;

  v_tp_a := public.floor_add_entry(v_t1, null, 'Speler A', 'a@tp.be');
  v_tp_b := public.floor_add_entry(v_t1, null, 'Speler B', 'b@tp.be');
  v_tp_c := public.floor_add_entry(v_t1, null, 'Speler C', 'c@tp.be');
  v_tp_d := public.floor_add_entry(v_t1, null, 'Speler D', 'd@tp.be');
  perform public.floor_eliminate(v_tp_d, null);
  perform public.floor_eliminate(v_tp_c, null);
  perform public.floor_eliminate(v_tp_b, null);
  perform public.floor_finish_tournament(v_t1);

  insert into tournaments (club_id, payout_template_id, structure_id, name, scheduled_at,
                           status, player_visibility, buyin_cents, fee_cents,
                           starting_stack, max_reentries)
  values (v_club_a, v_pay, v_struct, 'Avond 2', now() - interval '6 days',
          'running'::tournament_status, 'members'::visibility, 1800, 200, 20000, 0)
  returning id into v_t2;

  v_tp_a := public.floor_add_entry(v_t2, null, 'Speler A', 'a@tp.be');
  v_tp_b := public.floor_add_entry(v_t2, null, 'Speler B', 'b@tp.be');
  v_tp_c := public.floor_add_entry(v_t2, null, 'Speler E', 'e@tp.be');
  perform public.floor_eliminate(v_tp_c, null);
  perform public.floor_eliminate(v_tp_b, null);
  perform public.floor_finish_tournament(v_t2);

  -- En eentje die nog moet komen: die telt bij "gepland" en nergens anders.
  insert into tournaments (club_id, payout_template_id, structure_id, name, scheduled_at,
                           status, buyin_cents, fee_cents, starting_stack)
  values (v_club_a, v_pay, v_struct, 'Volgende week', now() + interval '5 days',
          'scheduled'::tournament_status, 1800, 200, 20000)
  returning id into v_t3;

  -- ------------------------------------------------------------------- 1 ---
  -- De kerncijfers. Servicecontext, dus de rechtencontrole laat door.
  select * into r from public.platform_overview();

  if r.clubs <> 2 then raise exception 'FOUT: % clubs geteld in plaats van 2', r.clubs; end if;
  if r.tournaments <> 2 then raise exception 'FOUT: % afgesloten avonden in plaats van 2', r.tournaments; end if;
  if r.upcoming <> 1 then raise exception 'FOUT: % geplande avonden in plaats van 1', r.upcoming; end if;
  if r.entries <> 7 then raise exception 'FOUT: % deelnames in plaats van 7', r.entries; end if;
  if r.players <> 5 then raise exception 'FOUT: % spelers in plaats van 5', r.players; end if;
  if r.memberships <> 5 then raise exception 'FOUT: % lidmaatschappen in plaats van 5', r.memberships; end if;
  if r.multi_club <> 0 then raise exception 'FOUT: % spelers bij meer clubs in plaats van 0', r.multi_club; end if;
  if r.avg_field <> 3.5 then raise exception 'FOUT: gemiddeld veld % in plaats van 3.5', r.avg_field; end if;
  raise notice 'OK  clubs, avonden, spelers en gemiddeld veld kloppen (% deelnames over % avonden)',
    r.entries, r.tournaments;

  -- ------------------------------------------------------------------- 2 ---
  -- Het geld staat op de juiste hoop. 7 inschrijvingen × 18 euro pot en
  -- 7 × 2 euro clubbijdrage. De prijzen zijn wat er weer uitging.
  if r.pot_cents <> 7 * 1800 then
    raise exception 'FOUT: prijzenpot % in plaats van %', r.pot_cents, 7 * 1800;
  end if;
  if r.fee_cents <> 7 * 200 then
    raise exception 'FOUT: clubbijdrage % in plaats van %', r.fee_cents, 7 * 200;
  end if;
  if r.prize_cents <> r.pot_cents then
    raise exception 'FOUT: uitbetaald % maar pot was %', r.prize_cents, r.pot_cents;
  end if;
  raise notice 'OK  pot (%), clubbijdrage (%) en prijzen (%) staan apart',
    r.pot_cents, r.fee_cents, r.prize_cents;

  -- ------------------------------------------------------------------- 3 ---
  -- De omzet. Alfa loopt vier maanden (de maand van instap telt mee) plus de
  -- opstartkost; Beta staat in haar eerste maand zonder opstart.
  if r.mrr_cents <> 7800 then
    raise exception 'FOUT: MRR % in plaats van 7800', r.mrr_cents;
  end if;
  if r.arr_cents <> 93600 then
    raise exception 'FOUT: ARR % in plaats van 93600', r.arr_cents;
  end if;
  if r.setup_cents <> 50000 then
    raise exception 'FOUT: opstartkosten % in plaats van 50000', r.setup_cents;
  end if;
  if r.revenue_cents <> 50000 + 4 * 3900 + 3900 then
    raise exception 'FOUT: omzet tot nu % in plaats van %', r.revenue_cents, 50000 + 4 * 3900 + 3900;
  end if;
  raise notice 'OK  omzet volgt de afspraak per club (MRR %, tot nu %)', r.mrr_cents, r.revenue_cents;

  -- ------------------------------------------------------------------- 4 ---
  -- Per club. Beta heeft niets gespeeld en moet toch netjes op nul staan
  -- in plaats van te ontbreken.
  select count(*) into v_n from public.platform_clubs();
  if v_n <> 2 then raise exception 'FOUT: % clubregels in plaats van 2', v_n; end if;

  select * into r from public.platform_clubs() where slug = 'tp1';
  if r.members <> 5 then raise exception 'FOUT: Alfa heeft % leden in plaats van 5', r.members; end if;
  if r.tournaments <> 2 then raise exception 'FOUT: Alfa heeft % avonden in plaats van 2', r.tournaments; end if;
  if r.entries <> 7 then raise exception 'FOUT: Alfa heeft % deelnames in plaats van 7', r.entries; end if;
  if r.avg_field <> 3.5 then raise exception 'FOUT: Alfa gemiddeld veld %', r.avg_field; end if;
  if r.fee_cents <> 1400 then raise exception 'FOUT: Alfa clubbijdrage %', r.fee_cents; end if;
  if r.active_30d <> 5 then raise exception 'FOUT: Alfa % actief in 30 dagen', r.active_30d; end if;

  select * into r from public.platform_clubs() where slug = 'tp2';
  if r.tournaments <> 0 or r.entries <> 0 then
    raise exception 'FOUT: Beta heeft avonden of deelnames die er niet zijn';
  end if;
  if r.revenue_cents <> 3900 then
    raise exception 'FOUT: Beta bracht % op in plaats van 3900', r.revenue_cents;
  end if;
  raise notice 'OK  per club kloppen leden, avonden, veld en omzet';

  -- ------------------------------------------------------------------- 5 ---
  -- De maandreeks geeft altijd evenveel maanden terug, ook de lege.
  select count(*) into v_n from public.platform_month_series(6);
  if v_n <> 6 then raise exception 'FOUT: % maanden in plaats van 6', v_n; end if;

  select sum(m.entries) into v_n from public.platform_month_series(6) m;
  if v_n <> 7 then raise exception 'FOUT: % deelnames over zes maanden in plaats van 7', v_n; end if;

  select sum(m.revenue_cents) into v_geld from public.platform_month_series(6) m;
  if v_geld <> 50000 + 4 * 3900 + 3900 then
    raise exception 'FOUT: omzet over de reeks % in plaats van %', v_geld, 50000 + 4 * 3900 + 3900;
  end if;
  raise notice 'OK  de maandreeks laat lege maanden staan en telt op tot hetzelfde';

  -- Per club per maand: twee clubs × zes maanden.
  select count(*) into v_n from public.platform_club_month_series(6);
  if v_n <> 12 then raise exception 'FOUT: % rijen club×maand in plaats van 12', v_n; end if;

  -- De top: A speelde twee keer en won twee keer.
  select * into r from public.platform_top_players(10) limit 1;
  if r.entries <> 2 or r.wins <> 2 then
    raise exception 'FOUT: de koploper heeft % deelnames en % overwinningen', r.entries, r.wins;
  end if;
  if r.net_cents <= 0 then
    raise exception 'FOUT: de winnaar staat op % en dat kan niet', r.net_cents;
  end if;

  -- De laatste avonden staan nieuwste eerst. `ended_at` is het moment van
  -- afsluiten en niet de geplande datum — Avond 2 werd als laatste afgesloten
  -- en hoort dus bovenaan.
  select * into r from public.platform_recent(5) limit 1;
  if r.name <> 'Avond 2' then
    raise exception 'FOUT: bovenaan staat % in plaats van Avond 2', r.name;
  end if;
  if r.entries <> 3 or r.winner is null then
    raise exception 'FOUT: Avond 2 heeft % deelnames en winnaar %', r.entries, r.winner;
  end if;

  -- En de datum die er staat is de speeldatum, niet het moment van afsluiten.
  -- Een avond die na middernacht eindigt hoort bij de dag waarop hij begon.
  if r.played_on <> ((now() - interval '6 days') at time zone 'Europe/Brussels')::date then
    raise exception 'FOUT: Avond 2 staat op % in plaats van op zijn speeldatum', r.played_on;
  end if;

  select last_night into v_d from public.platform_clubs() where slug = 'tp1';
  if v_d <> ((now() - interval '6 days') at time zone 'Europe/Brussels')::date then
    raise exception 'FOUT: de laatste avond van Alfa staat op %', v_d;
  end if;
  raise notice 'OK  top spelers en laatste avonden staan in de juiste volgorde';

  -- ------------------------------------------------------------------- 6 ---
  -- En dan de grens. Drie soorten mensen die er niet bij horen.
  insert into auth.users (email) values ('eigenaar@tp.be') returning id into v_owner;
  insert into auth.users (email) values ('speler@tp.be')   returning id into v_speler;
  insert into auth.users (email) values ('arne@halcoservices.be') returning id into v_admin;

  insert into club_members (club_id, user_id, role)
  values (v_club_a, v_owner, 'owner'::club_role);

  select id into v_pa from players where email = 'a@tp.be';
  update players set auth_user_id = v_speler, link_state = 'claimed' where id = v_pa;

  -- De clubeigenaar. Zijn eigen club mag hij zien; het platform niet.
  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  set local role authenticated;

  if public.is_platform_admin() then
    raise exception 'FOUT: een clubeigenaar geldt als platformbeheerder';
  end if;

  begin
    perform * from public.platform_overview();
    raise exception 'FOUT: een clubeigenaar kreeg de platformcijfers te zien';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform * from public.platform_clubs();
    raise exception 'FOUT: een clubeigenaar kreeg de clublijst van het platform';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform * from public.platform_top_players(5);
    raise exception 'FOUT: een clubeigenaar kreeg de spelerslijst van het platform';
  exception when insufficient_privilege then
    null;
  end;
  reset role;
  raise notice 'OK  een clubeigenaar komt er niet bij';

  -- De speler.
  perform set_config('request.jwt.claim.sub', v_speler::text, true);
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_speler, 'role', 'authenticated')::text, true);
  set local role authenticated;

  begin
    perform * from public.platform_month_series(6);
    raise exception 'FOUT: een speler kreeg de maandcijfers van het platform';
  exception when insufficient_privilege then
    null;
  end;

  -- En hij mag ook niet zien wíé beheerder is, of wat een club betaalt.
  -- Twee sloten: de rechten zijn ingetrokken én RLS staat aan zonder policy.
  -- Welk van de twee dichtvalt maakt niet uit, als er maar niets doorkomt.
  begin
    select count(*) into v_n from platform_admins;
    if v_n <> 0 then raise exception 'FOUT: een speler ziet % beheerders', v_n; end if;
  exception when insufficient_privilege then
    null;
  end;

  begin
    select count(*) into v_n from club_billing;
    if v_n <> 0 then raise exception 'FOUT: een speler ziet % facturatieregels', v_n; end if;
  exception when insufficient_privilege then
    null;
  end;
  reset role;
  raise notice 'OK  een speler ziet noch de cijfers, noch wie beheerder is, noch wat een club betaalt';

  -- De bezoeker zonder account.
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.role', 'anon', true);
  set local role anon;

  begin
    perform * from public.platform_overview();
    raise exception 'FOUT: een bezoeker kreeg de platformcijfers te zien';
  exception when insufficient_privilege then
    null;
  end;
  reset role;
  raise notice 'OK  een bezoeker komt er niet bij';

  -- En de beheerder zelf wél.
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  set local role authenticated;

  if not public.is_platform_admin() then
    raise exception 'FOUT: arne@halcoservices.be geldt niet als beheerder';
  end if;

  select * into r from public.platform_overview();
  if r.clubs <> 2 then
    raise exception 'FOUT: de beheerder ziet % clubs in plaats van 2', r.clubs;
  end if;

  select count(*) into v_n from public.platform_clubs();
  if v_n <> 2 then raise exception 'FOUT: de beheerder ziet % clubregels', v_n; end if;
  reset role;
  raise notice 'OK  de beheerder ziet alles';

  -- Hoofdletters in het e-mailadres mogen niet uitmaken.
  update auth.users set email = 'Arne@Halcoservices.BE' where id = v_admin;
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  set local role authenticated;
  if not public.is_platform_admin() then
    raise exception 'FOUT: hoofdletters in het e-mailadres sluiten de beheerder buiten';
  end if;
  reset role;
  raise notice 'OK  hoofdletters in het e-mailadres maken niets uit';

  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);
  perform set_config('request.jwt.claims', '', true);
end $$;

rollback;
