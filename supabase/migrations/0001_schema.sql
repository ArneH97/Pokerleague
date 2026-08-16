-- ClubStack — kernschema
-- Multi-tenant pokerclubplatform: clubbeheer, tornooi-engine, spelersingang.
--
-- Twee ontwerpbeslissingen die later niet meer te wijzigen zijn:
--   1. Elke clubgebonden tabel draagt club_id. Redundant t.o.v. de FK-keten,
--      maar het maakt RLS één simpele check i.p.v. een join per policy.
--   2. Speleridentiteit is PLATFORMBREED (players), niet clubgebonden.
--      club_players is slechts de kijk van één club op een persoon.
--      Zonder dit is een ranking over clubs heen later niet meer te bouwen.

-- Geen extensies nodig: gen_random_uuid() zit sinds Postgres 13 in de kern,
-- en voor hoofdletterongevoelige e-mail gebruiken we een lower()-index in
-- plaats van citext. Dat scheelt een extensie die op Supabase in een apart
-- schema belandt en dan search_path-verrassingen geeft.

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------

create type club_role         as enum ('owner', 'admin', 'floor', 'viewer');
create type player_link_state as enum ('shadow', 'invited', 'claimed');
create type tournament_status as enum ('draft', 'scheduled', 'running', 'paused', 'finished', 'cancelled');
create type clock_status      as enum ('stopped', 'running', 'paused');
create type entry_status      as enum ('registered', 'active', 'eliminated', 'withdrawn');
create type buyin_kind        as enum ('buyin', 'reentry', 'rebuy', 'addon');
create type bounty_mode       as enum ('none', 'fixed', 'progressive');
create type ranking_method    as enum ('fixed_table', 'linear', 'sqrt_ratio', 'pokerstars');
create type visibility        as enum ('private', 'members', 'public');

-- ---------------------------------------------------------------------------
-- Tenants
-- ---------------------------------------------------------------------------

create table clubs (
  id            uuid primary key default gen_random_uuid(),
  slug          text not null unique,
  name          text not null,
  city          text,
  country       char(2) not null default 'BE',
  locale        text    not null default 'nl',
  currency      char(3) not null default 'EUR',
  timezone      text    not null default 'Europe/Brussels',
  logo_url      text,

  -- Gedoogbeleid Kansspelcommissie. Bewust configureerbaar: dit is beleid,
  -- geen wet, en het KB dat de voorwaarden vastlegt moet nog komen.
  compliance    jsonb not null default jsonb_build_object(
                  'profile',            'be_tolerance',
                  'max_buyin_cents',    5000,
                  'max_daily_cents',    10000,
                  'max_reentries',      1,
                  'allow_cash_games',   false,
                  'min_age',            18,
                  'enforce',            'warn'   -- 'off' | 'warn' | 'block'
                ),

  settings      jsonb not null default '{}'::jsonb,
  is_active     boolean not null default true,
  created_at    timestamptz not null default now()
);

-- Staf: mensen die de club beheren. Los van spelers.
create table club_members (
  id          uuid primary key default gen_random_uuid(),
  club_id     uuid not null references clubs(id) on delete cascade,
  user_id     uuid not null references auth.users(id) on delete cascade,
  role        club_role not null default 'floor',
  created_at  timestamptz not null default now(),
  unique (club_id, user_id)
);

create index on club_members (user_id);

-- ---------------------------------------------------------------------------
-- Speleridentiteit (platformbreed)
-- ---------------------------------------------------------------------------

-- Eén rij per persoon, over alle clubs heen. Een club maakt hier een
-- schaduwprofiel aan; de speler claimt het later met zijn e-mailadres
-- en de historie van al zijn clubs versmelt vanzelf.
create table players (
  id                 uuid primary key default gen_random_uuid(),
  display_name       text not null,
  email              text,
  auth_user_id       uuid unique references auth.users(id) on delete set null,
  link_state         player_link_state not null default 'shadow',
  country            char(2),
  locale             text not null default 'nl',
  avatar_url         text,

  -- Zichtbaarheid in publieke rankings. Standaard uit: GDPR-opt-in,
  -- de speler zet dit zelf aan bij het claimen van zijn profiel.
  public_profile     boolean not null default false,

  -- Zachte merge van dubbels. De oude rij blijft bestaan zodat oude
  -- verwijzingen niet breken; queries volgen de pointer.
  merged_into_id     uuid references players(id) on delete set null,

  created_at         timestamptz not null default now()
);

-- Hoofdletterongevoelig uniek: Jan@test.be en jan@test.be zijn dezelfde man.
create unique index players_email_unique
  on players (lower(email)) where email is not null and merged_into_id is null;
create index on players (merged_into_id) where merged_into_id is not null;

