-- Tests voor migratie 0005: profielen, leeftijd, aanmeldingen, chipcounts,
-- inschrijvingen en deals. Draait in een transactie die terugrolt.

\set ON_ERROR_STOP on
begin;

-- ---------------------------------------------------------------------------
-- Opzet
-- ---------------------------------------------------------------------------

create temporary table _t (k text primary key, v uuid) on commit drop;

do $$
declare
  v_club uuid; v_tour uuid; v_struct uuid; v_user uuid; v_season uuid;
begin
  insert into clubs (slug, name) values ('testclub', 'Testclub') returning id into v_club;
  insert into seasons (club_id, name, starts_on)
  values (v_club, 'Seizoen', current_date) returning id into v_season;
  insert into tournaments (club_id, season_id, name, scheduled_at, status, buyin_cents)
  values (v_club, v_season, 'Testtornooi', now(), 'running', 2000) returning id into v_tour;

  insert into auth.users (email) values ('speler@test.be') returning id into v_user;

  insert into _t values ('club', v_club), ('tour', v_tour), ('user', v_user), ('season', v_season);
end $$;

-- ---------------------------------------------------------------------------
-- 1. Profielvelden
-- ---------------------------------------------------------------------------

do $$
declare
  v_p uuid; v_naam text; v_dubbel boolean := false;
begin
  -- display_name wordt automatisch samengesteld als hij leeg blijft.
  insert into players (display_name, first_name, last_name, username)
  values ('', 'Jan', 'Peeters', 'janp') returning id into v_p;

  select display_name into v_naam from players where id = v_p;
  assert v_naam = 'Jan Peeters', format('display_name werd "%s"', v_naam);

  -- Gebruikersnaam is hoofdletterongevoelig uniek.
  begin
    insert into players (display_name, username) values ('Andere Jan', 'JANP');
  exception when unique_violation then v_dubbel := true;
  end;
  assert v_dubbel, 'gebruikersnaam mocht niet twee keer bestaan';

  -- Vorm wordt afgedwongen.
  v_dubbel := false;
  begin
    insert into players (display_name, username) values ('Rare', 'ab');
  exception when check_violation then v_dubbel := true;
  end;
  assert v_dubbel, 'te korte gebruikersnaam werd toegelaten';

  raise notice 'profielvelden OK';
end $$;

-- ---------------------------------------------------------------------------
-- 2. Leeftijdscontrole
-- ---------------------------------------------------------------------------

do $$
declare
  c record; v_kind uuid; v_volw uuid; v_geblokkeerd boolean := false;
begin
  select (select v from _t where k='club') club, (select v from _t where k='tour') tour into c;

  insert into players (display_name, birthdate)
  values ('Jonge Speler', current_date - interval '16 years') returning id into v_kind;
  insert into players (display_name, birthdate)
  values ('Volwassen Speler', current_date - interval '30 years') returning id into v_volw;

  begin
    insert into tournament_players (club_id, tournament_id, player_id, status)
    values (c.club, c.tour, v_kind, 'active');
  exception when check_violation then v_geblokkeerd := true;
  end;
  assert v_geblokkeerd, 'minderjarige werd toegelaten tot het tornooi';

  -- Volwassene mag wel.
  insert into tournament_players (club_id, tournament_id, player_id, status)
  values (c.club, c.tour, v_volw, 'active');

  -- Onbekende geboortedatum blokkeert niet: schaduwprofielen aan tafel
  -- hebben er vaak geen, de controle blijft dan aan de deur.
  insert into players (display_name) values ('Onbekende Leeftijd') returning id into v_kind;
  insert into tournament_players (club_id, tournament_id, player_id, status)
  values (c.club, c.tour, v_kind, 'active');

  raise notice 'leeftijdscontrole OK';
end $$;

-- ---------------------------------------------------------------------------
-- 3. Aanmeldformulier
-- ---------------------------------------------------------------------------

do $$
declare
  c record; v_signup uuid; v_player uuid; v_player2 uuid;
  v_dubbel boolean := false; v_jong boolean := false;
