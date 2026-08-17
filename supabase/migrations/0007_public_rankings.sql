-- Pokerleague — publieke klassementen met toestemming
--
-- Uitgangspunt: iedereen mag op PokerLeague de klassementen en de actieve
-- tornooien zien, maar uitsluitend met gebruikersnamen. Geen echte namen,
-- geen geboortedatum, geen e-mailadres, geen gemeente.
--
-- Het belangrijkste inzicht hieronder: row level security verbergt RIJEN,
-- geen KOLOMMEN. Een vinkje "deze speler is publiek" zou betekenen dat een
-- bezoeker de hele spelersrij mag lezen, inclusief geboortedatum. Daarom
-- gaat de publieke kant via views die alleen de veilige kolommen bevatten.
-- Wat er niet in de view staat, kan er ook niet uit lekken — ook niet als
-- iemand later per ongeluk de verkeerde query schrijft.

-- ---------------------------------------------------------------------------
-- 1. Toestemming van de speler
-- ---------------------------------------------------------------------------

alter table players
  add column if not exists public_listing        boolean not null default false,
  add column if not exists listing_consent_at    timestamptz,
  add column if not exists listing_consent_source text
    check (listing_consent_source is null
           or listing_consent_source in ('signup', 'profile', 'club_form', 'import'));

comment on column players.public_listing is
  'Mag deze speler onder zijn gebruikersnaam in publieke klassementen verschijnen? Standaard nee: toestemming wordt gevraagd bij registratie.';
comment on column players.listing_consent_at is
  'Wanneer de speler die keuze maakte. Bewaren zodat je later kan aantonen dat er toestemming was.';

-- Legt vast wannéér de keuze veranderde, zonder dat de applicatie eraan hoeft
-- te denken. Wie toestemming intrekt, laat ook dat spoor achter.
create or replace function public.track_listing_consent()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'INSERT' then
    if new.public_listing then
      new.listing_consent_at := coalesce(new.listing_consent_at, now());
    end if;
  elsif new.public_listing is distinct from old.public_listing then
    new.listing_consent_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists players_listing_consent on players;
create trigger players_listing_consent
  before insert or update on players
  for each row execute function public.track_listing_consent();

-- ---------------------------------------------------------------------------
-- 2. Toestemming op het aanmeldformulier
-- ---------------------------------------------------------------------------
-- Wie zich bij een club aanmeldt kruist dit zelf aan. Zonder vinkje speelt
-- hij gewoon mee, alleen verschijnt hij niet in een publieke ranking.

alter table player_signups
  add column if not exists public_listing boolean not null default false;

comment on column player_signups.public_listing is
  'Aangekruist op het aanmeldformulier: mag mijn gebruikersnaam in publieke klassementen?';

