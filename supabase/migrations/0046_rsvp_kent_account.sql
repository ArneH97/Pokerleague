-- Pokerleague — na het inschrijven weten we of er al een account is
--
-- Wie zich vooraf inschrijft kreeg daarna één en dezelfde uitnodiging: "maak
-- je account af". Voor iemand die hier al jaren speelt is dat het verkeerde
-- zinnetje — hij hééft een account, en de knop bracht hem naar een
-- registratieformulier dat hem vertelt dat zijn adres al bezet is. Dat is een
-- doodlopende straat op precies het moment dat hij goedgezind is.
--
-- Daarvoor moet het antwoord van `rsvp_for_tournament` één ding meer dragen
-- dan een status. Vandaar `jsonb` in plaats van `text`:
--
--     {"status": "ok", "has_account": true}
--
-- **Verklapt dit of een adres bestaat?** Ja, en dat is een afweging. Iemand
-- kan een adres intikken en aan het antwoord zien of er een account op staat.
-- Maar hij moet daarvoor een geldige inschrijving voltooien voor een avond
-- die openstaat, en zijn poging komt op de lijst van de floor te staan — een
-- luidruchtige manier om te doen wat het registratieformulier zelf ook al
-- zegt wanneer je een bezet adres intikt. De winst is groter: iemand die al
-- een account heeft, sturen we naar het aanmeldscherm in plaats van tegen een
-- muur.
--
-- `drop` vooraf, want het teruggeeftype van een functie kan je niet wijzigen
-- met `create or replace`.

drop function if exists public.rsvp_for_tournament(uuid, text, text, text, date);

create or replace function public.rsvp_for_tournament(
  p_tournament_id uuid,
  p_first_name    text,
  p_last_name     text,
  p_email         text,
  p_birthdate     date
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  -- Een noodrem, geen zaalcapaciteit. Wie er honderden verzint, loopt hier
  -- tegenaan voordat de tabel vol staat.
  c_max_rsvp constant int := 500;

  t          tournaments;
  v_email    text := lower(nullif(trim(p_email), ''));
  v_first    text := nullif(trim(p_first_name), '');
  v_last     text := nullif(trim(p_last_name), '');
  v_naam     text;
  v_min_age  int;
  v_player   uuid;
  v_acct     boolean := false;
  v_n        int;
begin
  select * into t from tournaments where id = p_tournament_id;
  if not found or t.status <> 'scheduled' or t.scheduled_at <= now() then
    return jsonb_build_object('status', 'closed', 'has_account', false);
  end if;

  if v_first is null and v_last is null then
    return jsonb_build_object('status', 'bad_name', 'has_account', false);
  end if;
  v_naam := trim(coalesce(v_first, '') || ' ' || coalesce(v_last, ''));

  if v_email is null
     or v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[a-z]{2,}$' then
    return jsonb_build_object('status', 'bad_email', 'has_account', false);
  end if;

  v_min_age := coalesce((select (c.compliance ->> 'min_age')::int
                         from clubs c where c.id = t.club_id), 18);
  if p_birthdate is null
     or public.age_on(p_birthdate, public.club_today(t.club_id)) < v_min_age then
    return jsonb_build_object('status', 'too_young', 'has_account', false);
  end if;

  select count(*) into v_n
  from tournament_registrations r
  where r.tournament_id = t.id and r.cancelled_at is null;
  if v_n >= c_max_rsvp then
    return jsonb_build_object('status', 'full', 'has_account', false);
  end if;

  select id, auth_user_id is not null into v_player, v_acct
  from players
  where lower(email) = v_email and merged_into_id is null;

  if v_player is null then
    v_acct := false;
    insert into players (display_name, first_name, last_name, email, birthdate,
                         link_state, locale)
    values (v_naam, v_first, v_last, v_email, p_birthdate, 'invited',
            coalesce((select c.locale from clubs c where c.id = t.club_id), 'nl'))
    returning id into v_player;
  else
    update players
    set first_name = coalesce(first_name, v_first),
        last_name  = coalesce(last_name,  v_last),
        birthdate  = coalesce(birthdate,  p_birthdate)
    where id = v_player;
  end if;

  insert into club_players (club_id, player_id, joined_on)
  values (t.club_id, v_player, current_date)
  on conflict (club_id, player_id) do nothing;

  perform public.queue_invite(t.club_id, v_player);

  if exists (
    select 1 from tournament_registrations r
    where r.tournament_id = t.id and r.player_id = v_player
      and r.cancelled_at is null
  ) then
    return jsonb_build_object('status', 'already', 'has_account', v_acct);
  end if;

  insert into tournament_registrations (club_id, tournament_id, player_id)
  values (t.club_id, t.id, v_player)
  on conflict (tournament_id, player_id) do update
    set cancelled_at = null;

  return jsonb_build_object('status', 'ok', 'has_account', v_acct);
end;
$$;

comment on function public.rsvp_for_tournament(uuid, text, text, text, date) is
  'Schrijft iemand vooraf in voor een avond, zonder dat hij een account nodig heeft. Geeft {status, has_account} terug zodat het scherm weet of het naar registreren of naar aanmelden moet wijzen.';

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    revoke all on function public.rsvp_for_tournament(uuid, text, text, text, date) from public;
    grant execute on function public.rsvp_for_tournament(uuid, text, text, text, date)
      to anon, authenticated, service_role;
  end if;
end $$;
