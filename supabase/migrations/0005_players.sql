-- Pokerleague — spelersprofielen, inschrijvingen, chipcounts en deals
--
-- Uitgangspunt dat de rest van dit bestand verklaart: een account is nooit
-- een voorwaarde om te spelen. De floor kan altijd iemand op naam aan tafel
-- zetten. Een account voegt daar zelf inschrijven en je eigen stack ingeven
-- aan toe. Zo kan een openingsavond niet stuklopen op een lid dat zijn mail
-- niet heeft gevonden.

-- ---------------------------------------------------------------------------
-- 0. Twee gezichten op één database
-- ---------------------------------------------------------------------------
-- De clubomgeving (eigen logo, eigen kleuren, eigen ledenbestand, eigen klok)
-- en het spelersplatform PokerLeague delen dezelfde tabellen. Wat een club
-- ziet is altijd afgebakend door club_id en RLS; wat PokerLeague toont is de
-- doorsnede van clubs die hun resultaten delen én spelers die dat zelf
-- hebben aangezet.
--
-- Dat zijn bewust twee aparte toestemmingen. De club tekent dat resultaten
-- naar het platform mogen (shares_results). Maar een club kan niet namens
-- een speler beslissen dat diens naam op een openbare nationale ranking komt
-- — dat is een persoonsgegeven en die knop zit bij de speler zelf
-- (players.public_profile). Zonder dat onderscheid staat er straks een
-- ranking online waar iemand nooit toestemming voor gaf.

alter table clubs
  add column if not exists primary_color            text,
  add column if not exists custom_domain            text,
  add column if not exists shares_results           boolean not null default false,
  add column if not exists shares_results_agreed_at timestamptz,
  add column if not exists shares_results_agreed_by text;

create unique index if not exists clubs_custom_domain_unique
  on clubs (lower(custom_domain)) where custom_domain is not null;

comment on column clubs.shares_results is
  'Contractueel: mogen de resultaten van deze club mee in PokerLeague? Los van de toestemming van de speler zelf.';
comment on column clubs.custom_domain is
  'Eigen domein of subdomein van de club. Bepaalt welke clubomgeving een bezoeker te zien krijgt.';

-- ---------------------------------------------------------------------------
-- 1. Profielvelden
-- ---------------------------------------------------------------------------

alter table players
  add column if not exists first_name   text,
  add column if not exists last_name    text,
  add column if not exists username     text,
  add column if not exists birthdate    date,
  add column if not exists municipality text;

-- Gebruikersnaam is platformbreed uniek: hij is straks de identiteit over
-- clubs heen. Hoofdletterongevoelig, want niemand onthoudt of hij zich met
-- "Jan" of "jan" registreerde.
create unique index if not exists players_username_unique
  on players (lower(username)) where username is not null and merged_into_id is null;

alter table players
  drop constraint if exists players_username_format;
alter table players
  add constraint players_username_format
  check (username is null or username ~ '^[a-zA-Z0-9._-]{3,24}$');

comment on column players.birthdate is
  'Nodig voor de leeftijdscontrole uit het gedoogbeleid. Niet tonen aan andere spelers.';
comment on column players.municipality is
  'Bewust alleen gemeente, geen volledig adres: hoe minder persoonsgegevens, hoe minder te beschermen.';

-- Houdt display_name in de pas met voor- en achternaam, zodat er nooit een
-- leeg of verouderd label in een klassement staat.
create or replace function public.sync_display_name()
returns trigger
language plpgsql
as $$
begin
  if coalesce(trim(new.display_name), '') = '' then
    new.display_name := trim(coalesce(new.first_name, '') || ' ' || coalesce(new.last_name, ''));
  end if;
  if coalesce(trim(new.display_name), '') = '' then
    new.display_name := coalesce(new.username, 'Speler');
  end if;
  return new;
end;
$$;

drop trigger if exists players_display_name on players;
create trigger players_display_name
  before insert or update on players
  for each row execute function public.sync_display_name();

-- ---------------------------------------------------------------------------
-- 2. Leeftijdscontrole
-- ---------------------------------------------------------------------------

create or replace function public.age_on(p_birthdate date, p_on date)
returns int
language sql
immutable
as $$
  select case
    when p_birthdate is null then null
    else extract(year from age(p_on, p_birthdate))::int
  end;
$$;

