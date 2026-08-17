-- Pokerleague — wie bepaalt de taal van een speler?
--
-- Drie partijen kunnen het zeggen en ze spreken elkaar tegen. De regel die
-- hier bewaakt wordt is: de club mag zetten en bijstellen zolang het profiel
-- van de club is, en zodra de speler een account heeft is het van hem.
--
-- Het geval dat me bijna ontglipte staat als laatste: de spelerspagina roept
-- `claim_my_player` bij elk bezoek aan, zonder argumenten. Zou de taal uit het
-- token dan meetellen, dan draait elk bezoek terug wat de speler zelf instelde.
\set ON_ERROR_STOP on

begin;

do $$
declare
  v_club uuid; v_struct uuid; v_pay uuid; v_tour uuid;
  v_tp uuid; v_p uuid; v_uid uuid;
  v_taal text;
begin
  insert into clubs (slug, name, city, country, locale, timezone)
  values ('t31', 'Testclub 31', 'Aalst', 'BE', 'nl', 'Europe/Brussels') returning id into v_club;

  insert into blind_structures (club_id, name) values (v_club, 'S') returning id into v_struct;
  insert into blind_levels (structure_id, idx, is_break, small_blind, big_blind, ante, duration_s)
  values (v_struct, 0, false, 25, 50, 0, 1200);
  insert into payout_templates (club_id, name, tiers, rounding)
  values (v_club, 'P', '[{"min_entries":2,"max_entries":99,"percentages":[100]}]'::jsonb, 100)
  returning id into v_pay;
  insert into tournaments (club_id, payout_template_id, structure_id, name, scheduled_at,
                           status, player_visibility, buyin_cents, fee_cents,
                           starting_stack, max_reentries)
  values (v_club, v_pay, v_struct, 'Avond', now(), 'running'::tournament_status,
          'public'::visibility, 2000, 0, 20000, 1)
  returning id into v_tour;

  -- --------------------------------------------------------------------- 1 ---
  -- Zonder opgave valt hij terug op de taal van de club, niet op 'nl' uit de
  -- kolomstandaard. Bij een Waalse club is dat het verschil.
  v_tp := public.floor_add_entry(v_tour, null, 'Zonder Opgave', 'zonder@t31.be');
  select p.locale into v_taal from tournament_players tp
  join players p on p.id = tp.player_id where tp.id = v_tp;
  if v_taal <> 'nl' then raise exception 'FOUT: verwacht nl van de club, kreeg %', v_taal; end if;
  raise notice 'OK  zonder opgave krijgt hij de taal van de club';

  -- --------------------------------------------------------------------- 2 ---
  -- Mét opgave wint de floor.
  v_tp := public.floor_add_entry(v_tour, null, 'Waalse Gast', 'waal@t31.be', null, 'fr');
  select tp.player_id into v_p from tournament_players tp where tp.id = v_tp;
  select locale into v_taal from players where id = v_p;
  if v_taal <> 'fr' then raise exception 'FOUT: verwacht fr, kreeg %', v_taal; end if;
  raise notice 'OK  de floor geeft de taal mee en die wordt bewaard';

  -- --------------------------------------------------------------------- 3 ---
  -- Rommel gaat er niet in. Anders valt de mailer stil terug op Nederlands
  -- zonder dat iemand begrijpt waarom.
  if public.norm_locale('NL-be') <> 'nl' then raise exception 'FOUT: NL-be niet herkend'; end if;
  if public.norm_locale('fr_BE') <> 'fr' then raise exception 'FOUT: fr_BE niet herkend'; end if;
  if public.norm_locale('vlaams') is not null then raise exception 'FOUT: vlaams werd geslikt'; end if;
  if public.norm_locale('') is not null then raise exception 'FOUT: leeg werd geslikt'; end if;
  raise notice 'OK  alleen nl, fr en en komen erdoor, ook uit nl-BE en fr_BE';

  -- --------------------------------------------------------------------- 4 ---
  -- Een tweede avond met een andere taal: bijstellen mag, want dit profiel is
  -- nog van de club.
  perform public.floor_add_entry(v_tour, v_p);
  update players set locale = 'nl' where id = v_p;
  v_tp := public.floor_add_entry(v_tour, null, 'Waalse Gast', 'waal@t31.be', null, 'fr');
  select locale into v_taal from players where id = v_p;
  if v_taal <> 'fr' then raise exception 'FOUT: de floor kon niet bijstellen, taal is %', v_taal; end if;
  raise notice 'OK  zolang het profiel van de club is mag de floor bijstellen';

  -- --------------------------------------------------------------------- 5 ---
  -- Maar zodra hij een account heeft, blijft de club eraf.
  insert into auth.users (email) values ('waal@t31.be') returning id into v_uid;
  update players set auth_user_id = v_uid, link_state = 'claimed', locale = 'en' where id = v_p;

  perform public.floor_add_entry(v_tour, null, 'Waalse Gast', 'waal@t31.be', null, 'nl');
  select locale into v_taal from players where id = v_p;
  if v_taal <> 'en' then
    raise exception 'FOUT: de club overschreef de taal van een speler met een account (%)', v_taal;
  end if;
  raise notice 'OK  met een account is de taal van de speler en raakt de club er niet aan';

  -- --------------------------------------------------------------------- 6 ---
  -- En het geval dat bijna misging. De spelerspagina roept claim_my_player bij
  -- elk bezoek aan, zonder argumenten. In het token staat nog 'fr' van bij de
  -- registratie. Zou dat meetellen, dan staat hij na één klik weer op Frans.
  perform set_config('request.jwt.claims',
    json_build_object(
      'sub', v_uid, 'role', 'authenticated', 'email', 'waal@t31.be',
      'user_metadata', json_build_object('locale', 'fr')
    )::text, true);
  perform set_config('request.jwt.claim.sub', v_uid::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  perform public.claim_my_player();
  select locale into v_taal from players where id = v_p;
  if v_taal <> 'en' then
    raise exception 'FOUT: een bezoek aan de spelerspagina draaide de taal terug naar %', v_taal;
  end if;
  raise notice 'OK  een bezoek aan /ik draait de eigen taalkeuze niet terug';

  -- Wél als hij het expliciet meegeeft: dan is het een handeling en geen
  -- neveneffect.
  perform public.claim_my_player(null, null, null, null, 'fr');
  select locale into v_taal from players where id = v_p;
  if v_taal <> 'fr' then raise exception 'FOUT: expliciet meegeven werkte niet, taal is %', v_taal; end if;
  raise notice 'OK  expliciet meegeven verandert de taal wel';

  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.role', '', true);
end $$;

rollback;