-- Neemt de keuze mee bij goedkeuring.
create or replace function public.approve_signup(p_signup_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  s        player_signups%rowtype;
  v_player uuid;
  v_min    int;
begin
  select * into s from player_signups where id = p_signup_id;
  if not found then
    raise exception 'Aanvraag bestaat niet';
  end if;

  if not public.is_service_context()
     and not public.has_club_role(s.club_id, array['owner','admin']::club_role[]) then
    raise exception 'Geen rechten om aanvragen goed te keuren'
      using errcode = 'insufficient_privilege';
  end if;

  if s.status <> 'pending' then
    return s.player_id;
  end if;

  select coalesce((c.compliance->>'min_age')::int, 18) into v_min
  from clubs c where c.id = s.club_id;

  if public.age_on(s.birthdate, public.club_today(s.club_id)) < v_min then
    update player_signups
    set status = 'rejected',
        reject_reason = format('Jonger dan %s jaar', v_min),
        reviewed_at = now(),
        reviewed_by = auth.uid()
    where id = p_signup_id;
    return null;
  end if;

  select id into v_player from players
  where lower(email) = lower(s.email) and merged_into_id is null;

  if v_player is null then
    insert into players (display_name, first_name, last_name, username, email,
                         birthdate, municipality, link_state,
                         public_listing, listing_consent_source)
    values (trim(s.first_name || ' ' || s.last_name), s.first_name, s.last_name,
            s.username, s.email, s.birthdate, s.municipality, 'invited',
            s.public_listing, case when s.public_listing then 'club_form' end)
    returning id into v_player;
  else
    update players set
      first_name   = coalesce(first_name, s.first_name),
      last_name    = coalesce(last_name, s.last_name),
      username     = coalesce(username, s.username),
      birthdate    = coalesce(birthdate, s.birthdate),
      municipality = coalesce(municipality, s.municipality),
      -- Toestemming alleen aanzetten, nooit stilzwijgend intrekken: als hij
      -- bij club A ja zei en bij club B het vakje vergat, blijft ja gelden.
      public_listing = players.public_listing or s.public_listing,
      listing_consent_source = coalesce(players.listing_consent_source,
                                        case when s.public_listing then 'club_form' end)
    where id = v_player;
  end if;

  insert into club_players (club_id, player_id, joined_on)
  values (s.club_id, v_player, current_date)
  on conflict (club_id, player_id) do nothing;

  update player_signups
  set status = 'approved', player_id = v_player, reviewed_at = now(),
      reviewed_by = auth.uid()
  where id = p_signup_id;

  return v_player;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Tornooien staan standaard op publiek
-- ---------------------------------------------------------------------------
-- De keuze verdwijnt uit het aanmaakformulier: elk tornooi hoort op
-- PokerLeague te verschijnen. De kolom blijft bestaan om een testtornooi of
-- een besloten avond alsnog af te kunnen schermen.

alter table tournaments alter column player_visibility set default 'public';

update tournaments set player_visibility = 'public' where player_visibility = 'members';

-- ---------------------------------------------------------------------------
-- 4. De publieke views
-- ---------------------------------------------------------------------------
-- security_invoker staat bewust UIT. Deze views omzeilen dus de RLS van de
-- onderliggende tabellen — dat is precies de bedoeling, want de afscherming
-- zit hier in de kolomkeuze en de WHERE. De basistabellen blijven voor het
-- publiek volledig dicht; wie rechtstreeks `players` bevraagt krijgt niets.

create or replace view public.public_players
with (security_invoker = false) as
select
  p.id,
  -- Nooit de echte naam, tenzij de speler dat apart heeft aangezet.
  case
    when p.public_profile then p.display_name
    else coalesce(nullif(trim(p.username), ''), 'Speler ' || left(p.id::text, 4))
  end as public_name,
  p.country,
  p.avatar_url
from players p
where p.public_listing
  and p.merged_into_id is null;

comment on view public.public_players is
  'Enige manier waarop een buitenstaander een speler ziet. Bevat geen naam, geboortedatum, e-mail of gemeente.';

-- Resultaten van clubs die tekenden, van spelers die toestemden.
-- Bewust zonder prijzengeld: een gebruikersnaam naast een bedrag is een heel
-- ander soort gegeven dan een gebruikersnaam naast een klassering.
create or replace view public.public_results
with (security_invoker = false) as
select
  r.tournament_id,
  r.season_id,
  r.player_id,
  t.club_id,
  c.name        as club_name,
  c.slug        as club_slug,
  t.name        as tournament_name,
  r.position,
  r.entries_total,
  r.knockouts,
  r.points,
  r.finished_at
from tournament_results r
join tournaments t on t.id = r.tournament_id
join clubs c       on c.id = t.club_id
join players p     on p.id = r.player_id
where c.shares_results
  and c.is_active
  and t.player_visibility = 'public'
  and p.public_listing
  and p.merged_into_id is null;

comment on view public.public_results is
  'Publieke uitslagen. Alleen clubs die het delen contractueel hebben aanvaard, en alleen spelers die toestemden. Zonder prijzengeld.';

-- Actieve tornooien voor de publieke pagina: hoeveel spelers, welk level.
-- Geen namen, geen chipcounts — dat is de clubkant.
create or replace view public.public_live_tournaments
with (security_invoker = false) as
select
  t.id,
  t.name,
  t.scheduled_at,
  t.status,
  t.level_idx,
  t.buyin_cents + t.fee_cents as entry_cents,
  c.id   as club_id,
  c.name as club_name,
  c.slug as club_slug,
  c.city as club_city,
  c.logo_url,
  (select count(*) from tournament_players tp where tp.tournament_id = t.id)                        as entries,
  (select count(*) from tournament_players tp where tp.tournament_id = t.id and tp.status = 'active') as players_left
from tournaments t
join clubs c on c.id = t.club_id
where c.shares_results
  and c.is_active
  and t.player_visibility = 'public'
  and t.status in ('scheduled', 'running', 'paused', 'finished');

-- ---------------------------------------------------------------------------
-- 5. Rechten
-- ---------------------------------------------------------------------------

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    grant select on public.public_players           to anon;
    grant select on public.public_results           to anon;
    grant select on public.public_live_tournaments  to anon;
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant select on public.public_players           to authenticated;
    grant select on public.public_results           to authenticated;
    grant select on public.public_live_tournaments  to authenticated;
  end if;
end $$;

-- Een speler mag zijn eigen keuze altijd zien en wijzigen; dat loopt via de
-- bestaande policy players_self_update op de basistabel.