-- Weigert minderjarigen aan een tornooi. Alleen wanneer de geboortedatum
-- bekend is: een schaduwprofiel dat de floor aan tafel aanmaakt heeft die
-- vaak niet, en dan blijft de controle aan de deur waar hij hoort.
create or replace function public.enforce_min_age()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_min   int;
  v_birth date;
  v_age   int;
  v_tz    text;
begin
  select coalesce((c.compliance->>'min_age')::int, 18), c.timezone
  into v_min, v_tz
  from clubs c where c.id = new.club_id;

  select p.birthdate into v_birth from players p where p.id = new.player_id;
  if v_birth is null then
    return new;
  end if;

  v_age := public.age_on(v_birth, public.club_today(new.club_id));

  if v_age < v_min then
    raise exception 'Speler is % jaar; minimumleeftijd is %.', v_age, v_min
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

drop trigger if exists tournament_players_min_age on tournament_players;
create trigger tournament_players_min_age
  before insert on tournament_players
  for each row execute function public.enforce_min_age();

-- ---------------------------------------------------------------------------
-- 3. Aanmeldformulier voor nieuwe leden
-- ---------------------------------------------------------------------------
-- Nieuwe spelers vullen dit zelf in. Het komt bewust NIET rechtstreeks in
-- players terecht: een publiek formulier dat in je kerntabel schrijft is een
-- open deur voor rommel. De club keurt goed, en pas dan ontstaat het profiel.

create type signup_status as enum ('pending', 'approved', 'rejected');

create table if not exists player_signups (
  id            uuid primary key default gen_random_uuid(),
  club_id       uuid not null references clubs(id) on delete cascade,
  first_name    text not null,
  last_name     text not null,
  username      text not null,
  email         text not null,
  birthdate     date not null,
  municipality  text,
  status        signup_status not null default 'pending',
  player_id     uuid references players(id) on delete set null,
  reject_reason text,
  created_at    timestamptz not null default now(),
  reviewed_at   timestamptz,
  reviewed_by   uuid references auth.users(id) on delete set null
);

create index if not exists player_signups_club_status on player_signups (club_id, status, created_at desc);

-- Twee keer hetzelfde formulier insturen levert geen twee aanvragen op.
create unique index if not exists player_signups_pending_email
  on player_signups (club_id, lower(email)) where status = 'pending';

-- Zet een goedgekeurde aanvraag om in een echt spelersprofiel plus
-- clublidmaatschap. Bestaat er al iemand met dat e-mailadres, dan koppelen we
-- daaraan — zo blijft één persoon één speler, ook over clubs heen.
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

  -- Te jong is een gewone uitkomst, geen fout. Een exception zou bovendien
  -- de update hieronder mee terugdraaien, waardoor de aanvraag eeuwig op
  -- 'pending' bleef staan. We markeren hem dus en geven null terug; de
  -- reden staat in reject_reason zodat de club het kan uitleggen.
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
                         birthdate, municipality, link_state)
    values (trim(s.first_name || ' ' || s.last_name), s.first_name, s.last_name,
            s.username, s.email, s.birthdate, s.municipality, 'invited')
    returning id into v_player;
  else
    -- Bestaand profiel aanvullen, maar nooit overschrijven wat de speler zelf
    -- al heeft ingevuld.
    update players set
      first_name   = coalesce(first_name, s.first_name),
      last_name    = coalesce(last_name, s.last_name),
      username     = coalesce(username, s.username),
      birthdate    = coalesce(birthdate, s.birthdate),
      municipality = coalesce(municipality, s.municipality)
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
-- 4. Online inschrijven
-- ---------------------------------------------------------------------------
-- Bewust een aparte tabel naast tournament_players: inschrijven is een
-- voornemen, deelnemen is een feit. De floor bevestigt aan de deur en boekt
-- dan pas de inkoop. Zonder dat onderscheid staat iemand die zich online
-- inschreef en niet kwam opdagen in je uitslag.

create table if not exists tournament_registrations (
  id            uuid primary key default gen_random_uuid(),
  club_id       uuid not null references clubs(id) on delete cascade,
  tournament_id uuid not null references tournaments(id) on delete cascade,
  player_id     uuid not null references players(id) on delete cascade,
  note          text,
  created_at    timestamptz not null default now(),
  cancelled_at  timestamptz,
  unique (tournament_id, player_id)
);