begin
  select (select v from _t where k='club') club into c;

  insert into player_signups (club_id, first_name, last_name, username, email,
                              birthdate, municipality)
  values (c.club, 'Sofie', 'Maes', 'sofiem', 'sofie@test.be',
          current_date - interval '28 years', 'Aalst')
  returning id into v_signup;

  -- Tweede keer hetzelfde formulier geeft geen tweede aanvraag.
  begin
    insert into player_signups (club_id, first_name, last_name, username, email, birthdate)
    values (c.club, 'Sofie', 'Maes', 'sofiem2', 'SOFIE@test.be', current_date - interval '28 years');
  exception when unique_violation then v_dubbel := true;
  end;
  assert v_dubbel, 'dubbele aanvraag werd toegelaten';

  v_player := public.approve_signup(v_signup);
  assert v_player is not null, 'goedkeuring leverde geen speler op';

  assert (select count(*) from club_players
          where club_id = c.club and player_id = v_player) = 1,
    'speler werd niet aan de club gekoppeld';
  assert (select link_state from players where id = v_player) = 'invited',
    'speler zou op invited moeten staan';
  assert (select municipality from players where id = v_player) = 'Aalst',
    'gemeente werd niet overgenomen';

  -- Nog eens goedkeuren verandert niets en maakt geen dubbele speler.
  v_player2 := public.approve_signup(v_signup);
  assert v_player2 = v_player, 'tweede goedkeuring maakte een andere speler';

  -- Minderjarige aanvraag wordt geweigerd, gemarkeerd én voorzien van reden.
  insert into player_signups (club_id, first_name, last_name, username, email, birthdate)
  values (c.club, 'Te', 'Jong', 'tejong', 'jong@test.be', current_date - interval '15 years')
  returning id into v_signup;

  v_jong := public.approve_signup(v_signup) is null;
  assert v_jong, 'minderjarige aanvraag werd goedgekeurd';
  assert (select status from player_signups where id = v_signup) = 'rejected',
    'geweigerde aanvraag werd niet als rejected gemarkeerd';
  assert (select reject_reason from player_signups where id = v_signup) is not null,
    'geweigerde aanvraag zonder reden';
  assert not exists (select 1 from players where lower(email) = 'jong@test.be'),
    'er werd toch een spelersprofiel aangemaakt voor een minderjarige';

  raise notice 'aanmeldformulier OK';
end $$;

-- ---------------------------------------------------------------------------
-- 4. Bestaande speler hergebruiken over clubs heen
-- ---------------------------------------------------------------------------

do $$
declare
  v_club2 uuid; v_signup uuid; v_player uuid; v_bestaand uuid;
begin
  select id into v_bestaand from players where lower(email) = 'sofie@test.be';

  insert into clubs (slug, name) values ('tweede', 'Tweede Club') returning id into v_club2;
  insert into player_signups (club_id, first_name, last_name, username, email, birthdate)
  values (v_club2, 'Sofie', 'Maes', 'sofie_anders', 'sofie@test.be',
          current_date - interval '28 years')
  returning id into v_signup;

  v_player := public.approve_signup(v_signup);

  assert v_player = v_bestaand,
    'dezelfde persoon kreeg een tweede spelersprofiel in plaats van één gedeeld';
  assert (select count(*) from club_players where player_id = v_player) = 2,
    'speler zou nu bij twee clubs moeten horen';

  raise notice 'gedeelde speleridentiteit OK';
end $$;

-- ---------------------------------------------------------------------------
-- 5. Spelers geven hun eigen stack in
-- ---------------------------------------------------------------------------

do $$
declare
  c record; v_player uuid; v_tp uuid; v_ander uuid; v_tp_ander uuid;
  v_geweigerd int := 0; v_bron text;
