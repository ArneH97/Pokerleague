-- Tests voor het aantal spelers per tafel: 9-max, 8-max, 6-max.
--
-- Het veld staat op het tornooi; tafels die erbij komen erven het, tenzij ze
-- bewust een eigen aantal krijgen (een finaletafel voor tien).

begin;
do $$
declare v_club uuid; v_t uuid; v_tab uuid;
begin
  insert into clubs (slug,name,compliance) values ('tf-'||substr(gen_random_uuid()::text,1,10),'T', jsonb_build_object('enforce','off')) returning id into v_club;
  insert into tournaments (club_id,name,scheduled_at,status,buyin_cents,fee_cents,starting_stack,seats_per_table)
  values (v_club,'8-max',now(),'scheduled',4000,0,40000,8) returning id into v_t;

  assert (select seats_per_table from tournaments where id=v_t) = 8, 'veld niet bewaard';
  raise notice 'OK  spelers per tafel wordt bewaard op het tornooi';

  -- een tafel zonder eigen aantal erft dat van de avond
  insert into tournament_tables (club_id, tournament_id, table_no) values (v_club, v_t, 1) returning id into v_tab;
  assert (select seats from tournament_tables where id=v_tab) = 8,
    format('een nieuwe tafel hoort 8 stoelen te erven, kreeg %s', (select seats from tournament_tables where id=v_tab));
  raise notice 'OK  een nieuwe tafel erft het aantal van de avond';

  -- wie het bewust anders zet, houdt zijn eigen aantal
  insert into tournament_tables (club_id, tournament_id, table_no, seats) values (v_club, v_t, 2, 10) returning id into v_tab;
  assert (select seats from tournament_tables where id=v_tab) = 10, 'een eigen aantal werd overschreven';
  raise notice 'OK  een tafel met een eigen aantal houdt dat';

  -- bijstellen via het bewerkscherm
  perform public.update_tournament(v_t, jsonb_build_object('seats_per_table', 6));
  assert (select seats_per_table from tournaments where id=v_t) = 6, 'bijstellen werkte niet';
  raise notice 'OK  spelers per tafel is bij te stellen na het aanmaken';

  begin
    perform public.update_tournament(v_t, jsonb_build_object('seats_per_table', 12));
    raise exception 'twaalf stoelen werd aanvaard';
  exception when check_violation then
    raise notice 'OK  een onmogelijk aantal stoelen wordt geweigerd';
  end;

  begin
    insert into tournaments (club_id,name,scheduled_at,status,buyin_cents,fee_cents,starting_stack,seats_per_table)
    values (v_club,'Fout',now(),'scheduled',4000,0,40000,14);
    raise exception 'veertien stoelen kwam door de check heen';
  exception when check_violation then
    raise notice 'OK  de databank laat geen tafel van veertien toe';
  end;
end $$;
rollback;