create index if not exists tournament_registrations_tournament
  on tournament_registrations (tournament_id) where cancelled_at is null;

-- ---------------------------------------------------------------------------
-- 5. Spelers geven hun eigen stack in
-- ---------------------------------------------------------------------------

alter table tournament_players
  add column if not exists chip_count_updated_at timestamptz,
  add column if not exists chip_count_by         text
    check (chip_count_by is null or chip_count_by in ('player', 'floor'));

-- Een speler mag zijn eigen rij bijwerken, maar alleen het chipaantal.
-- Kolomrechten kunnen hier niet helpen: staf en spelers delen dezelfde
-- databaserol, dus een GRANT per kolom zou ook de floor beperken. Vandaar
-- een trigger die per geval kijkt wie er aan het bijwerken is.
create or replace function public.guard_player_chip_update()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_is_staff boolean;
  v_is_self  boolean;
begin
  if public.is_service_context() then
    return new;
  end if;

  v_is_staff := public.has_club_role(new.club_id, array['owner','admin','floor']::club_role[]);
  if v_is_staff then
    if new.chip_count is distinct from old.chip_count then
      new.chip_count_updated_at := now();
      new.chip_count_by := 'floor';
    end if;
    return new;
  end if;

  select exists (
    select 1 from players p
    where p.id = new.player_id and p.auth_user_id = auth.uid()
  ) into v_is_self;

  if not v_is_self then
    raise exception 'Geen rechten om deze deelnemer bij te werken'
      using errcode = 'insufficient_privilege';
  end if;

  if old.status <> 'active' then
    raise exception 'Je kan geen stack meer ingeven: je bent niet meer actief in dit tornooi'
      using errcode = 'check_violation';
  end if;

  -- Alles behalve het chipaantal moet gelijk blijven.
  if (new.status, new.table_no, new.seat_no, new.finish_position,
      new.reentries_used, new.rebuys_used, new.addons_used, new.bounties_won,
      new.player_id, new.tournament_id, new.club_id)
     is distinct from
     (old.status, old.table_no, old.seat_no, old.finish_position,
      old.reentries_used, old.rebuys_used, old.addons_used, old.bounties_won,
      old.player_id, old.tournament_id, old.club_id)
  then
    raise exception 'Je kan alleen je eigen chipaantal aanpassen'
      using errcode = 'insufficient_privilege';
  end if;

  if new.chip_count is not null and (new.chip_count < 0 or new.chip_count > 1000000000) then
    raise exception 'Onmogelijk chipaantal' using errcode = 'check_violation';
  end if;

  new.chip_count_updated_at := now();
  new.chip_count_by := 'player';
  return new;
end;
$$;

drop trigger if exists tournament_players_chip_guard on tournament_players;
create trigger tournament_players_chip_guard
  before update on tournament_players
  for each row execute function public.guard_player_chip_update();

-- ---------------------------------------------------------------------------
-- 6. Dealvoorstellen
-- ---------------------------------------------------------------------------

create type deal_method as enum ('icm', 'chipchop', 'custom');
create type deal_status as enum ('proposed', 'accepted', 'rejected');

create table if not exists tournament_deals (
  id            uuid primary key default gen_random_uuid(),
  club_id       uuid not null references clubs(id) on delete cascade,
  tournament_id uuid not null references tournaments(id) on delete cascade,
  method        deal_method not null,
  status        deal_status not null default 'proposed',
  pool_cents    int not null,
  -- [{ "tournament_player_id": ..., "name": ..., "chips": ..., "icm_cents": ...,
  --    "chop_cents": ..., "agreed_cents": ... }]
  shares        jsonb not null,
  created_at    timestamptz not null default now(),
  decided_at    timestamptz,
  created_by    uuid references auth.users(id) on delete set null
);

create index if not exists tournament_deals_tournament
  on tournament_deals (tournament_id, created_at desc);

-- Hoogstens één openstaand voorstel per tornooi: anders staat er straks een
-- verouderd voorstel op het zaalscherm terwijl de tafel over een nieuw praat.
create unique index if not exists tournament_deals_one_open
  on tournament_deals (tournament_id) where status = 'proposed';

-- ---------------------------------------------------------------------------
-- 7. RLS
-- ---------------------------------------------------------------------------

alter table player_signups            enable row level security;
alter table tournament_registrations  enable row level security;
alter table tournament_deals          enable row level security;