-- De kijk van één club op een persoon: lidnummer, bijnaam, status.
create table club_players (
  id             uuid primary key default gen_random_uuid(),
  club_id        uuid not null references clubs(id) on delete cascade,
  player_id      uuid not null references players(id) on delete cascade,
  member_number  text,
  nickname       text,
  is_member      boolean not null default true,  -- false = gastspeler
  joined_on      date,
  left_on        date,
  notes          text,
  created_at     timestamptz not null default now(),
  unique (club_id, player_id)
);

create unique index club_players_member_number_unique
  on club_players (club_id, member_number) where member_number is not null;
create index on club_players (player_id);

-- Uitnodiging om een schaduwprofiel te claimen.
create table player_invites (
  id           uuid primary key default gen_random_uuid(),
  club_id      uuid not null references clubs(id) on delete cascade,
  player_id    uuid not null references players(id) on delete cascade,
  email        text not null,
  token        text not null unique,
  expires_at   timestamptz not null,
  accepted_at  timestamptz,
  created_at   timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Configuratie: blindstructuren, payouts, puntensystemen
-- ---------------------------------------------------------------------------

-- club_id null = platformsjabloon, beschikbaar voor elke club.
create table blind_structures (
  id           uuid primary key default gen_random_uuid(),
  club_id      uuid references clubs(id) on delete cascade,
  name         text not null,
  description  text,
  created_at   timestamptz not null default now()
);

create table blind_levels (
  id            uuid primary key default gen_random_uuid(),
  structure_id  uuid not null references blind_structures(id) on delete cascade,
  idx           int  not null,
  is_break      boolean not null default false,
  label         text,
  small_blind   int not null default 0,
  big_blind     int not null default 0,
  ante          int not null default 0,
  duration_s    int not null,
  unique (structure_id, idx)
);

create table payout_templates (
  id          uuid primary key default gen_random_uuid(),
  club_id     uuid references clubs(id) on delete cascade,
  name        text not null,
  -- [{ "min_entries": 1, "max_entries": 9, "percentages": [60, 40] }, ...]
  tiers       jsonb not null,
  rounding    int not null default 500,   -- afronden op veelvouden van X cent
  created_at  timestamptz not null default now()
);

-- Elke club rekent zijn seizoenspunten anders. Nooit hardcoderen.
create table ranking_configs (
  id             uuid primary key default gen_random_uuid(),
  club_id        uuid references clubs(id) on delete cascade,
  name           text not null,
  method         ranking_method not null default 'sqrt_ratio',
  -- fixed_table : { "table": [100, 80, 65, ...], "tail": 5 }
  -- linear      : { "base": 100, "decrement": 5, "floor": 1 }
  -- sqrt_ratio  : { "multiplier": 10 }        -> mult * sqrt(N) / sqrt(P)
  -- pokerstars  : { "multiplier": 10 }        -> mult * (sqrt(N)/sqrt(P)) * log10(1+B)
  params         jsonb not null default '{}'::jsonb,
  bonus_per_ko   numeric(6,2) not null default 0,
  bonus_entry    numeric(6,2) not null default 0,
  count_best_n   int,          -- null = alle tornooien tellen mee
  min_tournaments int not null default 0,
  created_at     timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Seizoenen en tornooien
-- ---------------------------------------------------------------------------

create table seasons (
  id                uuid primary key default gen_random_uuid(),
  club_id           uuid not null references clubs(id) on delete cascade,
  name              text not null,
  starts_on         date not null,
  ends_on           date,
  ranking_config_id uuid references ranking_configs(id) on delete set null,
  is_active         boolean not null default true,
  created_at        timestamptz not null default now()
);

create index on seasons (club_id);

create table tournaments (
  id                uuid primary key default gen_random_uuid(),
  club_id           uuid not null references clubs(id) on delete cascade,
  season_id         uuid references seasons(id) on delete set null,
  structure_id      uuid references blind_structures(id) on delete set null,
  payout_template_id uuid references payout_templates(id) on delete set null,

  name              text not null,
  scheduled_at      timestamptz not null,
  status            tournament_status not null default 'draft',
  player_visibility visibility not null default 'members',

  -- Geld. Alles in cent, nooit floats.
  buyin_cents       int not null default 0,
  fee_cents         int not null default 0,   -- clubbijdrage, telt niet in prijzenpot
  bounty_mode       bounty_mode not null default 'none',
  bounty_cents      int not null default 0,
  addon_cents       int,
  starting_stack    int not null default 10000,
  addon_stack       int,
  max_reentries     int not null default 1,
  late_reg_level    int,                      -- laatste level waarop instappen mag

  -- Kloktoestand. Bewust GEEN aftellende teller in de database:
  -- we bewaren het startmoment en de opgebouwde tijd, de client rekent
  -- de resterende tijd uit tegen servertijd. Overleeft refresh, herstart
  -- en twee schermen die elkaar niet kennen.
  clock             clock_status not null default 'stopped',
  level_idx         int not null default 0,
  level_started_at  timestamptz,
  level_elapsed_ms  bigint not null default 0,

  started_at        timestamptz,
  ended_at          timestamptz,
  notes             text,
  created_by        uuid references auth.users(id) on delete set null,
  created_at        timestamptz not null default now()
);

create index on tournaments (club_id, scheduled_at desc);
create index on tournaments (club_id, status);
create index on tournaments (season_id);

create table tournament_tables (
  id             uuid primary key default gen_random_uuid(),
  club_id        uuid not null references clubs(id) on delete cascade,
  tournament_id  uuid not null references tournaments(id) on delete cascade,
  table_no       int not null,
  seats          int not null default 9,
  is_open        boolean not null default true,
  button_seat    int,
  unique (tournament_id, table_no)
);

-- Deelname van één speler aan één tornooi.
create table tournament_players (
  id             uuid primary key default gen_random_uuid(),
  club_id        uuid not null references clubs(id) on delete cascade,
  tournament_id  uuid not null references tournaments(id) on delete cascade,
  player_id      uuid not null references players(id) on delete restrict,
  status         entry_status not null default 'registered',
  table_no       int,
  seat_no        int,
  chip_count     int,
  reentries_used int not null default 0,
  rebuys_used    int not null default 0,
  addons_used    int not null default 0,
  bounties_won   int not null default 0,
  registered_at  timestamptz not null default now(),
  eliminated_at  timestamptz,
  finish_position int,
  unique (tournament_id, player_id)
);

create index on tournament_players (tournament_id, status);
create index on tournament_players (player_id);
create unique index tournament_players_seat_unique
  on tournament_players (tournament_id, table_no, seat_no)
  where table_no is not null and seat_no is not null and status = 'active';

-- ---------------------------------------------------------------------------
-- Het geldregister — tevens het compliance-bewijs
-- ---------------------------------------------------------------------------
-- Elke euro die een speler inzet staat hier als aparte rij met tijdstip.
-- Dit is wat een club moet kunnen tonen om aan te tonen dat niemand boven
-- de daglimiet ging. Append-only: corrigeren doe je met een tegenboeking.

create table buyins (
  id                    uuid primary key default gen_random_uuid(),
  club_id               uuid not null references clubs(id) on delete cascade,
  tournament_id         uuid not null references tournaments(id) on delete cascade,
  tournament_player_id  uuid not null references tournament_players(id) on delete cascade,
  player_id             uuid not null references players(id) on delete restrict,
  kind                  buyin_kind not null,
  amount_cents          int not null,   -- naar de prijzenpot
  fee_cents             int not null default 0,
  bounty_cents          int not null default 0,
  is_void               boolean not null default false,
  voided_reason         text,
  occurred_at           timestamptz not null default now(),
  recorded_by           uuid references auth.users(id) on delete set null
);

create index on buyins (tournament_id);
create index on buyins (player_id, occurred_at);
create index on buyins (club_id, occurred_at);

create table eliminations (
  id                    uuid primary key default gen_random_uuid(),
  club_id               uuid not null references clubs(id) on delete cascade,
  tournament_id         uuid not null references tournaments(id) on delete cascade,
  tournament_player_id  uuid not null references tournament_players(id) on delete cascade,
  eliminated_by_id      uuid references tournament_players(id) on delete set null,
  position              int not null,
  bounty_cents          int not null default 0,
  occurred_at           timestamptz not null default now(),
  recorded_by           uuid references auth.users(id) on delete set null
);

create index on eliminations (tournament_id);

-- ---------------------------------------------------------------------------
-- Eindresultaten — de tabel waar de spelersingang op leest
-- ---------------------------------------------------------------------------

create table tournament_results (
  id             uuid primary key default gen_random_uuid(),
  club_id        uuid not null references clubs(id) on delete cascade,
  tournament_id  uuid not null references tournaments(id) on delete cascade,
  season_id      uuid references seasons(id) on delete set null,
  player_id      uuid not null references players(id) on delete restrict,
  position       int not null,
  entries_total  int not null,
  prize_cents    int not null default 0,
  bounty_cents   int not null default 0,
  invested_cents int not null default 0,
  knockouts      int not null default 0,
  points         numeric(8,2) not null default 0,
  finished_at    timestamptz not null default now(),
  unique (tournament_id, player_id)
);

create index on tournament_results (player_id, finished_at desc);
create index on tournament_results (club_id, season_id);
create index on tournament_results (season_id, player_id);

-- ---------------------------------------------------------------------------
-- Auditspoor
-- ---------------------------------------------------------------------------

create table audit_log (
  id          bigserial primary key,
  club_id     uuid references clubs(id) on delete cascade,
  actor_id    uuid references auth.users(id) on delete set null,
  entity      text not null,
  entity_id   uuid,
  action      text not null,
  payload     jsonb,
  created_at  timestamptz not null default now()
);

create index on audit_log (club_id, created_at desc);
