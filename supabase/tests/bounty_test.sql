-- Tests voor wat "gewonnen" betekent op een bountyavond.
--
-- Je betaalt de bounty bij het inkopen en je verdient hem terug door mensen
-- uit te schakelen. Een overzicht dat de ene helft wel telt en de andere niet,
-- maakt van elke bountyavond een slechtere avond dan ze was — en het meest
-- bij de speler die het best speelde.
--
-- Wat hier vastligt: overal waar "gewonnen" staat, is dat prijzengeld plus
-- opgehaalde bounties. En "cashes" blijft op het prijzengeld alleen, want een
-- kop pakken is geen in-the-money finish.

begin;

do $$
declare
  v_club uuid; v_tour uuid;
  v_baas uuid := gen_random_uuid();
  v_jager uuid := gen_random_uuid();   -- speelt, pakt koppen
  v_tps uuid[] := array[]::uuid[]; i int;
  v_mij uuid;      -- de tournament_player van de jager
  v_speler uuid;   -- zijn player_id
  v_res record; v_lid record;
  v_inleg int; v_gewonnen int;
begin
  insert into auth.users (id, email) values
    (v_baas,  format('baas-%s@test.be',  substr(v_baas::text, 1, 8))),
    (v_jager, format('jager-%s@test.be', substr(v_jager::text, 1, 8)));

  insert into clubs (slug, name, compliance)
  values ('bt-' || substr(gen_random_uuid()::text, 1, 10), 'Bountytest',
          jsonb_build_object('enforce', 'off'))
  returning id into v_club;
  insert into club_members (club_id, user_id, role) values (v_club, v_baas, 'owner');

  -- €40 inkoop, €5 fee, €20 bounty. Zes spelers.
  insert into tournaments (club_id, name, scheduled_at, status, buyin_cents, fee_cents,
                           bounty_cents, bounty_mode, starting_stack, player_visibility)
  values (v_club, 'Bountyavond', now() - interval '1 day', 'running',
          4000, 500, 2000, 'fixed', 40000, 'public')
  returning id into v_tour;

  for i in 1 .. 6 loop
    v_tps := v_tps || public.floor_add_entry(
      v_tour, null, format('Speler %s', i),
      format('bt%s-%s@test.be', i, substr(gen_random_uuid()::text, 1, 8)));
  end loop;

  -- Speler 6 is onze jager en koppelen we aan een account, zodat my_results
  -- hem terugvindt.
  v_mij := v_tps[6];
  select player_id into v_speler from tournament_players where id = v_mij;
  update players set auth_user_id = v_jager where id = v_speler;

  -- Hij schakelt er twee uit en wordt daarna zelf vierde.
  perform public.floor_eliminate(v_tps[1], v_mij);
  perform public.floor_eliminate(v_tps[2], v_mij);
  perform public.floor_eliminate(v_tps[3], null);
  perform public.floor_eliminate(v_mij,    null);
  perform public.floor_eliminate(v_tps[4], null);
  perform public.floor_finish_tournament(v_tour);

  select * into v_res from tournament_results
   where tournament_id = v_tour and player_id = v_speler;

  assert v_res.knockouts = 2, format('twee koppen verwacht, kreeg %s', v_res.knockouts);
  assert v_res.bounty_cents = 4000,
    format('twee bounties van €20 is €40, de uitslag zegt %s cent', v_res.bounty_cents);
  raise notice 'OK  de opgehaalde bounties staan in de uitslag';

  -- ------------------------------------------------- zijn eigen pagina
  perform set_config('request.jwt.claim.sub', v_jager::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  select * into v_res from public.my_results() where tournament_id = v_tour;
  assert v_res.bounty_cents = 4000,
    format('my_results gaf %s cent bounty in plaats van 4000', v_res.bounty_cents);
  assert v_res.spent_cents = 6500,
    format('inkoop + fee + bounty is €65, my_results zegt %s cent', v_res.spent_cents);

  v_gewonnen := v_res.prize_cents + v_res.bounty_cents;
  assert v_gewonnen - v_res.spent_cents = v_res.prize_cents + 4000 - 6500,
    'het netto klopt niet met prijzengeld plus bounty min inleg';
  raise notice 'OK  op je eigen pagina is gewonnen = prijzengeld (%) + bounty (€40)',
    round(v_res.prize_cents / 100.0, 2);

  -- Zonder de bounty mee te tellen zou deze avond er €40 slechter uitzien.
  -- Dat is het hele punt van migratie 0064.
  assert v_gewonnen > v_res.prize_cents,
    'de bounty voegde niets toe aan wat de avond opbracht';

  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);

  -- ---------------------------------------------------- het ledenbestand
  perform set_config('request.jwt.claim.sub', v_baas::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  select * into v_lid from public.club_member_overview(v_club)
   where player_id = v_speler;
  assert v_lid.total_prize = v_gewonnen,
    format('het ledenbestand zegt %s, zijn eigen pagina %s', v_lid.total_prize, v_gewonnen);
  assert v_lid.total_spent = 6500, 'de inleg in het ledenbestand klopt niet';
  raise notice 'OK  het ledenbestand komt uit op hetzelfde saldo als zijn eigen pagina';

  -- -------------------------------------------------- en het klassement
  select * into v_res from public.club_standings_period(
    v_club, (now() - interval '7 days')::date, (now() + interval '1 day')::date)
   where player_id = v_speler;
  assert v_res.total_prize = v_gewonnen,
    format('het jaarklassement zegt %s in plaats van %s', v_res.total_prize, v_gewonnen);
  raise notice 'OK  het jaar- en maandklassement telt de bounties ook mee';

  -- Vierde van zes zonder prijzengeld is geen cash, hoeveel koppen hij ook
  -- pakte. Dat onderscheid moet blijven staan.
  if (select prize_cents from tournament_results
       where tournament_id = v_tour and player_id = v_speler) = 0 then
    assert v_lid.cashes = 0,
      'een speler zonder prijzengeld werd als cash geteld omdat hij bounties won';
    raise notice 'OK  bounties maken van een vierde plaats geen cash';
  else
    raise notice 'OK  (hij eindigde in de prijzen, de cash-telling is hier niet te meten)';
  end if;

  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);
end $$;

rollback;