-- Iedereen mag zich aanmelden bij een actieve club; niemand mag de
-- aanvragen van anderen lezen.
drop policy if exists player_signups_insert on player_signups;
create policy player_signups_insert on player_signups
  for insert with check (
    exists (select 1 from clubs c where c.id = club_id and c.is_active)
  );

drop policy if exists player_signups_staff on player_signups;
create policy player_signups_staff on player_signups
  for select using (public.is_club_member(club_id));

drop policy if exists player_signups_review on player_signups;
create policy player_signups_review on player_signups
  for update using (public.has_club_role(club_id, array['owner','admin']::club_role[]))
  with check (public.has_club_role(club_id, array['owner','admin']::club_role[]));

-- Inschrijven doe je voor jezelf; staf ziet en beheert alles van de club.
drop policy if exists tournament_registrations_read on tournament_registrations;
create policy tournament_registrations_read on tournament_registrations
  for select using (
    public.is_club_member(club_id)
    or exists (select 1 from players p
               where p.id = tournament_registrations.player_id and p.auth_user_id = auth.uid())
  );

drop policy if exists tournament_registrations_self on tournament_registrations;
create policy tournament_registrations_self on tournament_registrations
  for insert with check (
    exists (select 1 from players p
            where p.id = player_id and p.auth_user_id = auth.uid())
    and exists (
      select 1 from tournaments t
      where t.id = tournament_id
        and t.club_id = tournament_registrations.club_id
        and t.status in ('scheduled', 'draft')
        and public.is_club_player(t.club_id)
    )
  );

drop policy if exists tournament_registrations_cancel on tournament_registrations;
create policy tournament_registrations_cancel on tournament_registrations
  for update using (
    exists (select 1 from players p
            where p.id = player_id and p.auth_user_id = auth.uid())
    or public.has_club_role(club_id, array['owner','admin','floor']::club_role[])
  );

drop policy if exists tournament_registrations_staff on tournament_registrations;
create policy tournament_registrations_staff on tournament_registrations
  for delete using (public.has_club_role(club_id, array['owner','admin','floor']::club_role[]));

-- Een dealvoorstel hoort op het zaalscherm te verschijnen, dus iedereen die
-- het tornooi mag zien mag het voorstel zien. Alleen staf maakt en beslist.
drop policy if exists tournament_deals_read on tournament_deals;
create policy tournament_deals_read on tournament_deals
  for select using (public.can_view_tournament(tournament_id));

drop policy if exists tournament_deals_write on tournament_deals;
create policy tournament_deals_write on tournament_deals
  for all using (public.has_club_role(club_id, array['owner','admin','floor']::club_role[]))
  with check (public.has_club_role(club_id, array['owner','admin','floor']::club_role[]));

-- Spelers mogen hun eigen rij bijwerken; de trigger hierboven bewaakt wát.
drop policy if exists tournament_players_self_update on tournament_players;
create policy tournament_players_self_update on tournament_players
  for update using (
    exists (select 1 from players p
            where p.id = tournament_players.player_id and p.auth_user_id = auth.uid())
  )
  with check (
    exists (select 1 from players p
            where p.id = tournament_players.player_id and p.auth_user_id = auth.uid())
  );

-- ---------------------------------------------------------------------------
-- 8. Rechten en realtime
-- ---------------------------------------------------------------------------

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    grant usage on schema public to anon;
    grant select on all tables in schema public to anon;
    -- Alleen dit ene ding mag een niet-aangemelde bezoeker: zich aanmelden.
    grant insert on public.player_signups to anon;
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant select, insert, update, delete on all tables in schema public to authenticated;
    grant usage, select on all sequences in schema public to authenticated;
  end if;
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant all on all tables in schema public to service_role;
    grant all on all sequences in schema public to service_role;
  end if;
end $$;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (select 1 from pg_publication_tables
                   where pubname = 'supabase_realtime' and schemaname = 'public'
                     and tablename = 'tournament_deals') then
      alter publication supabase_realtime add table public.tournament_deals;
    end if;
    if not exists (select 1 from pg_publication_tables
                   where pubname = 'supabase_realtime' and schemaname = 'public'
                     and tablename = 'tournament_registrations') then
      alter publication supabase_realtime add table public.tournament_registrations;
    end if;
  end if;
end $$;
