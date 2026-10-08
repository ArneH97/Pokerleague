-- Tests voor de stoel bij een nieuwe inkoop.
--
-- Aan tafel gebeurt er bij een rebuy niets zichtbaars: de speler schuift niet
-- achteruit, hij legt geld neer en krijgt nieuwe fiches. In het systeem werd
-- zijn stoel bij het uitschakelen leeggemaakt en kwam hij er daarna zonder
-- plaats weer in — en dan klopt de tafelindeling niet meer met de zaal.
--
-- Wat hier vastligt: hij gaat terug op zijn eigen stoel, behalve als iemand
-- anders er intussen zit. Dan is ongeseat het juiste antwoord, want twee
-- mensen op één stoel zetten is erger dan één keer opnieuw moeten seaten.

begin;

do $$
declare
  v_club uuid; v_tour uuid; v_tafel uuid;
  v_a uuid; v_b uuid; v_c uuid;
  v_t int; v_s int;
begin
  insert into clubs (slug, name, compliance)
  values ('st-' || substr(gen_random_uuid()::text, 1, 12), 'Stoeltest',
          jsonb_build_object('enforce','off'))
  returning id into v_club;

  insert into tournaments (club_id, name, scheduled_at, status,
                           buyin_cents, fee_cents, starting_stack, max_reentries, seats_per_table)
  values (v_club, 'Avond', now(), 'running', 4000, 0, 40000, 3, 9)
  returning id into v_tour;

  v_a := public.floor_add_entry(v_tour, null, 'Anja',  format('a-%s@t.be', substr(gen_random_uuid()::text,1,8)));
  v_b := public.floor_add_entry(v_tour, null, 'Bert',  format('b-%s@t.be', substr(gen_random_uuid()::text,1,8)));
  v_c := public.floor_add_entry(v_tour, null, 'Chris', format('c-%s@t.be', substr(gen_random_uuid()::text,1,8)));

  perform public.floor_open_table(v_tour);
  perform public.floor_seat_player(v_a, 1, 3);
  perform public.floor_seat_player(v_b, 1, 5);

  assert (select seat_no from tournament_players where id = v_a) = 3,
    'de opzet klopt niet: Anja hoort op stoel 3 te zitten';

  -- ----------------------------------------- uitschakelen geeft de stoel vrij
  perform public.floor_eliminate(v_a, null);
  assert (select seat_no from tournament_players where id = v_a) is null,
    'de stoel kwam niet vrij bij het uitschakelen';
  assert (select seat_before_exit from tournament_players where id = v_a) = 3,
    'de stoel werd niet onthouden';
  raise notice 'OK  uitschakelen geeft de stoel vrij en onthoudt welke het was';

  -- ------------------------------------------- en een re-entry zet hem terug
  perform public.floor_rebuy(v_a, 'reentry');
  select table_no, seat_no into v_t, v_s from tournament_players where id = v_a;
  assert v_t = 1 and v_s = 3,
    format('Anja hoort terug op tafel 1 stoel 3 te zitten, zit op tafel %s stoel %s', v_t, v_s);
  assert (select status from tournament_players where id = v_a) = 'active',
    'Anja zit weer maar staat niet als actief';
  raise notice 'OK  een re-entry zet de speler terug op zijn eigen stoel';

  -- En het geheugen is opgebruikt: hij zit weer, er valt niets terug te geven.
  assert (select seat_before_exit from tournament_players where id = v_a) is null,
    'de onthouden stoel bleef staan nadat hij weer zat';
  raise notice 'OK  de onthouden stoel wordt opgeruimd zodra hij weer zit';

  -- ------------------------------------- tenzij er iemand anders is gaan zitten
  perform public.floor_eliminate(v_b, null);
  -- Chris neemt de vrijgekomen plaats van Bert.
  perform public.floor_seat_player(v_c, 1, 5);

  perform public.floor_rebuy(v_b, 'reentry');
  assert (select seat_no from tournament_players where id = v_b) is null,
    'Bert werd op een bezette stoel gezet';
  assert (select seat_no from tournament_players where id = v_c) = 5,
    'Chris werd van zijn stoel geduwd';
  raise notice 'OK  is de stoel intussen bezet, dan blijft de speler ongeseat';

  -- --------------------------------- een rechtstreekse rebuy raakt de stoel niet
  -- Hier staat de speler nooit op, dus er valt ook niets terug te zetten.
  select table_no, seat_no into v_t, v_s from tournament_players where id = v_a;
  perform public.floor_rebuy(v_a, 'rebuy');
  assert (select table_no from tournament_players where id = v_a) = v_t
     and (select seat_no  from tournament_players where id = v_a) = v_s,
    'een rechtstreekse rebuy veranderde de stoel';
  raise notice 'OK  een rechtstreekse rebuy laat de stoel staan waar hij staat';
end $$;

rollback;
