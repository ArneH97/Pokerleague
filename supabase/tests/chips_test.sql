-- Tests voor "chips in spel": klopt het getal met wat er echt op tafel ligt?
--
-- De aanleiding: het scherm rekende met tellers (zoveel inkopen maal de
-- startstapel) en kende de bonus van de voorinschrijving niet. Sinds een rebuy
-- de stapel vervangt in plaats van erbij te tellen, klopte het helemaal niet
-- meer.
--
-- De vergelijking die deze tests telkens maken: het getal uit het geldregister
-- tegenover de opgetelde stapels van wie er nog zit. Zolang niemand met de
-- hand aan zijn chips zit, horen die twee gelijk te zijn.

begin;

do $$
declare
  v_club uuid; v_tour uuid; v_tp uuid; v_speler uuid;
  v_tps uuid[] := array[]::uuid[]; i int;
  v_verwacht int; v_geteld int;
begin
  insert into clubs (slug, name, compliance)
  values ('ch-' || substr(gen_random_uuid()::text, 1, 12), 'Chiptest',
          jsonb_build_object('enforce','off'))
  returning id into v_club;

  insert into tournaments (club_id, name, scheduled_at, status,
                           buyin_cents, fee_cents, starting_stack,
                           prereg_bonus_stack, addon_stack, addon_cents, max_reentries)
  values (v_club, 'Opening', now(), 'running', 4000, 0, 40000, 5000, 15000, 2000, 5)
  returning id into v_tour;

  -- Drie spelers aan de deur, zonder voorinschrijving.
  for i in 1 .. 3 loop
    v_tps := v_tps || public.floor_add_entry(
      v_tour, null, format('Speler %s', i),
      format('ch%s-%s@test.be', i, substr(gen_random_uuid()::text, 1, 8)));
  end loop;

  assert public.chips_in_play(v_tour) = 120000,
    format('drie startstapels horen 120.000 te zijn, kreeg %s', public.chips_in_play(v_tour));
  raise notice 'OK  drie gewone inschrijvingen geven drie startstapels';

  -- En eentje die vooraf inschreef: die legt 45.000 op tafel, geen 40.000.
  insert into players (display_name, email, link_state)
  values ('Vooraf', format('vooraf-%s@test.be', substr(gen_random_uuid()::text, 1, 8)), 'invited')
  returning id into v_speler;
  insert into tournament_registrations (club_id, tournament_id, player_id)
  values (v_club, v_tour, v_speler);
  v_tp := public.floor_add_entry(v_tour, v_speler);

  assert public.chips_in_play(v_tour) = 165000,
    format('met de bonus erbij hoort het 165.000 te zijn, kreeg %s', public.chips_in_play(v_tour));
  raise notice 'OK  de bonus van de voorinschrijving telt mee in de chips in spel';

  -- De optelsom van de stapels hoort er gelijk aan te zijn.
  select coalesce(sum(chip_count), 0) into v_geteld
  from tournament_players where tournament_id = v_tour and status in ('active', 'registered');
  assert v_geteld = public.chips_in_play(v_tour),
    format('geteld %s tegenover verwacht %s', v_geteld, public.chips_in_play(v_tour));
  raise notice 'OK  het geldregister en de opgetelde stapels komen uit op hetzelfde';

  -- ------------------------------------------------------------------- rebuy
  -- Een speler zakt naar 8.000 en koopt opnieuw in. Er komt 32.000 bij, want
  -- zijn 8.000 verdwijnt van tafel.
  --
  -- Zijn verloren chips gaan naar een tegenstander: aan tafel verdwijnt er
  -- niets, het verhuist. Zonder die tweede regel zou de test iets meten wat
  -- in een echte zaal niet gebeurt.
  update tournament_players set chip_count = chip_count + 32000 where id = v_tps[2];
  update tournament_players set chip_count = 8000 where id = v_tps[1];
  perform public.floor_rebuy(v_tps[1], 'rebuy');

  assert public.chips_in_play(v_tour) = 165000 - 8000 + 40000,
    format('na de rebuy hoort het %s te zijn, kreeg %s', 165000 - 8000 + 40000, public.chips_in_play(v_tour));

  select coalesce(sum(chip_count), 0) into v_geteld
  from tournament_players where tournament_id = v_tour and status in ('active', 'registered');
  assert v_geteld = public.chips_in_play(v_tour),
    format('na de rebuy: geteld %s tegenover verwacht %s', v_geteld, public.chips_in_play(v_tour));
  raise notice 'OK  een rebuy telt alleen het verschil bij, niet een hele stapel';

  -- ------------------------------------------------------------------- addon
  perform public.floor_rebuy(v_tps[2], 'addon');
  select coalesce(sum(chip_count), 0) into v_geteld
  from tournament_players where tournament_id = v_tour and status in ('active', 'registered');
  assert v_geteld = public.chips_in_play(v_tour),
    format('na de addon: geteld %s tegenover verwacht %s', v_geteld, public.chips_in_play(v_tour));
  raise notice 'OK  een addon houdt de twee getallen gelijk';

  -- --------------------------------------------------------- uitschakeling
  -- Wie eruit ligt, telt niet meer mee in de optelsom. Zijn chips zijn naar de
  -- winnaar van die hand gegaan, dus het totaal blijft hetzelfde — de floor
  -- geeft dat door bij het tellen. Hier bootsen we dat na: de chips van de
  -- afvaller gaan naar iemand anders.
  v_verwacht := public.chips_in_play(v_tour);
  update tournament_players set chip_count = chip_count
    + (select coalesce(chip_count, 0) from tournament_players where id = v_tps[2])
  where id = v_tps[3];
  update tournament_players set chip_count = 0 where id = v_tps[2];
  perform public.floor_eliminate(v_tps[2], v_tps[3]);
  assert public.chips_in_play(v_tour) = v_verwacht,
    'een uitschakeling hoort de chips in spel niet te veranderen';
  raise notice 'OK  een uitschakeling verandert de chips in spel niet';

  -- ---------------------------------------------------------------- re-entry
  perform public.floor_rebuy(v_tps[2], 'reentry');
  assert public.chips_in_play(v_tour) = v_verwacht + 40000,
    'een re-entry hoort een volle startstapel bij te leggen';
  raise notice 'OK  een re-entry legt een volle startstapel bij';

  -- -------------------------------------------------- inkoop terugdraaien
  -- Op speler 1, die maar één extra inkoop heeft: zijn rebuy van daarnet, goed
  -- voor 32.000. Bij speler 2 zouden de addon en de re-entry hier hetzelfde
  -- tijdstip dragen — binnen één transactie staat `now()` stil — en dan is het
  -- niet te zeggen welke van de twee "de laatste" is.
  v_verwacht := public.chips_in_play(v_tour);
  perform public.floor_undo_last_buyin(v_tps[1]);
  assert public.chips_in_play(v_tour) = v_verwacht - 32000,
    format('teruggedraaid hoort %s te geven, kreeg %s',
           v_verwacht - 32000, public.chips_in_play(v_tour));
  assert (select chip_count from tournament_players where id = v_tps[1]) = 8000,
    'de stapel van voor de rebuy kwam niet terug';
  raise notice 'OK  een teruggedraaide inkoop telt niet meer mee';

  -- ------------------------------------- wat een speler op zijn gsm intikt
  -- Dit is de kern: het scherm rekent met het geldregister, niet met wat
  -- spelers doorgeven. Iemand die zich vertelt — of zich rijker rekent —
  -- verandert het ijkpunt niet, en dus loopt het verschil zichtbaar op.
  v_verwacht := public.chips_in_play(v_tour);
  select coalesce(sum(chip_count), 0) into v_geteld
  from tournament_players where tournament_id = v_tour and status in ('active', 'registered');

  update tournament_players set chip_count = coalesce(chip_count, 0) + 25000
  where id = v_tps[1];

  assert public.chips_in_play(v_tour) = v_verwacht,
    'wat een speler intikt hoort het ijkpunt niet te verzetten';
  assert (select coalesce(sum(chip_count), 0) from tournament_players
           where tournament_id = v_tour and status in ('active', 'registered'))
         = v_geteld + 25000,
    'de opgetelde stapels horen wél mee te bewegen';
  raise notice 'OK  een speler die zich verrekent, verzet het ijkpunt niet';
end $$;

rollback;
