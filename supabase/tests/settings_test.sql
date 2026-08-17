-- Pokerleague — wie mag de instellingen van een club wijzigen
--
-- Het instellingenscherm controleert zelf niets. Dat is met opzet: de poort
-- staat in de database, zodat er één waarheid is over wie wat mag. Maar dan
-- moet die poort ook echt dichtzitten, en dat is wat hier gecontroleerd wordt.
--
-- Drie rollen, drie verwachtingen:
--
--   * owner en admin mogen alles op dit scherm
--   * floor mag niets ervan — die bedient de avond en verandert niet hoe de
--     punten geteld worden of wat de daglimiet is
--   * een buitenstaander mag de club lezen (de clubgids is publiek) maar niets
--     wijzigen
--
-- Er is één ding dat gemakkelijk over het hoofd gezien wordt en dat hier
-- expliciet staat: RLS weigert een update niet met een foutmelding maar door
-- nul rijen te raken. Een test die alleen kijkt of er geen exception komt,
-- ziet dus niets. Vandaar dat elke controle de waarde daarna terugleest.
\set ON_ERROR_STOP on
begin;

do $$
declare
  v_club  uuid;
  v_owner uuid; v_floor uuid;
  v_pay   uuid; v_rank uuid;
  v_naam  text; v_round int; v_mult numeric;
begin
  insert into clubs (slug, name, city, country, locale, timezone)
  values ('t26', 'Testclub 26', 'Gent', 'BE', 'nl', 'Europe/Brussels')
  returning id into v_club;

  insert into payout_templates (club_id, name, tiers, rounding)
  values (v_club, 'Standaard', '[{"min_entries":2,"max_entries":99,"percentages":[60,40]}]'::jsonb, 100)
  returning id into v_pay;

  insert into ranking_configs (club_id, name, method, params)
  values (v_club, 'Seizoen', 'sqrt_ratio', '{"multiplier": 10}'::jsonb)
  returning id into v_rank;

  insert into auth.users (email) values ('owner@t26.be') returning id into v_owner;
  insert into auth.users (email) values ('floor@t26.be') returning id into v_floor;
  insert into club_members (club_id, user_id, role) values (v_club, v_owner, 'owner');
  insert into club_members (club_id, user_id, role) values (v_club, v_floor, 'floor');

  -- ------------------------------------------------------------- owner ---
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  set local role authenticated;

  update clubs set name = 'Door de eigenaar', public_names = true where id = v_club;
  update payout_templates set rounding = 500 where id = v_pay;
  update ranking_configs set params = '{"multiplier": 12}'::jsonb where id = v_rank;

  reset role;
  select name into v_naam from clubs where id = v_club;
  select rounding into v_round from payout_templates where id = v_pay;
  select (params->>'multiplier')::numeric into v_mult from ranking_configs where id = v_rank;

  if v_naam <> 'Door de eigenaar' then raise exception 'FOUT: de eigenaar kon de clubnaam niet wijzigen'; end if;
  if v_round <> 500 then raise exception 'FOUT: de eigenaar kon de afronding niet wijzigen'; end if;
  if v_mult <> 12 then raise exception 'FOUT: de eigenaar kon de punten niet wijzigen'; end if;
  raise notice 'OK  de eigenaar mag club, prijzenverdeling en punten wijzigen';

  -- ------------------------------------------------------------- floor ---
  perform set_config('request.jwt.claim.sub', v_floor::text, true);
  set local role authenticated;

  -- Geen exception: RLS raakt gewoon nul rijen. Daarom lezen we terug.
  update clubs set name = 'Door de floor' where id = v_club;
  update payout_templates set rounding = 100 where id = v_pay;
  update ranking_configs set params = '{"multiplier": 99}'::jsonb where id = v_rank;
  update clubs set compliance = '{"enforce":"off"}'::jsonb where id = v_club;

  reset role;
  select name into v_naam from clubs where id = v_club;
  select rounding into v_round from payout_templates where id = v_pay;
  select (params->>'multiplier')::numeric into v_mult from ranking_configs where id = v_rank;

  if v_naam <> 'Door de eigenaar' then raise exception 'FOUT: de floor kon de clubnaam wijzigen'; end if;
  if v_round <> 500 then raise exception 'FOUT: de floor kon de prijzenverdeling wijzigen'; end if;
  if v_mult <> 12 then raise exception 'FOUT: de floor kon het puntensysteem wijzigen'; end if;
  if (select compliance->>'enforce' from clubs where id = v_club) = 'off' then
    raise exception 'FOUT: de floor kon het gedoogbeleid uitzetten';
  end if;
  raise notice 'OK  de floor kan niets van dit alles wijzigen';

  -- ---------------------------------------------------- een buitenstaander ---
  perform set_config('request.jwt.claim.role', 'anon', true);
  perform set_config('request.jwt.claim.sub', '', true);
  set local role anon;

  -- De clubgids is publiek, dus lezen mag.
  if (select count(*) from clubs where id = v_club) <> 1 then
    raise exception 'FOUT: een bezoeker kan de clubgids niet lezen';
  end if;

  -- Wijzigen strandt hier al op het niveau eronder: anon heeft nergens
  -- schrijfrecht gekregen, dus Postgres weigert vóór RLS er ook maar aan te
  -- pas komt. Twee sloten op dezelfde deur, en dat is precies de bedoeling.
  begin
    update clubs set name = 'Door een vreemde' where id = v_club;
    reset role;
    raise exception 'FOUT: een buitenstaander kon de club wijzigen';
  exception
    when insufficient_privilege then
      reset role;
      raise notice 'OK  een buitenstaander leest de club maar heeft geen schrijfrecht';
  end;

  select name into v_naam from clubs where id = v_club;
  if v_naam <> 'Door de eigenaar' then raise exception 'FOUT: de clubnaam is toch veranderd'; end if;

  perform set_config('request.jwt.claim.role', '', true);
end $$;

rollback;
