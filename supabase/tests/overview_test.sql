-- Tests voor het ledenbestand en de clubcijfers.
-- Draait in een transactie die terugrolt, dus veilig tegen de echte database.

begin;
do $$
declare
  v_club uuid; v_rc uuid; v_season uuid; v_pt uuid; v_tour uuid; v_tp uuid;
  v_n int; v_num numeric; v_txt text;
begin
  insert into clubs (slug,name,timezone,compliance)
  values ('t-'||substr(gen_random_uuid()::text,1,12),'Overzicht','Europe/Brussels',
          jsonb_build_object('enforce','off'))
  returning id into v_club;
  insert into ranking_configs (club_id,name,method,params,bonus_per_ko,bonus_entry)
  values (v_club,'R','sqrt_ratio','{"multiplier":10}',1,2) returning id into v_rc;
  insert into seasons (club_id,name,starts_on,ranking_config_id)
  values (v_club,'S',current_date-30,v_rc) returning id into v_season;
  insert into payout_templates (club_id,name,tiers)
  values (v_club,'P','[{"min_entries":2,"max_entries":99,"percentages":[60,40]}]'::jsonb)
  returning id into v_pt;

  insert into tournaments (club_id,season_id,payout_template_id,name,scheduled_at,status,
                           buyin_cents,fee_cents,starting_stack,started_at)
  values (v_club,v_season,v_pt,'Avond',now(),'running',2000,500,20000, now() - interval '3 hours')
  returning id into v_tour;

  v_tp := public.floor_add_entry(v_tour,null,'Anna','anna-'||substr(gen_random_uuid()::text,1,6)||'@t.be');
  perform public.floor_add_entry(v_tour,null,'Bert',null,'geen mail');
  perform public.floor_add_entry(v_tour,null,'Cis',null,'geen mail');
  perform public.floor_finish_tournament(v_tour);

  -- ledenbestand
  select count(*) into v_n from public.club_member_overview(v_club);
  assert v_n = 3, format('ledenbestand verwacht 3, kreeg %s', v_n);
  select entries into v_n from public.club_member_overview(v_club) where display_name = 'Anna';
  assert v_n = 1, 'deelnames per speler kloppen niet';
  select total_spent into v_n from public.club_member_overview(v_club) where display_name = 'Anna';
  assert v_n = 2500, format('uitgegeven verwacht 2500, kreeg %s', v_n);
  select no_email_reason into v_txt from public.club_member_overview(v_club) where display_name = 'Bert';
  assert v_txt = 'geen mail', 'de reden zonder mailadres ontbreekt';

  -- cijfers
  select tournaments into v_n from public.club_stats(v_club, current_date-1, current_date+1);
  assert v_n = 1, format('verwacht 1 afgesloten avond, kreeg %s', v_n);
  select entries into v_n from public.club_stats(v_club, current_date-1, current_date+1);
  assert v_n = 3, 'deelnames kloppen niet';
  select new_players into v_n from public.club_stats(v_club, current_date-1, current_date+1);
  assert v_n = 3, format('alle drie zijn nieuw, kreeg %s', v_n);
  select club_cents into v_n from public.club_stats(v_club, current_date-1, current_date+1);
  assert v_n = 1500, format('clubinkomsten verwacht 1500, kreeg %s', v_n);
  select prize_cents into v_n from public.club_stats(v_club, current_date-1, current_date+1);
  assert v_n = 6000, format('prijzenpot verwacht 6000, kreeg %s', v_n);
  select avg_entries into v_num from public.club_stats(v_club, current_date-1, current_date+1);
  assert v_num = 3.0, format('gemiddeld veld verwacht 3, kreeg %s', v_num);
  select avg_minutes into v_n from public.club_stats(v_club, current_date-1, current_date+1);
  assert v_n between 175 and 185, format('speelduur verwacht ~180 min, kreeg %s', v_n);

  -- buiten de periode
  select tournaments into v_n from public.club_stats(v_club, current_date-400, current_date-300);
  assert v_n = 0, 'buiten de periode hoort er niets te staan';

  -- maandreeks
  select count(*) into v_n from public.club_month_series(v_club, 6);
  assert v_n = 6, format('verwacht 6 maanden, kreeg %s', v_n);
  select sum(entries) into v_n from public.club_month_series(v_club, 6);
  assert v_n = 3, 'de maandreeks telt niet op tot het totaal';

  raise notice 'cluboverzicht OK: ledenbestand, cijfers en maandreeks';
end $$;

-- Rechten: een buitenstaander krijgt niets
do $$
declare v_club uuid; v_geweigerd int := 0;
begin
  insert into clubs (slug,name) values ('t-'||substr(gen_random_uuid()::text,1,12),'Dicht')
  returning id into v_club;
  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);

  begin perform * from public.club_member_overview(v_club);
  exception when insufficient_privilege then v_geweigerd := v_geweigerd + 1; end;
  begin perform * from public.club_stats(v_club, current_date, current_date);
  exception when insufficient_privilege then v_geweigerd := v_geweigerd + 1; end;
  begin perform * from public.club_month_series(v_club, 3);
  exception when insufficient_privilege then v_geweigerd := v_geweigerd + 1; end;

  perform set_config('request.jwt.claim.role','',true);
  perform set_config('request.jwt.claim.sub','',true);
  assert v_geweigerd = 3, format('verwacht 3 weigeringen, kreeg %s', v_geweigerd);
  raise notice 'rechten OK: 3 van 3 geweigerd voor een buitenstaander';
end $$;
rollback;
