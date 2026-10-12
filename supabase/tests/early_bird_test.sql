-- Tests voor de early bird aan de deur en het intrekken van een inschrijving.
--
-- Wat hier vastligt is vooral één ding dat je met de hand nooit volhoudt:
-- chips bijgeven en "chips in spel" uit elkaar laten lopen. Elke beweging
-- hieronder wordt daarom twee keer gemeten — op de stapel van de speler én op
-- het totaal dat het zaalscherm toont.

begin;

-- ---------------------------------------------------------------------------
-- De schakelaar
-- ---------------------------------------------------------------------------

do $$
declare
  v_club uuid; v_t uuid;
  v_baas uuid := gen_random_uuid();
  v_tp uuid; v_tp2 uuid;
  v_speler uuid;
  v_chips int; v_in_spel int; v_bonus int;
begin
  insert into auth.users (id, email) values (v_baas, format('eb-%s@test.be', substr(v_baas::text,1,8)));

  insert into clubs (slug, name, compliance)
  values ('eb-' || substr(gen_random_uuid()::text, 1, 10), 'Earlybirdtest',
          jsonb_build_object('enforce', 'off'))
  returning id into v_club;
  insert into club_members (club_id, user_id, role) values (v_club, v_baas, 'owner');

  insert into tournaments (club_id, name, scheduled_at, status,
                           buyin_cents, fee_cents, starting_stack,
                           prereg_bonus_stack, player_visibility)
  values (v_club, 'Openingsavond', now(), 'running', 3000, 0, 40000, 5000, 'public')
  returning id into v_t;

  -- Iemand die niets invulde en gewoon aan de deur staat.
  v_tp := public.floor_add_entry(v_t, null, 'Walk In',
                                 format('eb1-%s@test.be', substr(gen_random_uuid()::text, 1, 8)));

  select chip_count, prereg_bonus into v_chips, v_bonus
  from tournament_players where id = v_tp;
  assert v_chips = 40000, format('zonder voorinschrijving hoort 40000, kreeg %s', v_chips);
  assert v_bonus = 0, format('zonder voorinschrijving hoort bonus 0, stond %s', v_bonus);
  assert public.chips_in_play(v_t) = 40000,
    format('chips in spel hoort 40000, stond %s', public.chips_in_play(v_t));
  raise notice 'OK  wie niet vooraf inschreef krijgt de startstapel en geen bonus';

  -- De floor zet de bonus alsnog aan.
  perform set_config('request.jwt.claim.sub', v_baas::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  assert public.floor_grant_prereg_bonus(v_tp) = 5000,
    'de knop hoort de gegeven bonus terug te geven';

  select chip_count, prereg_bonus into v_chips, v_bonus
  from tournament_players where id = v_tp;
  v_in_spel := public.chips_in_play(v_t);
  assert v_chips = 45000, format('na de bonus hoort 45000, kreeg %s', v_chips);
  assert v_bonus = 5000, format('de bonus hoort vastgelegd te staan, stond %s', v_bonus);
  assert v_in_spel = 45000, format('chips in spel hoort mee te stijgen naar 45000, stond %s', v_in_spel);
  raise notice 'OK  de bonus komt zowel op de stapel als in "chips in spel"';

  -- Twee keer drukken mag niet twee keer geven. Dit is de hele reden dat er
  -- een kolom bij moest.
  perform public.floor_grant_prereg_bonus(v_tp);
  select chip_count into v_chips from tournament_players where id = v_tp;
  assert v_chips = 45000, format('twee keer drukken gaf %s in plaats van 45000', v_chips);
  assert public.chips_in_play(v_t) = 45000, 'twee keer drukken telde dubbel in chips in spel';
  raise notice 'OK  twee keer drukken geeft niet twee keer chips';

  -- Er is geen weg terug, en dat hoort ook zo te blijven: de oude schakelaar
  -- met twee richtingen mag niet meer bestaan.
  assert not exists (
    select 1 from pg_proc where proname = 'floor_set_prereg_bonus'
  ), 'de schakelaar met twee richtingen staat er nog';
  raise notice 'OK  de bonus kan niet meer weggehaald worden';

  -- Wie vooraf inschreef krijgt hem van de trigger, en de schakelaar weet dat.
  insert into players (display_name, email, link_state)
  values ('Vroege Vogel', format('eb2-%s@test.be', substr(gen_random_uuid()::text, 1, 8)), 'invited')
  returning id into v_speler;
  insert into club_players (club_id, player_id, joined_on) values (v_club, v_speler, current_date);
  insert into tournament_registrations (club_id, tournament_id, player_id)
  values (v_club, v_t, v_speler);

  v_tp2 := public.floor_add_entry(v_t, v_speler);
  select chip_count, prereg_bonus into v_chips, v_bonus
  from tournament_players where id = v_tp2;
  assert v_chips = 45000, format('een voorinschrijver hoort met 45000 te beginnen, kreeg %s', v_chips);
  assert v_bonus = 5000, format('de trigger hoort de bonus vast te leggen, stond %s', v_bonus);
  raise notice 'OK  de trigger legt vast wat hij geeft';

  perform public.floor_grant_prereg_bonus(v_tp2);
  select chip_count into v_chips from tournament_players where id = v_tp2;
  assert v_chips = 45000,
    format('de knop gaf een voorinschrijver nog eens chips: %s', v_chips);
  raise notice 'OK  de knop telt niet bovenop wat de trigger al gaf';
end $$;

-- ---------------------------------------------------------------------------
-- Waar de schakelaar nee zegt
-- ---------------------------------------------------------------------------

do $$
declare
  v_club uuid; v_t uuid; v_tz uuid;
  v_baas uuid := gen_random_uuid();
  v_tp uuid; v_tp_zonder uuid; v_tp_rebuy uuid; v_tp_addon uuid;
begin
  -- Vorig blok liet zijn aanmelding in de transactie staan; die hoort hier
  -- niet te gelden. Leeg betekent servercontext, zoals een migratie.
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);

  insert into auth.users (id, email) values (v_baas, format('ebn-%s@test.be', substr(v_baas::text,1,8)));

  insert into clubs (slug, name, compliance)
  values ('ebn-' || substr(gen_random_uuid()::text, 1, 10), 'Neetest',
          jsonb_build_object('enforce', 'off'))
  returning id into v_club;
  insert into club_members (club_id, user_id, role) values (v_club, v_baas, 'owner');

  insert into tournaments (club_id, name, scheduled_at, status,
                           buyin_cents, fee_cents, starting_stack,
                           prereg_bonus_stack, player_visibility)
  values (v_club, 'Met bonus', now(), 'running', 3000, 0, 40000, 5000, 'public')
  returning id into v_t;

  insert into tournaments (club_id, name, scheduled_at, status,
                           buyin_cents, fee_cents, starting_stack,
                           prereg_bonus_stack, player_visibility)
  values (v_club, 'Zonder bonus', now(), 'running', 3000, 0, 40000, 0, 'public')
  returning id into v_tz;

  v_tp := public.floor_add_entry(v_t, null, 'Uitvaller',
                                 format('ebn1-%s@test.be', substr(gen_random_uuid()::text, 1, 8)));
  v_tp_zonder := public.floor_add_entry(v_tz, null, 'Geen Bonus',
                                 format('ebn2-%s@test.be', substr(gen_random_uuid()::text, 1, 8)));

  perform set_config('request.jwt.claim.sub', v_baas::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  -- Een avond zonder bonus hoort het te zeggen in plaats van niets te doen.
  begin
    perform public.floor_grant_prereg_bonus(v_tp_zonder);
    assert false, 'een avond zonder bonus liet de knop toch toe';
  exception when check_violation then
    raise notice 'OK  een avond zonder bonus weigert de knop';
  end;

  -- Iemand die eruit ligt: zijn chips tellen niet meer mee, dus chips bijgeven
  -- zou alleen het totaal vervuilen.
  perform public.floor_eliminate(v_tp, null);
  begin
    perform public.floor_grant_prereg_bonus(v_tp);
    assert false, 'een uitgeschakelde speler kreeg toch bonuschips';
  exception when check_violation then
    raise notice 'OK  een uitgeschakelde speler krijgt geen bonus meer';
  end;

  -- Enkel bij de eerste inkoop: wie al opnieuw inkocht is te laat.
  v_tp_rebuy := public.floor_add_entry(v_t, null, 'Al Ingekocht',
                                 format('ebn3-%s@test.be', substr(gen_random_uuid()::text, 1, 8)));
  perform public.floor_rebuy(v_tp_rebuy, 'rebuy');
  begin
    perform public.floor_grant_prereg_bonus(v_tp_rebuy);
    assert false, 'een speler met een rebuy kreeg de early bird alsnog';
  exception when check_violation then
    raise notice 'OK  na een tweede inkoop kan de early bird niet meer';
  end;

  -- En een addon telt net zo goed als tweede inkoop.
  v_tp_addon := public.floor_add_entry(v_t, null, 'Addon Gekocht',
                                 format('ebn4-%s@test.be', substr(gen_random_uuid()::text, 1, 8)));
  perform public.floor_rebuy(v_tp_addon, 'addon');
  begin
    perform public.floor_grant_prereg_bonus(v_tp_addon);
    assert false, 'een speler met een addon kreeg de early bird alsnog';
  exception when check_violation then
    raise notice 'OK  een addon sluit de early bird ook uit';
  end;
end $$;

-- ---------------------------------------------------------------------------
-- Een inschrijving intrekken
-- ---------------------------------------------------------------------------

do $$
declare
  v_club uuid; v_t uuid;
  v_baas uuid := gen_random_uuid();
  v_speler uuid; v_tp uuid; v_tp_b uuid;
  v_in_spel int; v_pot int;
begin
  -- Vorig blok liet zijn aanmelding in de transactie staan; die hoort hier
  -- niet te gelden. Leeg betekent servercontext, zoals een migratie.
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);

  insert into auth.users (id, email) values (v_baas, format('an-%s@test.be', substr(v_baas::text,1,8)));

  insert into clubs (slug, name, compliance)
  values ('an-' || substr(gen_random_uuid()::text, 1, 10), 'Annuleertest',
          jsonb_build_object('enforce', 'off'))
  returning id into v_club;
  insert into club_members (club_id, user_id, role) values (v_club, v_baas, 'owner');

  insert into tournaments (club_id, name, scheduled_at, status,
                           buyin_cents, fee_cents, starting_stack,
                           prereg_bonus_stack, player_visibility)
  values (v_club, 'Annuleeravond', now(), 'running', 3000, 500, 40000, 5000, 'public')
  returning id into v_t;

  -- Iemand die vooraf inschreef, aan tafel kwam, en dan toch niet meedoet.
  insert into players (display_name, email, link_state)
  values ('Toch Niet', format('an1-%s@test.be', substr(gen_random_uuid()::text, 1, 8)), 'invited')
  returning id into v_speler;
  insert into club_players (club_id, player_id, joined_on) values (v_club, v_speler, current_date);
  insert into tournament_registrations (club_id, tournament_id, player_id)
  values (v_club, v_t, v_speler);

  v_tp := public.floor_add_entry(v_t, v_speler);
  v_tp_b := public.floor_add_entry(v_t, null, 'Blijft Zitten',
                                 format('an2-%s@test.be', substr(gen_random_uuid()::text, 1, 8)));

  v_in_spel := public.chips_in_play(v_t);
  select coalesce(sum(amount_cents), 0) into v_pot
  from buyins where tournament_id = v_t and not is_void;
  assert v_in_spel = 85000, format('opzet: 45000 + 40000 verwacht, stond %s', v_in_spel);
  -- `amount_cents` is wat naar de prijzenpot gaat; de rake staat apart.
  assert v_pot = 6000, format('opzet: 2 x 3000 in de pot verwacht, stond %s', v_pot);

  perform set_config('request.jwt.claim.sub', v_baas::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  perform public.floor_remove_entry(v_tp);

  assert public.chips_in_play(v_t) = 40000,
    format('na het intrekken hoort 40000 over te blijven, stond %s', public.chips_in_play(v_t));
  select coalesce(sum(amount_cents), 0) into v_pot
  from buyins where tournament_id = v_t and not is_void;
  assert v_pot = 3000, format('na het intrekken hoort 3000 over te blijven, stond %s', v_pot);
  raise notice 'OK  intrekken haalt zowel de chips als het geld uit het spel';

  -- En hij staat weer op de lijst van wie er verwacht wordt, want hij schreef
  -- zich nooit uit.
  assert exists (
    select 1 from tournament_registrations
    where tournament_id = v_t and player_id = v_speler and cancelled_at is null
  ), 'de voorinschrijving kwam niet terug na het intrekken';
  raise notice 'OK  zijn voorinschrijving staat weer open';
end $$;

-- ---------------------------------------------------------------------------
-- Intrekken mag geen bounty van iemand anders afpakken
-- ---------------------------------------------------------------------------

do $$
declare
  v_club uuid; v_t uuid; v_t_zonder uuid;
  v_baas uuid := gen_random_uuid();
  v_slachtoffer uuid; v_moordenaar uuid;
  v_s2 uuid; v_m2 uuid;
  v_melding text;
begin
  -- Vorig blok liet zijn aanmelding in de transactie staan; die hoort hier
  -- niet te gelden. Leeg betekent servercontext, zoals een migratie.
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);

  insert into auth.users (id, email) values (v_baas, format('bo-%s@test.be', substr(v_baas::text,1,8)));

  insert into clubs (slug, name, compliance)
  values ('bo-' || substr(gen_random_uuid()::text, 1, 10), 'Bountytest',
          jsonb_build_object('enforce', 'off'))
  returning id into v_club;
  insert into club_members (club_id, user_id, role) values (v_club, v_baas, 'owner');

  insert into tournaments (club_id, name, scheduled_at, status,
                           buyin_cents, fee_cents, bounty_cents, bounty_mode,
                           starting_stack, player_visibility)
  values (v_club, 'Bountyavond', now(), 'running', 2000, 500, 1000, 'progressive',
          40000, 'public')
  returning id into v_t;

  insert into tournaments (club_id, name, scheduled_at, status,
                           buyin_cents, fee_cents, starting_stack, player_visibility)
  values (v_club, 'Gewone avond', now(), 'running', 3000, 0, 40000, 'public')
  returning id into v_t_zonder;

  v_slachtoffer := public.floor_add_entry(v_t, null, 'Eruit Gespeeld',
                                 format('bo1-%s@test.be', substr(gen_random_uuid()::text, 1, 8)));
  v_moordenaar := public.floor_add_entry(v_t, null, 'Killer Keske',
                                 format('bo2-%s@test.be', substr(gen_random_uuid()::text, 1, 8)));

  perform public.floor_eliminate(v_slachtoffer, v_moordenaar);

  perform set_config('request.jwt.claim.sub', v_baas::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  begin
    perform public.floor_remove_entry(v_slachtoffer);
    assert false, 'een speler met een opgeëiste bounty werd toch weggehaald';
  exception when check_violation then
    v_melding := sqlerrm;
    assert v_melding like '%Killer Keske%',
      format('de melding hoort te zeggen wie de bounty kreeg, stond: %s', v_melding);
    raise notice 'OK  intrekken weigert en noemt wie de bounty kreeg';
  end;

  -- Draai de uitschakeling terug en het mag weer. Dat is de uitweg die de
  -- melding aanwijst, en die hoort te werken.
  perform public.floor_undo_elimination(v_slachtoffer);
  perform public.floor_remove_entry(v_slachtoffer);
  assert not exists (select 1 from tournament_players where id = v_slachtoffer),
    'na het terugdraaien van de uitschakeling lukte het intrekken nog niet';
  raise notice 'OK  na het terugdraaien van de uitschakeling mag het wel';

  -- Op een avond zonder bounty verandert er niets: daar blijft de knop voor de
  -- man die zichzelf per ongeluk uitschakelde gewoon werken.
  v_s2 := public.floor_add_entry(v_t_zonder, null, 'Per Ongeluk',
                                 format('bo3-%s@test.be', substr(gen_random_uuid()::text, 1, 8)));
  v_m2 := public.floor_add_entry(v_t_zonder, null, 'Iemand Anders',
                                 format('bo4-%s@test.be', substr(gen_random_uuid()::text, 1, 8)));
  perform public.floor_eliminate(v_s2, v_m2);
  perform public.floor_remove_entry(v_s2);
  assert not exists (select 1 from tournament_players where id = v_s2),
    'op een avond zonder bounty werd het intrekken onterecht geweigerd';
  raise notice 'OK  zonder bounty blijft intrekken na een uitschakeling mogelijk';
end $$;

rollback;