begin
  select (select v from _t where k='club') club,
         (select v from _t where k='tour') tour,
         (select v from _t where k='user') usr into c;

  insert into players (display_name, auth_user_id, birthdate)
  values ('Eigen Speler', c.usr, current_date - interval '35 years')
  returning id into v_player;
  insert into club_players (club_id, player_id) values (c.club, v_player);
  insert into tournament_players (club_id, tournament_id, player_id, status, chip_count)
  values (c.club, c.tour, v_player, 'active', 20000) returning id into v_tp;

  insert into players (display_name, birthdate)
  values ('Andere Speler', current_date - interval '35 years') returning id into v_ander;
  insert into tournament_players (club_id, tournament_id, player_id, status, chip_count)
  values (c.club, c.tour, v_ander, 'active', 20000) returning id into v_tp_ander;

  -- Doe alsof we deze speler zijn in een webverzoek.
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', c.usr::text, true);

  -- Eigen chipaantal mag.
  update tournament_players set chip_count = 31500 where id = v_tp;
  select chip_count_by into v_bron from tournament_players where id = v_tp;
  assert v_bron = 'player', format('bron werd "%s" in plaats van player', v_bron);
  assert (select chip_count_updated_at from tournament_players where id = v_tp) is not null,
    'tijdstip van bijwerken ontbreekt';

  -- Zichzelf een betere plaats geven mag niet.
  begin
    update tournament_players set finish_position = 1 where id = v_tp;
  exception when insufficient_privilege then v_geweigerd := v_geweigerd + 1;
  end;

  -- Zichzelf terug actief zetten mag niet.
  begin
    update tournament_players set status = 'withdrawn' where id = v_tp;
  exception when insufficient_privilege then v_geweigerd := v_geweigerd + 1;
  end;

  -- De stack van iemand anders aanpassen mag niet.
  begin
    update tournament_players set chip_count = 1 where id = v_tp_ander;
  exception when insufficient_privilege then v_geweigerd := v_geweigerd + 1;
  end;

  -- Onmogelijke waarden worden geweigerd.
  begin
    update tournament_players set chip_count = -5 where id = v_tp;
  exception when check_violation then v_geweigerd := v_geweigerd + 1;
  end;

  assert v_geweigerd = 4, format('verwacht 4 weigeringen, kreeg %s', v_geweigerd);

  -- Uitgeschakeld: geen stack meer ingeven.
  perform set_config('request.jwt.claim.role', '', true);
  update tournament_players set status = 'eliminated', finish_position = 9 where id = v_tp;

  perform set_config('request.jwt.claim.role', 'authenticated', true);
  v_geweigerd := 0;
  begin
    update tournament_players set chip_count = 99999 where id = v_tp;
  exception when check_violation then v_geweigerd := 1;
  end;
  assert v_geweigerd = 1, 'uitgeschakelde speler kon nog een stack ingeven';

  perform set_config('request.jwt.claim.role', '', true);
  perform set_config('request.jwt.claim.sub', '', true);

  raise notice 'chipcount door spelers OK';
end $$;

-- ---------------------------------------------------------------------------
-- 6. Floor blijft alles mogen, en wordt als bron genoteerd
-- ---------------------------------------------------------------------------

do $$
declare
  c record; v_tp uuid; v_bron text; v_staf uuid;
begin
  select (select v from _t where k='club') club, (select v from _t where k='tour') tour into c;
  select id into v_tp from tournament_players
  where tournament_id = c.tour and status = 'active' limit 1;

  -- Een echte floormedewerker: eigen account, rol bij de club, en een
  -- gewoon webverzoek. Niet serverside, want dan slaat de trigger over.
  insert into auth.users (email) values ('floor@test.be') returning id into v_staf;
  insert into club_members (club_id, user_id, role) values (c.club, v_staf, 'floor');

  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', v_staf::text, true);

  update tournament_players set chip_count = 45000 where id = v_tp;
  select chip_count_by into v_bron from tournament_players where id = v_tp;
  assert v_bron = 'floor', format('bron werd "%s" in plaats van floor', v_bron);

  -- Floor mag wél alles: uitschakelen hoort gewoon te lukken.
  update tournament_players set status = 'eliminated', finish_position = 8 where id = v_tp;

  perform set_config('request.jwt.claim.role', '', true);
  perform set_config('request.jwt.claim.sub', '', true);

  raise notice 'floor-correctie OK';
end $$;

-- ---------------------------------------------------------------------------
-- 7. Inschrijvingen en deals
-- ---------------------------------------------------------------------------

do $$
declare
  c record; v_player uuid; v_dubbel boolean := false;
begin
  select (select v from _t where k='club') club, (select v from _t where k='tour') tour into c;
  select id into v_player from players where display_name = 'Volwassen Speler';

  insert into tournament_registrations (club_id, tournament_id, player_id)
  values (c.club, c.tour, v_player);

  begin
    insert into tournament_registrations (club_id, tournament_id, player_id)
    values (c.club, c.tour, v_player);
  exception when unique_violation then v_dubbel := true;
  end;
  assert v_dubbel, 'dubbele inschrijving werd toegelaten';

  -- Eén openstaand dealvoorstel per tornooi.
  insert into tournament_deals (club_id, tournament_id, method, pool_cents, shares)
  values (c.club, c.tour, 'icm', 50000, '[]'::jsonb);

  v_dubbel := false;
  begin
    insert into tournament_deals (club_id, tournament_id, method, pool_cents, shares)
    values (c.club, c.tour, 'chipchop', 50000, '[]'::jsonb);
  exception when unique_violation then v_dubbel := true;
  end;
  assert v_dubbel, 'tweede openstaand voorstel werd toegelaten';

  -- Na een beslissing mag er wel een nieuw voorstel komen.
  update tournament_deals set status = 'rejected', decided_at = now()
  where tournament_id = c.tour and status = 'proposed';

  insert into tournament_deals (club_id, tournament_id, method, pool_cents, shares)
  values (c.club, c.tour, 'chipchop', 50000, '[]'::jsonb);

  raise notice 'inschrijvingen en deals OK';
end $$;

rollback;
