-- Tests voor wat een rebuy, een re-entry en een addon met de stapel doen.
--
-- De aanleiding: een rebuy telde een startstapel bíj de huidige stapel op, en
-- wie vooraf had ingeschreven hield daardoor ook zijn bonuschips na elke
-- nieuwe inkoop.

begin;

do $$
declare
  v_club uuid; v_tour uuid; v_tp uuid; v_ander uuid;
  v_speler uuid; v_tps uuid[] := array[]::uuid[]; i int;
begin
  insert into clubs (slug, name, compliance)
  values ('rb-' || substr(gen_random_uuid()::text, 1, 12), 'Rebuytest',
          jsonb_build_object('enforce','off'))
  returning id into v_club;

  insert into tournaments (club_id, name, scheduled_at, status,
                           buyin_cents, fee_cents, starting_stack,
                           prereg_bonus_stack, addon_stack, addon_cents, max_reentries)
  values (v_club, 'Opening', now(), 'running', 4000, 0, 40000, 5000, 15000, 2000, 5)
  returning id into v_tour;

  -- ------------------------------------------------- iemand die vooraf inschreef
  insert into players (display_name, email, link_state)
  values ('Vooraf', format('vooraf-%s@test.be', substr(gen_random_uuid()::text, 1, 8)), 'invited')
  returning id into v_speler;
  insert into tournament_registrations (club_id, tournament_id, player_id)
  values (v_club, v_tour, v_speler);

  v_tp := public.floor_add_entry(v_tour, v_speler);
  assert (select chip_count from tournament_players where id = v_tp) = 45000,
    format('wie vooraf inschreef hoort met 45.000 te beginnen, kreeg %s',
           (select chip_count from tournament_players where id = v_tp));
  raise notice 'OK  de bonus van de voorinschrijving komt er bij de eerste inkoop bij';

  -- ------------------------------------------------------------------- rebuy
  update tournament_players set chip_count = 8000 where id = v_tp;
  perform public.floor_rebuy(v_tp, 'rebuy');
  assert (select chip_count from tournament_players where id = v_tp) = 40000,
    format('een rebuy hoort de stapel op 40.000 te zetten, werd %s',
           (select chip_count from tournament_players where id = v_tp));
  raise notice 'OK  een rebuy zet de stapel op de startstapel en telt niet op';

  -- En de bonus komt er geen tweede keer bij, ook al staat de inschrijving er
  -- nog: 40.000 en niet 45.000. Dat is de vorige assert al, maar dit is de
  -- reden dat ze er staat.
  assert (select chip_count from tournament_players where id = v_tp) <> 45000,
    'de bonuschips van de voorinschrijving telden mee bij de rebuy';
  raise notice 'OK  de bonuschips tellen niet mee bij een rebuy';

  -- De inkoop staat wel gewoon in het geldregister.
  assert (select count(*) from buyins where tournament_player_id = v_tp and kind = 'rebuy' and not is_void) = 1,
    'de rebuy werd niet als inkoop geboekt';
  assert (select rebuys_used from tournament_players where id = v_tp) = 1,
    'de rebuyteller klopt niet';
  raise notice 'OK  de rebuy staat in het geldregister en op de teller';

  -- ------------------------------------------------------ rebuy boven de startstapel
  update tournament_players set chip_count = 60000 where id = v_tp;
  begin
    perform public.floor_rebuy(v_tp, 'rebuy');
    raise exception 'een rebuy boven de startstapel werd aanvaard';
  exception when check_violation then
    raise notice 'OK  een rebuy weigert als hij de stapel zou verkleinen';
  end;
  assert (select chip_count from tournament_players where id = v_tp) = 60000,
    'de geweigerde rebuy heeft toch aan de stapel gezeten';

  -- ------------------------------------------------- een rebuy terugdraaien
  -- Verkeerde naam aangeklikt. De stapel hoort terug te staan zoals hij was,
  -- en niet op nul: een rebuy overschrijft de stapel, dus er valt niets meer
  -- van af te trekken.
  update tournament_players set chip_count = 12500 where id = v_tp;
  perform public.floor_rebuy(v_tp, 'rebuy');
  assert (select chip_count from tournament_players where id = v_tp) = 40000,
    'de rebuy zette de stapel niet op de startstapel';
  perform public.floor_undo_last_buyin(v_tp);
  assert (select chip_count from tournament_players where id = v_tp) = 12500,
    format('terugdraaien hoort 12.500 terug te zetten, werd %s',
           (select chip_count from tournament_players where id = v_tp));
  assert (select rebuys_used from tournament_players where id = v_tp) = 1,
    'de teruggedraaide rebuy telt nog mee op de teller';
  raise notice 'OK  een rebuy terugdraaien zet de oude stapel terug';

  -- --------------------------------------------------------------------- addon
  -- Een addon is wél iets dat erbij komt: extra chips bovenop wat je hebt.
  perform public.floor_rebuy(v_tp, 'addon');
  assert (select chip_count from tournament_players where id = v_tp) = 27500,
    format('een addon hoort er 15.000 bij te tellen bovenop de 12.500, werd %s',
           (select chip_count from tournament_players where id = v_tp));
  raise notice 'OK  een addon telt wel op bij de huidige stapel';

  -- ------------------------------------------------------------------ re-entry
  update tournament_players set chip_count = 0, status = 'eliminated',
    finish_position = 9, eliminated_at = now() where id = v_tp;
  perform public.floor_rebuy(v_tp, 'reentry');
  assert (select chip_count from tournament_players where id = v_tp) = 40000,
    'een re-entry hoort een verse startstapel te geven, zonder bonus';
  assert (select status from tournament_players where id = v_tp) = 'active',
    'een re-entry bracht de speler niet terug in het veld';
  raise notice 'OK  een re-entry geeft een verse startstapel zonder bonus';

  -- ---------------------------------------- de eindplaatsen na een re-entry
  for i in 1 .. 6 loop
    v_tps := v_tps || public.floor_add_entry(
      v_tour, null, format('Speler %s', i),
      format('rb%s-%s@test.be', i, substr(gen_random_uuid()::text, 1, 8)));
  end loop;

  -- Zeven deelnemers in totaal. Twee vallen af: plaats 7 en plaats 6.
  perform public.floor_eliminate(v_tps[6], null);
  perform public.floor_eliminate(v_tps[5], null);
  assert (select finish_position from tournament_players where id = v_tps[6]) = 7,
    'de eerste afvaller van zeven hoort zevende te zijn';

  -- De laatste afvaller koopt zich terug in. Dan is er nog één afvaller over,
  -- en die is van zeven deelnemers de laatste.
  perform public.floor_rebuy(v_tps[5], 'reentry');
  assert (select finish_position from tournament_players where id = v_tps[6]) = 7,
    format('na de re-entry hoort de overblijvende afvaller zevende te blijven, staat op %s',
           (select finish_position from tournament_players where id = v_tps[6]));
  assert (select finish_position from tournament_players where id = v_tps[5]) is null,
    'de teruggekeerde speler houdt een eindplaats';
  raise notice 'OK  een re-entry laat de plaats van de andere afvallers kloppen';
end $$;

rollback;
