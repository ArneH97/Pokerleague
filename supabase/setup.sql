-- Pokerleague — volledige database-opzet
--
-- GEGENEREERD BESTAND. Bewerk supabase/migrations/*.sql en draai
-- `npm run db:bundle` opnieuw.
--
-- Plak dit in de SQL Editor van Supabase en draai het in één keer.
-- Draait op een lege database; bestaande tabellen worden niet aangeraakt
-- maar zullen wel een foutmelding geven.
--
-- Onderdelen: 0001_schema.sql · 0002_functions.sql · 0003_rls.sql · 0004_realtime.sql · 0005_players.sql · 0006_structures.sql · 0007_public_rankings.sql · 0008_floor.sql · 0009_club_mark.sql · 0010_floor_email.sql · 0011_rls_recursion.sql · 0012_floor_undo_buyin.sql · 0013_entry_fees.sql · 0014_standings_period.sql · 0015_club_overview.sql · 0016_deal.sql

-- =========================================================================
-- 0001_schema.sql
-- =========================================================================

-- Pokerleague — kernschema
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

-- =========================================================================
-- 0002_functions.sql
-- =========================================================================

-- Pokerleague — functies: autorisatie, compliance, payouts, punten, afronding.

-- ---------------------------------------------------------------------------
-- Autorisatiehelpers
-- ---------------------------------------------------------------------------
-- SECURITY DEFINER met vaste search_path: deze functies worden vanuit RLS-
-- policies op club_members zelf aangeroepen en zouden anders oneindig
-- recursief worden.

create or replace function public.is_club_member(p_club_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from club_members
    where club_id = p_club_id and user_id = auth.uid()
  );
$$;

create or replace function public.has_club_role(p_club_id uuid, p_roles club_role[])
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from club_members
    where club_id = p_club_id
      and user_id = auth.uid()
      and role = any(p_roles)
  );
$$;

-- Draait deze aanroep buiten een gebruikerssessie om? Waar: bij migraties,
-- seeds, serverside code met de secret key, en binnen triggers die als
-- eigenaar draaien. Onwaar voor elke gewone browseraanvraag.
--
-- Nodig omdat de functies hieronder SECURITY DEFINER zijn en dus RLS
-- omzeilen. Zonder deze grens zou elke ingelogde speler ze kunnen aanroepen
-- voor eender welke club.
-- Let op: dit kijkt naar de ROL UIT HET JWT, niet naar current_user. Binnen
-- een SECURITY DEFINER-functie is current_user altijd de eigenaar van die
-- functie, waardoor een controle daarop niets doet — hij zou voor iedereen
-- 'postgres' zien en dus altijd waar zijn.
--
-- Geen JWT betekent geen webverzoek: een migratie, een seed of psql.
create or replace function public.is_service_context()
returns boolean
language plpgsql
stable
as $$
declare
  v_role text;
begin
  begin
    v_role := auth.role();
  exception when others then
    v_role := null;
  end;
  return coalesce(v_role, 'service_role') = 'service_role';
end;
$$;

-- De spelersrij die bij de ingelogde gebruiker hoort (of null voor staf
-- die zelf niet speelt).
create or replace function public.current_player_id()
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select id from players where auth_user_id = auth.uid() limit 1;
$$;

-- Volgt de merge-pointer naar de overlevende spelersrij.
create or replace function public.resolve_player(p_player_id uuid)
returns uuid
language plpgsql
stable
as $$
declare
  v_id    uuid := p_player_id;
  v_next  uuid;
  v_hops  int := 0;
begin
  loop
    select merged_into_id into v_next from players where id = v_id;
    exit when v_next is null or v_hops > 10;
    v_id := v_next;
    v_hops := v_hops + 1;
  end loop;
  return v_id;
end;
$$;

-- Staat de ingelogde gebruiker als speler op de ledenlijst van deze club?
create or replace function public.is_club_player(p_club_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from club_players cp
    join players p on p.id = cp.player_id
    where cp.club_id = p_club_id and p.auth_user_id = auth.uid()
  );
$$;

-- Deelt de ingelogde gebruiker een club met deze speler?
create or replace function public.shares_club_with(p_player_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from club_players a
    join club_players b on b.club_id = a.club_id
    join players me on me.id = a.player_id
    where me.auth_user_id = auth.uid()
      and b.player_id = p_player_id
  );
$$;

-- Mag de ingelogde gebruiker dit tornooi zien?
create or replace function public.can_view_tournament(p_tournament_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from tournaments t
    where t.id = p_tournament_id
      and (
        public.is_club_member(t.club_id)
        or (t.player_visibility = 'public')
        or (t.player_visibility = 'members' and public.is_club_player(t.club_id))
      )
  );
$$;

-- ---------------------------------------------------------------------------
-- Compliance: gedoogbeleid Kansspelcommissie
-- ---------------------------------------------------------------------------

-- Welke dag is het nú bij deze club?
--
-- Niet overslaan: een pokeravond loopt door na middernacht, en de server
-- draait op UTC. Om 00:30 in Brussel is het in UTC nog de vorige dag. Wie
-- hier `current_date` gebruikt, telt de daglimiet tegen de verkeerde dag en
-- laat precies op het gevaarlijkste moment te veel door.
create or replace function public.club_today(p_club_id uuid default null)
returns date
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select (now() at time zone coalesce(
    (select c.timezone from clubs c where c.id = p_club_id),
    'Europe/Brussels'
  ))::date;
$$;

-- Totale inzet van een speler op één kalenderdag. Standaard over alle clubs
-- heen: de daglimiet volgt de speler, niet de club. Geef p_club_id mee voor
-- de clubgebonden variant (wat een club effectief kan controleren).
--
-- p_day is de LOKALE dag van de club, niet de serverdatum. Gebruik
-- public.club_today(club_id) om hem te bepalen.
create or replace function public.player_daily_spend_cents(
  p_player_id uuid,
  p_day       date,
  p_club_id   uuid default null
)
returns int
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  -- Financiële gegevens: alleen staf van de bevraagde club, of serverside.
  if not public.is_service_context()
     and not (p_club_id is not null
              and public.has_club_role(p_club_id, array['owner','admin','floor']::club_role[]))
  then
    raise exception 'Geen rechten om de daginzet van deze speler op te vragen'
      using errcode = 'insufficient_privilege';
  end if;

  return public.daily_spend_unchecked(p_player_id, p_day, p_club_id);
end;
$$;

-- Interne variant zonder controle, voor de compliance-trigger — die draait
-- midden in een verzoek van een floormedewerker en heeft het totaal over
-- alle clubs heen nodig.
--
-- De echte beveiliging zit niet in een rolcontrole maar in de REVOKE
-- hieronder: anon en authenticated mogen deze functie simpelweg niet
-- aanroepen. Dat is niet te omzeilen met een geknutseld JWT.
create or replace function public.daily_spend_unchecked(
  p_player_id uuid,
  p_day       date,
  p_club_id   uuid default null
)
returns int
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(sum(b.amount_cents + b.fee_cents + b.bounty_cents), 0)::int
  from buyins b
  join clubs c on c.id = b.club_id
  where b.player_id = p_player_id
    and not b.is_void
    and (p_club_id is null or b.club_id = p_club_id)
    and (b.occurred_at at time zone c.timezone)::date = p_day;
$$;

revoke all on function public.daily_spend_unchecked(uuid, date, uuid) from public;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    revoke all on function public.daily_spend_unchecked(uuid, date, uuid) from anon;
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    revoke all on function public.daily_spend_unchecked(uuid, date, uuid) from authenticated;
  end if;
end $$;

-- Bewaakt de daglimiet en het maximum aantal re-entries bij het inboeken.
-- Gedrag hangt af van clubs.compliance->>'enforce': off | warn | block.
create or replace function public.enforce_compliance_on_buyin()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_comp      jsonb;
  v_tz        text;
  v_day       date;
  v_spent     int;
  v_new_total int;
  v_max_day   int;
  v_mode      text;
  v_max_re    int;
  v_used      int;
begin
  select c.compliance, c.timezone into v_comp, v_tz
  from clubs c where c.id = new.club_id;

  v_mode := coalesce(v_comp->>'enforce', 'warn');
  if v_mode = 'off' then
    return new;
  end if;

  v_day     := (new.occurred_at at time zone v_tz)::date;
  v_max_day := coalesce((v_comp->>'max_daily_cents')::int, 10000);
  v_max_re  := coalesce((v_comp->>'max_reentries')::int, 1);

  -- Bewust de ongecontroleerde variant: deze trigger draait tijdens een
  -- verzoek van een floormedewerker en moet het totaal over alle clubs zien.
  v_spent     := public.daily_spend_unchecked(new.player_id, v_day);
  v_new_total := v_spent + new.amount_cents + new.fee_cents + new.bounty_cents;

  if v_new_total > v_max_day then
    if v_mode = 'block' then
      raise exception
        'Daglimiet overschreden: speler zou op % cent uitkomen, limiet is % cent.',
        v_new_total, v_max_day
        using errcode = 'check_violation';
    else
      raise warning 'Daglimiet overschreden: % van % cent.', v_new_total, v_max_day;
    end if;
  end if;

  if new.kind in ('reentry', 'rebuy') then
    select case when new.kind = 'reentry' then reentries_used else rebuys_used end
    into v_used
    from tournament_players where id = new.tournament_player_id;

    if coalesce(v_used, 0) + 1 > v_max_re then
      if v_mode = 'block' then
        raise exception 'Maximaal % re-entry/rebuy per tornooi toegestaan.', v_max_re
          using errcode = 'check_violation';
      else
        raise warning 'Re-entrylimiet overschreden.';
      end if;
    end if;
  end if;

  return new;
end;
$$;

create trigger buyins_compliance
  before insert on buyins
  for each row execute function public.enforce_compliance_on_buyin();

-- Houdt de tellers op tournament_players synchroon met het geldregister.
create or replace function public.sync_entry_counters()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_tp uuid := coalesce(new.tournament_player_id, old.tournament_player_id);
begin
  update tournament_players tp set
    reentries_used = (select count(*) from buyins b
                      where b.tournament_player_id = v_tp and b.kind = 'reentry' and not b.is_void),
    rebuys_used    = (select count(*) from buyins b
                      where b.tournament_player_id = v_tp and b.kind = 'rebuy'   and not b.is_void),
    addons_used    = (select count(*) from buyins b
                      where b.tournament_player_id = v_tp and b.kind = 'addon'   and not b.is_void)
  where tp.id = v_tp;
  return null;
end;
$$;

create trigger buyins_sync_counters
  after insert or update or delete on buyins
  for each row execute function public.sync_entry_counters();

-- ---------------------------------------------------------------------------
-- Prijzengeld
-- ---------------------------------------------------------------------------

-- Verdeelt de prijzenpot volgens het sjabloon. Afronding gaat naar beneden op
-- een veelvoud van p_rounding; wat overblijft gaat naar plaats 1, zodat de som
-- exact de pot is.
create or replace function public.calc_payouts(
  p_prizepool_cents int,
  p_entries         int,
  p_tiers           jsonb,
  p_rounding        int default 500
)
returns table (place int, amount_cents int)
language plpgsql
immutable
as $$
declare
  v_tier    jsonb;
  v_pcts    jsonb;
  v_amounts int[] := array[]::int[];
  v_i       int;
  v_n       int;
  v_sum     int := 0;
  v_round   int := greatest(coalesce(p_rounding, 1), 1);
begin
  if p_prizepool_cents is null or p_prizepool_cents <= 0
     or p_entries is null or p_entries <= 0 then
    return;
  end if;

  select t into v_tier
  from jsonb_array_elements(coalesce(p_tiers, '[]'::jsonb)) t
  where p_entries >= coalesce((t->>'min_entries')::int, 0)
    and p_entries <= coalesce((t->>'max_entries')::int, 2147483647)
  order by coalesce((t->>'min_entries')::int, 0) desc
  limit 1;

  v_pcts := coalesce(v_tier->'percentages', '[]'::jsonb);
  -- Nooit meer betaalde plaatsen dan deelnemers.
  v_n := least(coalesce(jsonb_array_length(v_pcts), 0), p_entries);

  if v_n = 0 then
    place := 1;
    amount_cents := p_prizepool_cents;
    return next;
    return;
  end if;

  for v_i in 0 .. v_n - 1 loop
    v_amounts := v_amounts ||
      (floor(p_prizepool_cents * (v_pcts->>v_i)::numeric / 100.0 / v_round) * v_round)::int;
  end loop;

  select coalesce(sum(x), 0)::int into v_sum from unnest(v_amounts) x;

  -- Afrondingsrestant naar plaats 1, zodat de som exact de pot is.
  v_amounts[1] := v_amounts[1] + (p_prizepool_cents - v_sum);

  for v_i in 1 .. array_length(v_amounts, 1) loop
    place := v_i;
    amount_cents := v_amounts[v_i];
    return next;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- Seizoenspunten
-- ---------------------------------------------------------------------------
-- Elke club rekent anders. Vandaar een handvol benoemde methodes met
-- parameters in plaats van een vrij in te voeren formule — dat laatste is
-- een injectierisico en niemand onderhoudt het.

create or replace function public.calc_points(
  p_method      ranking_method,
  p_params      jsonb,
  p_position    int,
  p_entries     int,
  p_knockouts   int default 0,
  p_buyin_cents int default 0,
  p_bonus_ko    numeric default 0,
  p_bonus_entry numeric default 0
)
returns numeric
language plpgsql
immutable
as $$
declare
  v_pts   numeric := 0;
  v_tbl   jsonb;
  v_mult  numeric;
  v_base  numeric;
  v_dec   numeric;
  v_floor numeric;
begin
  if p_position is null or p_position < 1 or p_entries is null or p_entries < 1 then
    return 0;
  end if;

  case p_method
    when 'fixed_table' then
      v_tbl := coalesce(p_params->'table', '[]'::jsonb);
      if p_position <= jsonb_array_length(v_tbl) then
        v_pts := (v_tbl->>(p_position - 1))::numeric;
      else
        v_pts := coalesce((p_params->>'tail')::numeric, 0);
      end if;

    when 'linear' then
      v_base  := coalesce((p_params->>'base')::numeric, 100);
      v_dec   := coalesce((p_params->>'decrement')::numeric, 5);
      v_floor := coalesce((p_params->>'floor')::numeric, 1);
      v_pts   := greatest(v_base - (p_position - 1) * v_dec, v_floor);

    when 'sqrt_ratio' then
      v_mult := coalesce((p_params->>'multiplier')::numeric, 10);
      v_pts  := v_mult * sqrt(p_entries::numeric) / sqrt(p_position::numeric);

    when 'pokerstars' then
      v_mult := coalesce((p_params->>'multiplier')::numeric, 10);
      v_pts  := v_mult
                * (sqrt(p_entries::numeric) / sqrt(p_position::numeric))
                * log(10, 1 + (p_buyin_cents::numeric / 100.0));
  end case;

  v_pts := v_pts + (coalesce(p_knockouts, 0) * coalesce(p_bonus_ko, 0)) + coalesce(p_bonus_entry, 0);
  return round(greatest(v_pts, 0), 2);
end;
$$;

-- ---------------------------------------------------------------------------
-- Tornooi afsluiten
-- ---------------------------------------------------------------------------
-- Berekent pot, prijzen en punten en schrijft tournament_results weg.
-- Idempotent: opnieuw draaien overschrijft het vorige resultaat.

create or replace function public.finalize_tournament(p_tournament_id uuid)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  t             tournaments%rowtype;
  v_prizepool   int;
  v_entries     int;
  v_tiers       jsonb;
  v_rounding    int;
  v_rc          ranking_configs%rowtype;
  v_written     int := 0;
  r             record;
  v_prize       int;
begin
  select * into t from tournaments where id = p_tournament_id;
  if not found then
    raise exception 'Tornooi % bestaat niet', p_tournament_id;
  end if;

  -- Deze functie schrijft resultaten weg en omzeilt RLS. Zonder deze check
  -- zou elke ingelogde gebruiker het tornooi van een willekeurige club
  -- kunnen afsluiten.
  if not public.is_service_context()
     and not public.has_club_role(t.club_id, array['owner','admin','floor']::club_role[])
  then
    raise exception 'Geen rechten om dit tornooi af te sluiten'
      using errcode = 'insufficient_privilege';
  end if;

  select count(distinct player_id) into v_entries
  from tournament_players where tournament_id = p_tournament_id;

  if v_entries = 0 then
    return 0;
  end if;

  -- Alleen amount_cents vormt de pot; fee is clubinkomst, bounty wordt
  -- rechtstreeks aan de knock-outs uitbetaald.
  select coalesce(sum(amount_cents), 0) into v_prizepool
  from buyins where tournament_id = p_tournament_id and not is_void;

  select coalesce(pt.tiers, '[{"min_entries":1,"percentages":[100]}]'::jsonb),
         coalesce(pt.rounding, 500)
  into v_tiers, v_rounding
  from tournaments tt
  left join payout_templates pt on pt.id = tt.payout_template_id
  where tt.id = p_tournament_id;

  select rc.* into v_rc
  from seasons s
  join ranking_configs rc on rc.id = s.ranking_config_id
  where s.id = t.season_id;

  delete from tournament_results where tournament_id = p_tournament_id;

  for r in
    select tp.player_id,
           tp.finish_position,
           coalesce((select count(*) from eliminations e
                     where e.eliminated_by_id = tp.id), 0)::int as knockouts,
           coalesce((select sum(b.amount_cents + b.fee_cents + b.bounty_cents)
                     from buyins b
                     where b.tournament_player_id = tp.id and not b.is_void), 0)::int as invested,
           coalesce((select sum(e.bounty_cents) from eliminations e
                     where e.eliminated_by_id = tp.id), 0)::int as bounty_won
    from tournament_players tp
    where tp.tournament_id = p_tournament_id
      and tp.finish_position is not null
  loop
    select coalesce(cp.amount_cents, 0) into v_prize
    from public.calc_payouts(v_prizepool, v_entries, v_tiers, v_rounding) cp
    where cp.place = r.finish_position;

    insert into tournament_results (
      club_id, tournament_id, season_id, player_id, position, entries_total,
      prize_cents, bounty_cents, invested_cents, knockouts, points, finished_at
    ) values (
      t.club_id, p_tournament_id, t.season_id, r.player_id, r.finish_position, v_entries,
      coalesce(v_prize, 0), r.bounty_won, r.invested, r.knockouts,
      case when v_rc.id is null then 0
           else public.calc_points(v_rc.method, v_rc.params, r.finish_position, v_entries,
                                   r.knockouts, t.buyin_cents, v_rc.bonus_per_ko, v_rc.bonus_entry)
      end,
      coalesce(t.ended_at, now())
    );
    v_written := v_written + 1;
  end loop;

  update tournaments
  set status = 'finished',
      clock = 'stopped',
      ended_at = coalesce(ended_at, now())
  where id = p_tournament_id;

  return v_written;
end;
$$;

-- ---------------------------------------------------------------------------
-- Seizoensklassement
-- ---------------------------------------------------------------------------
-- count_best_n wordt hier toegepast: veel clubs laten alleen de beste N
-- resultaten meetellen.

create or replace function public.season_standings(p_season_id uuid)
returns table (
  player_id      uuid,
  display_name   text,
  tournaments    int,
  counted        int,
  points         numeric,
  best_position  int,
  cashes         int,
  total_prize    int,
  knockouts      int
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_best_n int;
  v_min    int;
  v_club   uuid;
begin
  select s.club_id, rc.count_best_n, rc.min_tournaments
  into v_club, v_best_n, v_min
  from seasons s
  left join ranking_configs rc on rc.id = s.ranking_config_id
  where s.id = p_season_id;

  if v_club is null then
    return;
  end if;

  -- Klassement is voor staf en leden van de club. Een publieke ranking over
  -- clubs heen komt later en krijgt een eigen, expliciet publieke functie.
  if not public.is_service_context()
     and not public.is_club_member(v_club)
     and not public.is_club_player(v_club)
  then
    raise exception 'Geen rechten op het klassement van deze club'
      using errcode = 'insufficient_privilege';
  end if;

  return query
  with ranked as (
    select r.*,
           row_number() over (partition by r.player_id order by r.points desc) as rn
    from tournament_results r
    where r.season_id = p_season_id
  ),
  agg as (
    select ranked.player_id,
           count(*)::int                                                as tournaments,
           count(*) filter (where v_best_n is null or rn <= v_best_n)::int as counted,
           sum(ranked.points) filter (where v_best_n is null or rn <= v_best_n) as points,
           min(ranked.position)::int                                    as best_position,
           count(*) filter (where ranked.prize_cents > 0)::int          as cashes,
           sum(ranked.prize_cents + ranked.bounty_cents)::int           as total_prize,
           sum(ranked.knockouts)::int                                   as knockouts
    from ranked
    group by ranked.player_id
  )
  select a.player_id, p.display_name, a.tournaments, a.counted,
         round(coalesce(a.points, 0), 2), a.best_position, a.cashes,
         a.total_prize, a.knockouts
  from agg a
  join players p on p.id = a.player_id
  where a.tournaments >= coalesce(v_min, 0)
  order by 5 desc, a.best_position asc;
end;
$$;

-- =========================================================================
-- 0003_rls.sql
-- =========================================================================

-- Pokerleague — row level security.
-- Uitgangspunt: alles dicht, dan gericht openzetten. Een club mag nooit
-- data van een andere club zien, en het geldregister is nooit zichtbaar
-- voor spelers.

-- De helperfuncties (is_club_member, has_club_role, is_club_player,
-- can_view_tournament, shares_club_with) staan in 0002 en moeten dus eerst
-- gedraaid zijn.

-- ---------------------------------------------------------------------------
alter table clubs               enable row level security;
alter table club_members        enable row level security;
alter table players             enable row level security;
alter table club_players        enable row level security;
alter table player_invites      enable row level security;
alter table blind_structures    enable row level security;
alter table blind_levels        enable row level security;
alter table payout_templates    enable row level security;
alter table ranking_configs     enable row level security;
alter table seasons             enable row level security;
alter table tournaments         enable row level security;
alter table tournament_tables   enable row level security;
alter table tournament_players  enable row level security;
alter table buyins              enable row level security;
alter table eliminations        enable row level security;
alter table tournament_results  enable row level security;
alter table audit_log           enable row level security;

-- ---------------------------------------------------------------------------
-- Clubs — de clubgids is publiek, beheer niet.
-- ---------------------------------------------------------------------------

create policy clubs_read on clubs
  for select using (is_active or public.is_club_member(id));

create policy clubs_update on clubs
  for update using (public.has_club_role(id, array['owner','admin']::club_role[]));

-- ---------------------------------------------------------------------------
-- Staf
-- ---------------------------------------------------------------------------

create policy club_members_read on club_members
  for select using (user_id = auth.uid() or public.is_club_member(club_id));

create policy club_members_write on club_members
  for all using (public.has_club_role(club_id, array['owner','admin']::club_role[]))
  with check (public.has_club_role(club_id, array['owner','admin']::club_role[]));

-- ---------------------------------------------------------------------------
-- Spelers
-- ---------------------------------------------------------------------------
-- Zichtbaar als: het is je eigen profiel, je deelt een club, staf van een club
-- waar de speler lid is, of de speler heeft zijn profiel publiek gezet.

create policy players_read on players
  for select using (
    auth_user_id = auth.uid()
    or public_profile
    or public.shares_club_with(id)
    or exists (
      select 1 from club_players cp
      where cp.player_id = players.id and public.is_club_member(cp.club_id)
    )
  );

create policy players_self_update on players
  for update using (auth_user_id = auth.uid())
  with check (auth_user_id = auth.uid());

-- Staf mag schaduwprofielen aanmaken en bijwerken voor de eigen club.
create policy players_staff_insert on players
  for insert with check (
    exists (select 1 from club_members cm
            where cm.user_id = auth.uid()
              and cm.role in ('owner','admin','floor'))
  );

create policy players_staff_update on players
  for update using (
    link_state = 'shadow'
    and exists (
      select 1 from club_players cp
      where cp.player_id = players.id
        and public.has_club_role(cp.club_id, array['owner','admin','floor']::club_role[])
    )
  );

create policy club_players_read on club_players
  for select using (
    public.is_club_member(club_id)
    or exists (select 1 from players p
               where p.id = club_players.player_id and p.auth_user_id = auth.uid())
  );

create policy club_players_write on club_players
  for all using (public.has_club_role(club_id, array['owner','admin','floor']::club_role[]))
  with check (public.has_club_role(club_id, array['owner','admin','floor']::club_role[]));

create policy player_invites_staff on player_invites
  for all using (public.has_club_role(club_id, array['owner','admin']::club_role[]))
  with check (public.has_club_role(club_id, array['owner','admin']::club_role[]));

-- ---------------------------------------------------------------------------
-- Configuratie — platformsjablonen (club_id null) leest iedereen.
-- ---------------------------------------------------------------------------

create policy blind_structures_read on blind_structures
  for select using (club_id is null or public.is_club_member(club_id));

create policy blind_structures_write on blind_structures
  for all using (club_id is not null and public.has_club_role(club_id, array['owner','admin']::club_role[]))
  with check (club_id is not null and public.has_club_role(club_id, array['owner','admin']::club_role[]));

create policy blind_levels_read on blind_levels
  for select using (
    exists (select 1 from blind_structures s
            where s.id = blind_levels.structure_id
              and (s.club_id is null or public.is_club_member(s.club_id)))
  );

create policy blind_levels_write on blind_levels
  for all using (
    exists (select 1 from blind_structures s
            where s.id = blind_levels.structure_id
              and s.club_id is not null
              and public.has_club_role(s.club_id, array['owner','admin']::club_role[]))
  )
  with check (
    exists (select 1 from blind_structures s
            where s.id = blind_levels.structure_id
              and s.club_id is not null
              and public.has_club_role(s.club_id, array['owner','admin']::club_role[]))
  );

create policy payout_templates_read on payout_templates
  for select using (club_id is null or public.is_club_member(club_id));

create policy payout_templates_write on payout_templates
  for all using (club_id is not null and public.has_club_role(club_id, array['owner','admin']::club_role[]))
  with check (club_id is not null and public.has_club_role(club_id, array['owner','admin']::club_role[]));

create policy ranking_configs_read on ranking_configs
  for select using (club_id is null or public.is_club_member(club_id) or public.is_club_player(club_id));

create policy ranking_configs_write on ranking_configs
  for all using (club_id is not null and public.has_club_role(club_id, array['owner','admin']::club_role[]))
  with check (club_id is not null and public.has_club_role(club_id, array['owner','admin']::club_role[]));

-- ---------------------------------------------------------------------------
-- Seizoenen en tornooien
-- ---------------------------------------------------------------------------

create policy seasons_read on seasons
  for select using (public.is_club_member(club_id) or public.is_club_player(club_id));

create policy seasons_write on seasons
  for all using (public.has_club_role(club_id, array['owner','admin']::club_role[]))
  with check (public.has_club_role(club_id, array['owner','admin']::club_role[]));

create policy tournaments_read on tournaments
  for select using (
    public.is_club_member(club_id)
    or player_visibility = 'public'
    or (player_visibility = 'members' and public.is_club_player(club_id))
  );

create policy tournaments_write on tournaments
  for all using (public.has_club_role(club_id, array['owner','admin','floor']::club_role[]))
  with check (public.has_club_role(club_id, array['owner','admin','floor']::club_role[]));

create policy tournament_tables_read on tournament_tables
  for select using (public.can_view_tournament(tournament_id));

create policy tournament_tables_write on tournament_tables
  for all using (public.has_club_role(club_id, array['owner','admin','floor']::club_role[]))
  with check (public.has_club_role(club_id, array['owner','admin','floor']::club_role[]));

-- Deelnemerslijst is zichtbaar zodra het tornooi zichtbaar is: dit voedt
-- "wie staat er aan de leiding" in de spelersapp.
create policy tournament_players_read on tournament_players
  for select using (public.can_view_tournament(tournament_id));

create policy tournament_players_write on tournament_players
  for all using (public.has_club_role(club_id, array['owner','admin','floor']::club_role[]))
  with check (public.has_club_role(club_id, array['owner','admin','floor']::club_role[]));

-- ---------------------------------------------------------------------------
-- Geldregister — uitsluitend staf. Geen enkele spelerslees-policy.
-- ---------------------------------------------------------------------------

create policy buyins_staff on buyins
  for all using (public.has_club_role(club_id, array['owner','admin','floor']::club_role[]))
  with check (public.has_club_role(club_id, array['owner','admin','floor']::club_role[]));

create policy eliminations_read on eliminations
  for select using (public.can_view_tournament(tournament_id));

create policy eliminations_write on eliminations
  for all using (public.has_club_role(club_id, array['owner','admin','floor']::club_role[]))
  with check (public.has_club_role(club_id, array['owner','admin','floor']::club_role[]));

-- ---------------------------------------------------------------------------
-- Resultaten — de leeslaag van de spelersapp.
-- ---------------------------------------------------------------------------

create policy tournament_results_read on tournament_results
  for select using (
    public.can_view_tournament(tournament_id)
    or exists (select 1 from players p
               where p.id = tournament_results.player_id and p.auth_user_id = auth.uid())
  );

create policy tournament_results_write on tournament_results
  for all using (public.has_club_role(club_id, array['owner','admin']::club_role[]))
  with check (public.has_club_role(club_id, array['owner','admin']::club_role[]));

create policy audit_log_read on audit_log
  for select using (public.has_club_role(club_id, array['owner','admin']::club_role[]));

-- ---------------------------------------------------------------------------
-- Rechten
-- ---------------------------------------------------------------------------
-- Supabase zet dit doorgaans al goed via default privileges, maar expliciet
-- is beter dan hopen. RLS blijft de echte poort: een grant zonder policy
-- levert nog steeds nul rijen op.
-- De DO-blokken maken dit ook draaibaar op een kale Postgres, waar de
-- Supabase-rollen niet bestaan.

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    grant usage on schema public to anon;
    grant select on all tables in schema public to anon;
  end if;

  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant usage on schema public to authenticated;
    grant select, insert, update, delete on all tables in schema public to authenticated;
    grant usage, select on all sequences in schema public to authenticated;
  end if;

  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant usage on schema public to service_role;
    grant all on all tables in schema public to service_role;
    grant all on all sequences in schema public to service_role;
  end if;
end $$;

-- =========================================================================
-- 0004_realtime.sql
-- =========================================================================

-- Pokerleague — realtime
--
-- Zonder dit stuurt Supabase geen wijzigingen door en moet elk scherm
-- pollen. De zaalweergave en het floor-scherm zijn twee losse apparaten die
-- dezelfde klok tonen; die moeten binnen een seconde gelijk lopen.
--
-- RLS blijft gelden op de realtime-stroom: een client krijgt alleen
-- wijzigingen door van rijen die hij ook via een gewone query mag zien.

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then

    -- De klok zelf. Dit is de belangrijkste.
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public'
        and tablename = 'tournaments'
    ) then
      alter publication supabase_realtime add table public.tournaments;
    end if;

    -- Deelnemers: aantal over, chipcounts, uitschakelingen.
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public'
        and tablename = 'tournament_players'
    ) then
      alter publication supabase_realtime add table public.tournament_players;
    end if;

    -- Prijzenpot loopt mee met de inkopen. Alleen staf ziet deze rijen.
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public'
        and tablename = 'buyins'
    ) then
      alter publication supabase_realtime add table public.buyins;
    end if;

  end if;
end $$;

-- Realtime stuurt bij een update standaard alleen de gewijzigde kolommen mee
-- en bij een delete helemaal niets. Voor tournaments willen we de volledige
-- oude rij kunnen zien, zodat een client kan bepalen wat er veranderd is
-- zonder meteen opnieuw te moeten laden.
alter table public.tournaments replica identity full;

-- =========================================================================
-- 0005_players.sql
-- =========================================================================

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

-- =========================================================================
-- 0006_structures.sql
-- =========================================================================

-- Pokerleague — blindstructuren bewerken
--
-- Een structuur opslaan betekent alle levels vervangen. Vanuit de browser zou
-- dat twee losse aanroepen zijn: eerst wissen, dan invoegen. Gaat de tweede
-- mis of valt de wifi weg, dan staat er een structuur zonder levels — en dat
-- is precies de structuur waar een tornooi aan hangt.
--
-- Vandaar één functie die het in één transactie doet.

create or replace function public.replace_blind_levels(
  p_structure_id uuid,
  p_levels       jsonb
)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_club  uuid;
  v_lvl   jsonb;
  v_idx   int := 0;
  v_count int;
begin
  select club_id into v_club from blind_structures where id = p_structure_id;
  if not found then
    raise exception 'Blindstructuur bestaat niet';
  end if;

  -- Platformsjablonen (club_id null) zijn voor iedereen leesbaar maar door
  -- niemand te wijzigen; die horen alleen via een migratie te veranderen.
  if v_club is null then
    raise exception 'Een platformsjabloon kan je niet aanpassen. Maak er een kopie van.'
      using errcode = 'insufficient_privilege';
  end if;

  if not public.is_service_context()
     and not public.has_club_role(v_club, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten om deze structuur te wijzigen'
      using errcode = 'insufficient_privilege';
  end if;

  if jsonb_typeof(p_levels) <> 'array' or jsonb_array_length(p_levels) = 0 then
    raise exception 'Een structuur moet minstens één level bevatten'
      using errcode = 'check_violation';
  end if;

  delete from blind_levels where structure_id = p_structure_id;

  for v_lvl in select * from jsonb_array_elements(p_levels) loop
    insert into blind_levels (
      structure_id, idx, is_break, label, small_blind, big_blind, ante, duration_s
    ) values (
      p_structure_id,
      v_idx,
      coalesce((v_lvl->>'is_break')::boolean, false),
      nullif(trim(coalesce(v_lvl->>'label', '')), ''),
      greatest(coalesce((v_lvl->>'small_blind')::int, 0), 0),
      greatest(coalesce((v_lvl->>'big_blind')::int, 0), 0),
      greatest(coalesce((v_lvl->>'ante')::int, 0), 0),
      -- Nul seconden zou de klok laten doorrollen zonder ooit te stoppen.
      greatest(coalesce((v_lvl->>'duration_s')::int, 0), 30)
    );
    v_idx := v_idx + 1;
  end loop;

  select count(*) into v_count from blind_levels where structure_id = p_structure_id;
  return v_count;
end;
$$;

-- Kopie maken van een bestaande structuur, inclusief levels. Handig om een
-- platformsjabloon of een vorig seizoen als vertrekpunt te nemen.
create or replace function public.duplicate_blind_structure(
  p_structure_id uuid,
  p_club_id      uuid,
  p_name         text
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_new uuid;
begin
  if not public.is_service_context()
     and not public.has_club_role(p_club_id, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten om structuren aan te maken voor deze club'
      using errcode = 'insufficient_privilege';
  end if;

  if not exists (
    select 1 from blind_structures s
    where s.id = p_structure_id and (s.club_id is null or s.club_id = p_club_id)
  ) then
    raise exception 'Bronstructuur niet gevonden';
  end if;

  insert into blind_structures (club_id, name, description)
  select p_club_id, p_name, description
  from blind_structures where id = p_structure_id
  returning id into v_new;

  insert into blind_levels (structure_id, idx, is_break, label, small_blind, big_blind, ante, duration_s)
  select v_new, idx, is_break, label, small_blind, big_blind, ante, duration_s
  from blind_levels where structure_id = p_structure_id
  order by idx;

  return v_new;
end;
$$;

-- =========================================================================
-- 0007_public_rankings.sql
-- =========================================================================

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

-- =========================================================================
-- 0008_floor.sql
-- =========================================================================

-- Pokerleague — handelingen van de floor tijdens een tornooi
--
-- Waarom dit in de database staat en niet in de browser: elke handeling
-- hieronder raakt meerdere tabellen tegelijk. Een speler toevoegen betekent
-- een profiel, een clublidmaatschap, een deelname én een inkoop. Doet de
-- browser dat in vier losse aanroepen en valt de wifi weg na de derde, dan
-- staat er iemand aan tafel die niet betaald heeft.
--
-- En de eindplaats bij een uitschakeling moet de server bepalen. Twee
-- toestellen die tegelijk iemand wegklikken zouden anders allebei dezelfde
-- plaats uitdelen, en dan klopt je hele uitslag niet meer.

-- ---------------------------------------------------------------------------
-- Speler toevoegen en meteen laten inkopen
-- ---------------------------------------------------------------------------
-- Geef ofwel een bestaande p_player_id mee, ofwel p_new_name voor iemand die
-- er voor het eerst is. Dat tweede geval is de rij aan de deur: enkel een
-- naam, geen account, geen formulier.

create or replace function public.floor_add_entry(
  p_tournament_id uuid,
  p_player_id     uuid default null,
  p_new_name      text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  t        tournaments%rowtype;
  v_player uuid;
  v_tp     uuid;
begin
  select * into t from tournaments where id = p_tournament_id;
  if not found then
    raise exception 'Tornooi bestaat niet';
  end if;

  if not public.is_service_context()
     and not public.has_club_role(t.club_id, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten om spelers toe te voegen'
      using errcode = 'insufficient_privilege';
  end if;

  if t.status in ('finished', 'cancelled') then
    raise exception 'Dit tornooi is afgelopen' using errcode = 'check_violation';
  end if;

  if p_player_id is not null then
    v_player := public.resolve_player(p_player_id);
  else
    if coalesce(trim(p_new_name), '') = '' then
      raise exception 'Geef een naam op' using errcode = 'check_violation';
    end if;
    insert into players (display_name) values (trim(p_new_name)) returning id into v_player;
  end if;

  insert into club_players (club_id, player_id, joined_on)
  values (t.club_id, v_player, current_date)
  on conflict (club_id, player_id) do nothing;

  -- Al ingeschreven? Dan niets dubbel boeken, gewoon teruggeven.
  select id into v_tp from tournament_players
  where tournament_id = p_tournament_id and player_id = v_player;

  if v_tp is not null then
    return v_tp;
  end if;

  insert into tournament_players (
    club_id, tournament_id, player_id, status, chip_count
  ) values (
    t.club_id, p_tournament_id, v_player, 'active', t.starting_stack
  )
  returning id into v_tp;

  insert into buyins (
    club_id, tournament_id, tournament_player_id, player_id,
    kind, amount_cents, fee_cents, bounty_cents, recorded_by
  ) values (
    t.club_id, p_tournament_id, v_tp, v_player,
    'buyin', t.buyin_cents, t.fee_cents,
    case when t.bounty_mode = 'none' then 0 else t.bounty_cents end,
    auth.uid()
  );

  -- Een inschrijving vooraf is nu een deelname geworden.
  update tournament_registrations
  set cancelled_at = coalesce(cancelled_at, now())
  where tournament_id = p_tournament_id and player_id = v_player and cancelled_at is null;

  return v_tp;
end;
$$;

-- ---------------------------------------------------------------------------
-- Opnieuw inkopen: re-entry, rebuy of addon
-- ---------------------------------------------------------------------------

create or replace function public.floor_rebuy(
  p_tournament_player_id uuid,
  p_kind                 buyin_kind default 'reentry'
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  tp tournament_players%rowtype;
  t  tournaments%rowtype;
begin
  select * into tp from tournament_players where id = p_tournament_player_id;
  if not found then
    raise exception 'Deelnemer bestaat niet';
  end if;
  select * into t from tournaments where id = tp.tournament_id;

  if not public.is_service_context()
     and not public.has_club_role(tp.club_id, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten' using errcode = 'insufficient_privilege';
  end if;

  if p_kind = 'buyin' then
    raise exception 'Gebruik floor_add_entry voor de eerste inkoop' using errcode = 'check_violation';
  end if;

  insert into buyins (
    club_id, tournament_id, tournament_player_id, player_id,
    kind, amount_cents, fee_cents, bounty_cents, recorded_by
  ) values (
    tp.club_id, tp.tournament_id, tp.id, tp.player_id,
    p_kind,
    case when p_kind = 'addon' then coalesce(t.addon_cents, t.buyin_cents) else t.buyin_cents end,
    case when p_kind = 'addon' then 0 else t.fee_cents end,
    case when t.bounty_mode = 'none' or p_kind = 'addon' then 0 else t.bounty_cents end,
    auth.uid()
  );

  -- Een re-entry brengt een uitgeschakelde speler terug aan tafel; een rebuy
  -- of addon geeft alleen chips aan wie er al zit.
  update tournament_players
  set status          = case when p_kind = 'reentry' then 'active' else status end,
      finish_position = case when p_kind = 'reentry' then null else finish_position end,
      eliminated_at   = case when p_kind = 'reentry' then null else eliminated_at end,
      -- Een re-entry begint van nul af aan met een verse stack; een rebuy of
      -- addon legt chips bij wat er al ligt.
      chip_count      = case
                          when p_kind = 'reentry' then t.starting_stack
                          when p_kind = 'addon'
                            then coalesce(chip_count, 0) + coalesce(t.addon_stack, t.starting_stack)
                          else coalesce(chip_count, 0) + t.starting_stack
                        end
  where id = tp.id;

  -- Bij een re-entry schuift iedereen die na hem afviel een plaats op, anders
  -- staan er straks twee spelers op dezelfde eindplaats.
  if p_kind = 'reentry' and tp.finish_position is not null then
    update tournament_players
    set finish_position = finish_position - 1
    where tournament_id = tp.tournament_id
      and finish_position is not null
      and finish_position < tp.finish_position;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Uitschakelen
-- ---------------------------------------------------------------------------
-- De eindplaats wordt hier berekend en niet door de browser meegegeven: twee
-- toestellen die tegelijk iemand wegklikken moeten verschillende plaatsen
-- krijgen. De rijvergrendeling hieronder dwingt dat af.

create or replace function public.floor_eliminate(
  p_tournament_player_id uuid,
  p_by_tournament_player_id uuid default null
)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  tp       tournament_players%rowtype;
  t        tournaments%rowtype;
  v_pos    int;
  v_bounty int := 0;
begin
  select * into tp from tournament_players where id = p_tournament_player_id;
  if not found then
    raise exception 'Deelnemer bestaat niet';
  end if;

  if not public.is_service_context()
     and not public.has_club_role(tp.club_id, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten' using errcode = 'insufficient_privilege';
  end if;

  if tp.status = 'eliminated' then
    return tp.finish_position;
  end if;

  select * into t from tournaments where id = tp.tournament_id;

  -- Vergrendel het tornooi zodat twee gelijktijdige uitschakelingen netjes
  -- na elkaar gebeuren in plaats van dezelfde plaats te pakken.
  perform 1 from tournaments where id = tp.tournament_id for update;

  select count(*) into v_pos
  from tournament_players
  where tournament_id = tp.tournament_id and status in ('active', 'registered');

  -- De chipcount blijft staan. Dat een speler geen chips meer heeft volgt al
  -- uit zijn status; hem hier op nul zetten betekent dat een verkeerde klik
  -- die je meteen terugdraait zijn stack wel definitief wist.
  update tournament_players
  set status = 'eliminated', finish_position = v_pos, eliminated_at = now()
  where id = tp.id;

  if t.bounty_mode <> 'none' and p_by_tournament_player_id is not null then
    v_bounty := t.bounty_cents;
    update tournament_players
    set bounties_won = bounties_won + 1
    where id = p_by_tournament_player_id;
  end if;

  insert into eliminations (
    club_id, tournament_id, tournament_player_id, eliminated_by_id,
    position, bounty_cents, recorded_by
  ) values (
    tp.club_id, tp.tournament_id, tp.id, p_by_tournament_player_id,
    v_pos, v_bounty, auth.uid()
  );

  return v_pos;
end;
$$;

-- Uitschakeling terugdraaien. Gebeurt vaker dan je denkt: verkeerde naam
-- aangeklikt terwijl er drie mensen tegelijk iets vragen.
create or replace function public.floor_undo_elimination(p_tournament_player_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  tp tournament_players%rowtype;
begin
  select * into tp from tournament_players where id = p_tournament_player_id;
  if not found then
    raise exception 'Deelnemer bestaat niet';
  end if;

  if not public.is_service_context()
     and not public.has_club_role(tp.club_id, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten' using errcode = 'insufficient_privilege';
  end if;

  if tp.status <> 'eliminated' then
    return;
  end if;

  -- Iedereen die ná hem afviel schuift een plaats op.
  update tournament_players
  set finish_position = finish_position - 1
  where tournament_id = tp.tournament_id
    and finish_position is not null
    and finish_position < tp.finish_position;

  delete from eliminations
  where tournament_player_id = tp.id
    and position = tp.finish_position;

  update tournament_players
  set status = 'active', finish_position = null, eliminated_at = null
  where id = tp.id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Tornooi afsluiten
-- ---------------------------------------------------------------------------
-- Wie nog aan tafel zit krijgt de bovenste plaatsen, op chipcount gesorteerd.
-- Daarna berekent finalize_tournament prijzengeld en punten.

create or replace function public.floor_finish_tournament(p_tournament_id uuid)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  t     tournaments%rowtype;
  r     record;
  v_pos int;
begin
  select * into t from tournaments where id = p_tournament_id;
  if not found then
    raise exception 'Tornooi bestaat niet';
  end if;

  if not public.is_service_context()
     and not public.has_club_role(t.club_id, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten' using errcode = 'insufficient_privilege';
  end if;

  select count(*) into v_pos
  from tournament_players
  where tournament_id = p_tournament_id and status in ('active', 'registered');

  for r in
    select id from tournament_players
    where tournament_id = p_tournament_id and status in ('active', 'registered')
    order by coalesce(chip_count, 0) asc, registered_at desc
  loop
    update tournament_players
    set status = 'eliminated', finish_position = v_pos, eliminated_at = coalesce(eliminated_at, now())
    where id = r.id;
    v_pos := v_pos - 1;
  end loop;

  update tournaments set ended_at = coalesce(ended_at, now()) where id = p_tournament_id;

  return public.finalize_tournament(p_tournament_id);
end;
$$;

-- =========================================================================
-- 0009_club_mark.sql
-- =========================================================================

-- Pokerleague — het beeldmerk apart van het volledige logo
--
-- Een clublogo is meestal een blok: beeldmerk, naam en baseline samen, vaak
-- met een eigen achtergrond ingebakken. Dat plak je niet op een zaalscherm —
-- je ziet de rechthoek van het bestand tegen de achtergrond van de klok
-- afsteken, en de naam staat er dan twee keer.
--
-- Daarom een tweede verwijzing: alleen het beeldmerk, vrijstaand, met een
-- doorzichtige achtergrond. Dat kan groot en zacht achter de tijd staan
-- zonder rand. De clubnaam zetten we als tekst erboven, in de taal en het
-- lettertype van het platform.

alter table clubs
  add column if not exists mark_url text;

comment on column clubs.mark_url is
  'Alleen het beeldmerk, vrijstaand op een doorzichtige achtergrond (PNG of SVG). Wordt groot en vervaagd achter de zaalklok gezet. Leeg = geen watermerk, dan toont de klok enkel de clubnaam.';

-- =========================================================================
-- 0010_floor_email.sql
-- =========================================================================

-- Pokerleague — het mailadres als sleutel bij een nieuwe speler aan de deur
--
-- Waarom het mailadres en niet de naam: er zitten in België meer dan genoeg
-- mensen met dezelfde naam, en dezelfde man speelt volgend jaar misschien ook
-- bij een tweede club. Op naam matchen levert dan ofwel twee profielen voor
-- één speler, ofwel twee spelers samengeplakt tot één. Op het mailadres kan
-- geen van beide: er staat een unieke index op lower(email) over het hele
-- platform, niet per club.
--
-- Waarom er tóch een uitweg is: aan de deur staan er drie mensen tegelijk
-- iets te vragen. Wie een speler niet ingeschreven krijgt omdat die zijn
-- adres niet uit het hoofd kent, typt binnen de kortste keren jan@jan.be in.
-- Een vervuilde sleutel is erger dan een ontbrekende. Vandaar: verplicht,
-- tenzij de floor uitdrukkelijk zegt waarom niet — en dat leggen we vast.

-- ---------------------------------------------------------------------------
-- 1. Waarom er geen mailadres is
-- ---------------------------------------------------------------------------

alter table players
  add column if not exists no_email_reason text;

comment on column players.no_email_reason is
  'Ingevuld wanneer de floor een speler zonder mailadres toevoegde. Zo zie je achteraf wie je nog moet aanvullen én waarom het toen niet lukte.';

-- ---------------------------------------------------------------------------
-- 2. De uitnodiging komt in een wachtrij, ze vertrekt niet meteen
-- ---------------------------------------------------------------------------
-- Mail versturen vanuit deze functie zou betekenen dat de floor aan de deur
-- staat te wachten op een externe dienst. Dat mag nooit. Er komt een rij bij,
-- en iets anders leegt die rij.

alter table player_invites
  add column if not exists sent_at    timestamptz,
  add column if not exists last_error text;

comment on column player_invites.sent_at is
  'Leeg = staat nog in de wachtrij. De verzender vult dit in zodra de mail buiten is.';

create index if not exists player_invites_pending
  on player_invites (created_at) where sent_at is null and accepted_at is null;

-- Een token van 64 tekens, zonder pgcrypto: twee uuid''s aan elkaar volstaan
-- ruimschoots en gen_random_uuid() zit sinds PG13 in de kern.
create or replace function public.new_invite_token()
returns text
language sql
volatile
as $$
  select replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '')
$$;

-- ---------------------------------------------------------------------------
-- 3. Speler toevoegen, nu met mailadres
-- ---------------------------------------------------------------------------
-- De oude versie moet eerst weg. Twee functies met dezelfde naam waarvan de
-- ene drie en de andere vijf parameters met standaardwaarden heeft, maakt elke
-- aanroep met drie argumenten dubbelzinnig — Postgres weigert dan gewoon.

drop function if exists public.floor_add_entry(uuid, uuid, text);

create or replace function public.floor_add_entry(
  p_tournament_id   uuid,
  p_player_id       uuid    default null,
  p_new_name        text    default null,
  p_email           text    default null,
  p_no_email_reason text    default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  t        tournaments%rowtype;
  v_player uuid;
  v_tp     uuid;
  v_email  text := nullif(lower(trim(coalesce(p_email, ''))), '');
  v_reason text := nullif(trim(coalesce(p_no_email_reason, '')), '');
  v_name   text := nullif(trim(coalesce(p_new_name, '')), '');
begin
  select * into t from tournaments where id = p_tournament_id;
  if not found then
    raise exception 'Tornooi bestaat niet';
  end if;

  if not public.is_service_context()
     and not public.has_club_role(t.club_id, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten om spelers toe te voegen'
      using errcode = 'insufficient_privilege';
  end if;

  if t.status in ('finished', 'cancelled') then
    raise exception 'Dit tornooi is afgelopen' using errcode = 'check_violation';
  end if;

  if p_player_id is not null then
    -- Bestaand lid: het mailadres staat al in zijn profiel, daar raken we
    -- hier niet aan.
    v_player := public.resolve_player(p_player_id);
  else
    if v_name is null then
      raise exception 'Geef een naam op' using errcode = 'check_violation';
    end if;

    -- Zonder mailadres én zonder reden gaat het niet door. Dat is de hele
    -- afspraak: overslaan mag, maar niet stilzwijgend.
    if v_email is null and v_reason is null then
      raise exception 'Geef een mailadres op, of een reden waarom er geen is'
        using errcode = 'check_violation';
    end if;

    if v_email is not null then
      -- Losse controle, bewust ruim: een adres afkeuren dat wél bestaat is
      -- erger dan er eentje doorlaten dat straks bounct.
      if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[a-z]{2,}$' then
        raise exception 'Dat lijkt geen geldig mailadres' using errcode = 'check_violation';
      end if;

      -- Hier gebeurt het echte werk: bestaat deze speler al ergens op het
      -- platform, dan pikken we hém op in plaats van een tweede profiel te
      -- maken. Ook als hij bij een andere club zit — dat is precies waarom
      -- de spelers platformbreed staan en niet per club.
      select id into v_player
      from players
      where lower(email) = v_email and merged_into_id is null;
    end if;

    if v_player is null then
      insert into players (display_name, email, link_state, no_email_reason)
      values (
        v_name,
        v_email,
        (case when v_email is null then 'shadow' else 'invited' end)::player_link_state,
        case when v_email is null then v_reason end
      )
      returning id into v_player;

      -- Uitnodiging in de wachtrij. Hij vult zelf gebruikersnaam,
      -- geboortedatum, gemeente en zijn toestemming voor de klassementen aan.
      if v_email is not null then
        insert into player_invites (club_id, player_id, email, token, expires_at)
        values (t.club_id, v_player, v_email, public.new_invite_token(),
                now() + interval '30 days');
      end if;
    end if;
  end if;

  insert into club_players (club_id, player_id, joined_on)
  values (t.club_id, v_player, current_date)
  on conflict (club_id, player_id) do nothing;

  -- Al ingeschreven? Dan niets dubbel boeken, gewoon teruggeven.
  select id into v_tp from tournament_players
  where tournament_id = p_tournament_id and player_id = v_player;

  if v_tp is not null then
    return v_tp;
  end if;

  insert into tournament_players (
    club_id, tournament_id, player_id, status, chip_count
  ) values (
    t.club_id, p_tournament_id, v_player, 'active', t.starting_stack
  )
  returning id into v_tp;

  insert into buyins (
    club_id, tournament_id, tournament_player_id, player_id,
    kind, amount_cents, fee_cents, bounty_cents, recorded_by
  ) values (
    t.club_id, p_tournament_id, v_tp, v_player,
    'buyin', t.buyin_cents, t.fee_cents,
    case when t.bounty_mode = 'none' then 0 else t.bounty_cents end,
    auth.uid()
  );

  -- Een inschrijving vooraf is nu een deelname geworden.
  update tournament_registrations
  set cancelled_at = coalesce(cancelled_at, now())
  where tournament_id = p_tournament_id and player_id = v_player and cancelled_at is null;

  return v_tp;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Het mailadres achteraf alsnog invullen
-- ---------------------------------------------------------------------------
-- Wie aan de deur werd toegevoegd zonder adres, vul je later aan vanuit het
-- ledenbestand. Loopt via een functie en niet via een gewone update, omdat
-- er twee dingen tegelijk moeten gebeuren: het adres vastleggen én de
-- uitnodiging alsnog in de wachtrij zetten. En omdat het adres van iemand
-- anders kan blijken te zijn.

create or replace function public.set_player_email(
  p_player_id uuid,
  p_email     text,
  p_club_id   uuid
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_email    text := nullif(lower(trim(coalesce(p_email, ''))), '');
  v_existing uuid;
  v_player   uuid := public.resolve_player(p_player_id);
begin
  if not public.is_service_context()
     and not public.has_club_role(p_club_id, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten' using errcode = 'insufficient_privilege';
  end if;

  if v_email is null or v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[a-z]{2,}$' then
    raise exception 'Dat lijkt geen geldig mailadres' using errcode = 'check_violation';
  end if;

  -- Hoort dit adres al bij iemand anders, dan is dit dezelfde persoon en
  -- geven we die terug. Samenvoegen doen we hier niet automatisch: dat is
  -- een beslissing met gevolgen voor iemands historie.
  select id into v_existing from players
  where lower(email) = v_email and merged_into_id is null and id <> v_player;

  if v_existing is not null then
    return v_existing;
  end if;

  update players
  set email           = v_email,
      no_email_reason = null,
      link_state      = case when link_state = 'shadow' then 'invited' else link_state end
  where id = v_player;

  insert into player_invites (club_id, player_id, email, token, expires_at)
  values (p_club_id, v_player, v_email, public.new_invite_token(), now() + interval '30 days');

  return v_player;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Wie moet je nog aanvullen
-- ---------------------------------------------------------------------------

create or replace view public.club_players_without_email
with (security_invoker = true) as
select
  cp.club_id,
  p.id            as player_id,
  p.display_name,
  p.no_email_reason,
  cp.joined_on,
  (select count(*) from tournament_players tp
    where tp.player_id = p.id and tp.club_id = cp.club_id) as entries
from club_players cp
join players p on p.id = cp.player_id
where p.email is null
  and p.merged_into_id is null;

comment on view public.club_players_without_email is
  'Spelers die aan de deur werden toegevoegd zonder mailadres. security_invoker staat AAN: je ziet dus alleen de clubs waar je zelf rechten op hebt.';

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant select on public.club_players_without_email to authenticated;
  end if;
end $$;

-- =========================================================================
-- 0011_rls_recursion.sql
-- =========================================================================

-- Pokerleague — een lus tussen twee leesregels doorbreken
--
-- Het probleem, zoals het op het scherm kwam:
--   infinite recursion detected in policy for relation "players"
--
-- Twee policies verwezen naar elkaars tabel met een gewone subquery:
--
--   players_read       ... exists (select 1 from club_players ...)
--   club_players_read  ... exists (select 1 from players ...)
--
-- Op zo'n subquery past Postgres opnieuw row level security toe. Wie
-- `players` leest, triggert dus `club_players_read`, die op zijn beurt
-- `players_read` triggert, en zo verder. Zolang je één van beide tabellen
-- apart bevraagt valt dat niet op — Postgres kan de lus soms wegoptimaliseren.
-- Vraag je ze samen op (club_players mét de naam uit players, wat het
-- spelersbeheer aan de floor doet), dan slaat hij vast.
--
-- De oplossing is niet om de regel te versoepelen maar om de subquery uit de
-- policy te halen: een SECURITY DEFINER functie draait met de rechten van de
-- eigenaar en zet dus géén nieuwe RLS-ronde in gang. Precies dezelfde
-- voorwaarde, alleen niet meer in een kring.

-- ---------------------------------------------------------------------------
-- 1. De twee voorwaarden als functie
-- ---------------------------------------------------------------------------

-- Ben ik staf van een club waar deze speler lid is?
create or replace function public.staff_sees_player(p_player_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from club_players cp
    join club_members cm on cm.club_id = cp.club_id
    where cp.player_id = p_player_id
      and cm.user_id = auth.uid()
  );
$$;

comment on function public.staff_sees_player(uuid) is
  'Staf van een club mag de spelers van die club lezen. Als functie en niet als subquery in de policy, anders ontstaat er een lus met club_players_read.';

-- Ben ik staf met schrijfrecht bij een club waar deze speler lid is?
create or replace function public.staff_edits_player(p_player_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from club_players cp
    join club_members cm on cm.club_id = cp.club_id
    where cp.player_id = p_player_id
      and cm.user_id = auth.uid()
      and cm.role in ('owner', 'admin', 'floor')
  );
$$;

-- Is dit spelersprofiel van mij?
create or replace function public.is_my_player(p_player_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from players
    where id = p_player_id and auth_user_id = auth.uid()
  );
$$;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function public.staff_sees_player(uuid)  to authenticated;
    grant execute on function public.staff_edits_player(uuid) to authenticated;
    grant execute on function public.is_my_player(uuid)       to authenticated;
  end if;
  if exists (select 1 from pg_roles where rolname = 'anon') then
    grant execute on function public.staff_sees_player(uuid)  to anon;
    grant execute on function public.staff_edits_player(uuid) to anon;
    grant execute on function public.is_my_player(uuid)       to anon;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 2. De policies opnieuw, zonder kruisverwijzing
-- ---------------------------------------------------------------------------
-- Inhoudelijk verandert er niets aan wie wat mag zien.

drop policy if exists players_read on players;
create policy players_read on players
  for select using (
    auth_user_id = auth.uid()
    or public_profile
    or public.shares_club_with(id)
    or public.staff_sees_player(id)
  );

drop policy if exists players_staff_update on players;
create policy players_staff_update on players
  for update using (
    link_state = 'shadow'
    and public.staff_edits_player(id)
  );

drop policy if exists club_players_read on club_players;
create policy club_players_read on club_players
  for select using (
    public.is_club_member(club_id)
    or public.is_my_player(player_id)
  );

-- =========================================================================
-- 0012_floor_undo_buyin.sql
-- =========================================================================

-- Pokerleague — een verkeerd geboekte inkoop terugdraaien
--
-- Aanleiding: de knoppen voor rebuy, addon en uitschakelen staan naast
-- elkaar op hetzelfde rijtje. Een uitschakeling was al terug te draaien, een
-- inkoop niet — en dat is nu net de klik die geld kost. Eén misser en er
-- staat twintig euro extra in de prijzenpot die niemand betaald heeft, en de
-- uitbetaling aan het eind van de avond klopt niet meer.
--
-- Geen rij verwijderen maar op is_void zetten. Het geldregister is de
-- verantwoording tegenover het gedoogbeleid: daar hoort een fout in te staan
-- mét de reden waarom hij is rechtgezet, niet uit te verdwijnen. De teller
-- van sync_entry_counters kijkt al naar `not is_void`, dus die corrigeert
-- zichzelf zodra de rij geschrapt is.

-- ---------------------------------------------------------------------------
-- 1. Onthouden wat er op tafel lag vóór een re-entry
-- ---------------------------------------------------------------------------
-- Een re-entry overschrijft de chipcount met een verse startstack. Zonder de
-- oude waarde ergens te bewaren is terugdraaien verlieslatend: je krijgt de
-- speler wel terug op zijn plaats, maar zijn stapel van vóór de bust is weg.

alter table tournament_players
  add column if not exists stack_before_reentry int;

comment on column tournament_players.stack_before_reentry is
  'De chipcount van vlak voor de laatste re-entry. Enkel bedoeld om die re-entry ongedaan te kunnen maken.';

-- ---------------------------------------------------------------------------
-- 2. floor_rebuy bewaart die waarde
-- ---------------------------------------------------------------------------

create or replace function public.floor_rebuy(
  p_tournament_player_id uuid,
  p_kind                 buyin_kind default 'reentry'
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  tp tournament_players%rowtype;
  t  tournaments%rowtype;
begin
  select * into tp from tournament_players where id = p_tournament_player_id;
  if not found then
    raise exception 'Deelnemer bestaat niet';
  end if;
  select * into t from tournaments where id = tp.tournament_id;

  if not public.is_service_context()
     and not public.has_club_role(tp.club_id, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten' using errcode = 'insufficient_privilege';
  end if;

  if p_kind = 'buyin' then
    raise exception 'Gebruik floor_add_entry voor de eerste inkoop' using errcode = 'check_violation';
  end if;

  insert into buyins (
    club_id, tournament_id, tournament_player_id, player_id,
    kind, amount_cents, fee_cents, bounty_cents, recorded_by
  ) values (
    tp.club_id, tp.tournament_id, tp.id, tp.player_id,
    p_kind,
    -- Elke inkoop gaat voluit naar de prijzenpot. Een addon kan een ander
    -- bedrag hebben dan de buy-in; staat dat niet ingesteld, dan geldt de
    -- buy-in. Een rebuy en een re-entry kosten altijd de buy-in.
    case when p_kind = 'addon' then coalesce(t.addon_cents, t.buyin_cents) else t.buyin_cents end,
    -- De clubbijdrage betaal je één keer, bij je eerste inkoop van de avond.
    -- Bij een re-entry stap je opnieuw in en betaal je hem opnieuw; bij een
    -- addon niet, want je zat er al.
    case when p_kind = 'addon' then 0 else t.fee_cents end,
    case when t.bounty_mode = 'none' or p_kind = 'addon' then 0 else t.bounty_cents end,
    auth.uid()
  );

  update tournament_players
  set status          = case when p_kind = 'reentry' then 'active' else status end,
      finish_position = case when p_kind = 'reentry' then null else finish_position end,
      eliminated_at   = case when p_kind = 'reentry' then null else eliminated_at end,
      -- Bewaren wat er lag, zodat de re-entry terug te draaien is.
      stack_before_reentry = case when p_kind = 'reentry' then chip_count else stack_before_reentry end,
      chip_count      = case
                          when p_kind = 'reentry' then t.starting_stack
                          when p_kind = 'addon'
                            then coalesce(chip_count, 0) + coalesce(t.addon_stack, t.starting_stack)
                          else coalesce(chip_count, 0) + t.starting_stack
                        end
  where id = tp.id;

  -- Bij een re-entry schuift iedereen die na hem afviel een plaats op, anders
  -- staan er straks twee spelers op dezelfde eindplaats.
  if p_kind = 'reentry' and tp.finish_position is not null then
    update tournament_players
    set finish_position = finish_position - 1
    where tournament_id = tp.tournament_id
      and finish_position is not null
      and finish_position < tp.finish_position;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. De laatste inkoop terugdraaien
-- ---------------------------------------------------------------------------
-- Draait alleen de láátste terug, en enkel een rebuy, addon of re-entry. De
-- eerste inkoop van een speler hoort bij zijn deelname: die verwijder je niet
-- los, dan zou er iemand aan tafel zitten zonder betaald te hebben.

create or replace function public.floor_undo_last_buyin(p_tournament_player_id uuid)
returns buyin_kind
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  tp    tournament_players%rowtype;
  t     tournaments%rowtype;
  b     buyins%rowtype;
  v_pos int;
begin
  select * into tp from tournament_players where id = p_tournament_player_id;
  if not found then
    raise exception 'Deelnemer bestaat niet';
  end if;

  if not public.is_service_context()
     and not public.has_club_role(tp.club_id, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten' using errcode = 'insufficient_privilege';
  end if;

  select * into b
  from buyins
  where tournament_player_id = tp.id
    and not is_void
    and kind <> 'buyin'
  order by occurred_at desc, id desc
  limit 1;

  if not found then
    raise exception 'Er is geen inkoop om terug te draaien'
      using errcode = 'check_violation';
  end if;

  select * into t from tournaments where id = tp.tournament_id;

  update buyins
  set is_void = true,
      voided_reason = 'teruggedraaid door de floor'
  where id = b.id;

  if b.kind = 'reentry' then
    -- Terug naar uitgeschakeld, met de stapel van vóór de re-entry. De plaats
    -- laten we opnieuw berekenen in plaats van de oude te hergebruiken: er
    -- kan ondertussen iemand anders afgevallen zijn.
    select count(*) into v_pos
    from tournament_players
    where tournament_id = tp.tournament_id
      and status in ('active', 'registered')
      and id <> tp.id;

    update tournament_players
    set status               = 'eliminated',
        finish_position      = v_pos + 1,
        eliminated_at        = coalesce(eliminated_at, now()),
        chip_count           = coalesce(stack_before_reentry, 0),
        stack_before_reentry = null
    where id = tp.id;
  else
    update tournament_players
    set chip_count = greatest(
      0,
      coalesce(chip_count, 0) - case
        when b.kind = 'addon' then coalesce(t.addon_stack, t.starting_stack)
        else t.starting_stack
      end)
    where id = tp.id;
  end if;

  return b.kind;
end;
$$;

-- =========================================================================
-- 0013_entry_fees.sql
-- =========================================================================

-- Pokerleague — per soort inkoop bepalen wat er naar de club gaat
--
-- Tot nu toe was er één clubbijdrage die gold voor de buy-in én voor elke
-- rebuy of re-entry, en een addon droeg nooit iets bij. Dat is één club-
-- afspraak hard in de software gegoten, en clubs doen dit niet allemaal
-- hetzelfde: de ene vraagt op een rebuy geen bijdrage omdat de speler al
-- betaald heeft, de andere net wel omdat hij opnieuw een stapel krijgt, en
-- op een addon zit soms een klein bedrag voor de zaal.
--
-- Vanaf hier stelt de club het per soort in. Elke kolom mag leeg blijven;
-- dan geldt wat er vroeger gebeurde, zodat bestaande tornooien niet van
-- prijs veranderen omdat er een migratie langskwam.

alter table tournaments
  add column if not exists rebuy_cents     int,
  add column if not exists rebuy_fee_cents int,
  add column if not exists addon_fee_cents int;

comment on column tournaments.rebuy_cents is
  'Wat een rebuy of re-entry in de prijzenpot legt. Leeg = hetzelfde als de buy-in.';
comment on column tournaments.rebuy_fee_cents is
  'Clubbijdrage op een rebuy of re-entry. Leeg = dezelfde bijdrage als bij de buy-in.';
comment on column tournaments.addon_fee_cents is
  'Clubbijdrage op een addon. Leeg = geen bijdrage.';

-- ---------------------------------------------------------------------------
-- floor_rebuy rekent met de juiste bedragen
-- ---------------------------------------------------------------------------

create or replace function public.floor_rebuy(
  p_tournament_player_id uuid,
  p_kind                 buyin_kind default 'reentry'
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  tp tournament_players%rowtype;
  t  tournaments%rowtype;
  v_pot int;
  v_fee int;
begin
  select * into tp from tournament_players where id = p_tournament_player_id;
  if not found then
    raise exception 'Deelnemer bestaat niet';
  end if;
  select * into t from tournaments where id = tp.tournament_id;

  if not public.is_service_context()
     and not public.has_club_role(tp.club_id, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten' using errcode = 'insufficient_privilege';
  end if;

  if p_kind = 'buyin' then
    raise exception 'Gebruik floor_add_entry voor de eerste inkoop' using errcode = 'check_violation';
  end if;

  if p_kind = 'addon' then
    v_pot := coalesce(t.addon_cents, t.buyin_cents);
    v_fee := coalesce(t.addon_fee_cents, 0);
  else
    -- Rebuy én re-entry volgen dezelfde afspraak: je koopt opnieuw in.
    v_pot := coalesce(t.rebuy_cents, t.buyin_cents);
    v_fee := coalesce(t.rebuy_fee_cents, t.fee_cents);
  end if;

  insert into buyins (
    club_id, tournament_id, tournament_player_id, player_id,
    kind, amount_cents, fee_cents, bounty_cents, recorded_by
  ) values (
    tp.club_id, tp.tournament_id, tp.id, tp.player_id,
    p_kind, v_pot, v_fee,
    case when t.bounty_mode = 'none' or p_kind = 'addon' then 0 else t.bounty_cents end,
    auth.uid()
  );

  update tournament_players
  set status          = case when p_kind = 'reentry' then 'active' else status end,
      finish_position = case when p_kind = 'reentry' then null else finish_position end,
      eliminated_at   = case when p_kind = 'reentry' then null else eliminated_at end,
      stack_before_reentry = case when p_kind = 'reentry' then chip_count else stack_before_reentry end,
      chip_count      = case
                          when p_kind = 'reentry' then t.starting_stack
                          when p_kind = 'addon'
                            then coalesce(chip_count, 0) + coalesce(t.addon_stack, t.starting_stack)
                          else coalesce(chip_count, 0) + t.starting_stack
                        end
  where id = tp.id;

  if p_kind = 'reentry' and tp.finish_position is not null then
    update tournament_players
    set finish_position = finish_position - 1
    where tournament_id = tp.tournament_id
      and finish_position is not null
      and finish_position < tp.finish_position;
  end if;
end;
$$;

-- =========================================================================
-- 0014_standings_period.sql
-- =========================================================================

-- Pokerleague — klassement over een vrije periode
--
-- season_standings() blijft het echte seizoensklassement: dat past de regels
-- van de club toe, zoals "alleen je beste tien resultaten tellen mee" en
-- "minstens drie tornooien gespeeld". Die regels horen bij een seizoen en bij
-- niets anders.
--
-- Wat hier bijkomt is iets eenvoudigers: wie deed het goed in maart, of in
-- 2026. Daar hoort geen beste-tien-regel bij — dan zou "de maand maart" iets
-- anders betekenen dan wat er in maart gebeurd is. Alles in de periode telt,
-- punt.

create or replace function public.club_standings_period(
  p_club_id uuid,
  p_from    date,
  p_to      date
)
returns table (
  player_id      uuid,
  display_name   text,
  tournaments    int,
  points         numeric,
  best_position  int,
  cashes         int,
  total_prize    int,
  knockouts      int
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_tz text;
begin
  select c.timezone into v_tz from clubs c where c.id = p_club_id;
  if v_tz is null then
    return;
  end if;

  if not public.is_service_context()
     and not public.is_club_member(p_club_id)
     and not public.is_club_player(p_club_id)
  then
    raise exception 'Geen rechten op het klassement van deze club'
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select
    r.player_id,
    p.display_name,
    count(*)::int                        as tournaments,
    round(sum(r.points), 2)              as points,
    min(r.position)::int                 as best_position,
    count(*) filter (where r.prize_cents > 0)::int as cashes,
    coalesce(sum(r.prize_cents), 0)::int as total_prize,
    coalesce(sum(r.knockouts), 0)::int   as knockouts
  from tournament_results r
  join players p on p.id = r.player_id
  where r.club_id = p_club_id
    -- De datumgrenzen volgen de tijdzone van de club. Een tornooi dat om
    -- half één 's nachts eindigt hoort bij de avond ervoor, niet bij de
    -- volgende maand omdat de server in UTC staat.
    and (r.finished_at at time zone v_tz)::date >= p_from
    and (r.finished_at at time zone v_tz)::date <= p_to
  group by r.player_id, p.display_name
  order by points desc, best_position asc, p.display_name asc;
end;
$$;

comment on function public.club_standings_period(uuid, date, date) is
  'Klassement over een vrije periode (maand, jaar, ...). Telt álle resultaten in die periode. Voor het seizoensklassement met de beste-N-regel van de club: season_standings().';

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function public.club_standings_period(uuid, date, date) to authenticated;
  end if;
end $$;

-- =========================================================================
-- 0015_club_overview.sql
-- =========================================================================

-- Pokerleague — ledenbestand en cijfers van de club
--
-- Waarom dit functies zijn en geen queries in de browser: het gaat telkens om
-- een optelsom over drie of vier tabellen tegelijk. Dat in de app doen
-- betekent alles ophalen en in JavaScript optellen — traag zodra een club
-- twee seizoenen historie heeft, en het antwoord kan per scherm verschillen
-- omdat iedereen zijn eigen versie van "actief lid" verzint.
--
-- Alles hier is SECURITY DEFINER met een expliciete rechtencontrole bovenaan.
-- De strengste zit op het ledenbestand: daar staan mailadressen in, en die
-- horen alleen bij de staf van die club terecht te komen.

-- ---------------------------------------------------------------------------
-- 1. Het ledenbestand met de cijfers erbij
-- ---------------------------------------------------------------------------

create or replace function public.club_member_overview(p_club_id uuid)
returns table (
  player_id       uuid,
  display_name    text,
  username        text,
  email           text,
  no_email_reason text,
  link_state      player_link_state,
  joined_on       date,
  entries         int,
  last_played     timestamptz,
  best_position   int,
  cashes          int,
  total_prize     int,
  total_spent     int,
  knockouts       int
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  -- Mailadressen: alleen staf. Een gewone speler heeft hier niets te zoeken,
  -- ook niet als hij lid is van de club.
  if not public.is_service_context()
     and not public.has_club_role(p_club_id, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten op het ledenbestand van deze club'
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select
    p.id,
    p.display_name,
    p.username,
    p.email,
    p.no_email_reason,
    p.link_state,
    cp.joined_on,
    coalesce(st.entries, 0)::int,
    st.last_played,
    st.best_position::int,
    coalesce(st.cashes, 0)::int,
    coalesce(st.total_prize, 0)::int,
    coalesce(sp.spent, 0)::int,
    coalesce(st.knockouts, 0)::int
  from club_players cp
  join players p on p.id = cp.player_id
  left join lateral (
    select
      count(*)                                        as entries,
      max(r.finished_at)                              as last_played,
      min(r.position)                                 as best_position,
      count(*) filter (where r.prize_cents > 0)       as cashes,
      sum(r.prize_cents)                              as total_prize,
      sum(r.knockouts)                                as knockouts
    from tournament_results r
    where r.player_id = p.id and r.club_id = cp.club_id
  ) st on true
  left join lateral (
    select sum(b.amount_cents + b.fee_cents + b.bounty_cents) as spent
    from buyins b
    where b.player_id = p.id and b.club_id = cp.club_id and not b.is_void
  ) sp on true
  where cp.club_id = p_club_id
    and p.merged_into_id is null
  order by st.last_played desc nulls last, p.display_name;
end;
$$;

comment on function public.club_member_overview(uuid) is
  'Het ledenbestand van één club met de cijfers per speler. Alleen voor staf: er staan mailadressen in.';

-- ---------------------------------------------------------------------------
-- 2. De cijfers van de club over een periode
-- ---------------------------------------------------------------------------
-- Eén rij met alles erop. Bewust geen aparte functie per getal: die zouden
-- elk hun eigen WHERE hebben en dan gaan de cijfers na verloop van tijd uit
-- elkaar lopen.

create or replace function public.club_stats(
  p_club_id uuid,
  p_from    date,
  p_to      date
)
returns table (
  tournaments    int,
  entries        int,
  unique_players int,
  new_players    int,
  avg_entries    numeric,
  biggest_field  int,
  prize_cents    int,
  club_cents     int,
  bounty_cents   int,
  avg_minutes    int
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_tz text;
begin
  select c.timezone into v_tz from clubs c where c.id = p_club_id;
  if v_tz is null then
    return;
  end if;

  if not public.is_service_context()
     and not public.has_club_role(p_club_id, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten op de cijfers van deze club'
      using errcode = 'insufficient_privilege';
  end if;

  return query
  with tours as (
    select t.id, t.started_at, t.ended_at
    from tournaments t
    where t.club_id = p_club_id
      and t.status = 'finished'
      and t.ended_at is not null
      and (t.ended_at at time zone v_tz)::date between p_from and p_to
  ),
  res as (
    select r.* from tournament_results r
    join tours x on x.id = r.tournament_id
  ),
  geld as (
    select b.* from buyins b
    join tours x on x.id = b.tournament_id
    where not b.is_void
  ),
  velden as (
    select r.tournament_id, count(*) as n from res r group by r.tournament_id
  )
  select
    (select count(*) from tours)::int,
    (select count(*) from res)::int,
    (select count(distinct r.player_id) from res r)::int,
    -- Nieuw = deze periode voor het eerst bij deze club gespeeld.
    (select count(*) from (
       select r.player_id
       from res r
       group by r.player_id
       having not exists (
         select 1 from tournament_results o
         join tournaments ot on ot.id = o.tournament_id
         where o.player_id = r.player_id
           and o.club_id = p_club_id
           and (ot.ended_at at time zone v_tz)::date < p_from
       )
     ) q)::int,
    coalesce(round(avg(v.n), 1), 0),
    coalesce(max(v.n), 0)::int,
    (select coalesce(sum(g.amount_cents), 0) from geld g)::int,
    (select coalesce(sum(g.fee_cents), 0) from geld g)::int,
    (select coalesce(sum(g.bounty_cents), 0) from geld g)::int,
    (select coalesce(round(avg(extract(epoch from (x.ended_at - x.started_at)) / 60)), 0)
     from tours x where x.started_at is not null)::int
  from velden v;
end;
$$;

comment on function public.club_stats(uuid, date, date) is
  'Kerncijfers van een club over een periode: avonden, deelnames, geld en gemiddelde speelduur. Alleen afgesloten tornooien tellen mee.';

-- ---------------------------------------------------------------------------
-- 3. Verloop per maand, voor een grafiekje
-- ---------------------------------------------------------------------------

create or replace function public.club_month_series(
  p_club_id uuid,
  p_months  int default 12
)
returns table (
  month       date,
  tournaments int,
  entries     int,
  prize_cents int,
  club_cents  int
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_tz text;
begin
  select c.timezone into v_tz from clubs c where c.id = p_club_id;
  if v_tz is null then
    return;
  end if;

  if not public.is_service_context()
     and not public.has_club_role(p_club_id, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten op de cijfers van deze club'
      using errcode = 'insufficient_privilege';
  end if;

  return query
  with maanden as (
    -- Ook de lege maanden, anders springt een grafiek over een stille zomer
    -- heen alsof die er nooit geweest is.
    select generate_series(
      date_trunc('month', (now() at time zone v_tz)::date) - make_interval(months => greatest(p_months, 1) - 1),
      date_trunc('month', (now() at time zone v_tz)::date),
      interval '1 month'
    )::date as m
  ),
  tours as (
    select t.id, date_trunc('month', (t.ended_at at time zone v_tz))::date as m
    from tournaments t
    where t.club_id = p_club_id and t.status = 'finished' and t.ended_at is not null
  )
  select
    mm.m,
    (select count(*) from tours x where x.m = mm.m)::int,
    (select count(*) from tournament_results r
      join tours x on x.id = r.tournament_id where x.m = mm.m)::int,
    (select coalesce(sum(b.amount_cents), 0) from buyins b
      join tours x on x.id = b.tournament_id where x.m = mm.m and not b.is_void)::int,
    (select coalesce(sum(b.fee_cents), 0) from buyins b
      join tours x on x.id = b.tournament_id where x.m = mm.m and not b.is_void)::int
  from maanden mm
  order by mm.m;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Rechten
-- ---------------------------------------------------------------------------

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function public.club_member_overview(uuid)        to authenticated;
    grant execute on function public.club_stats(uuid, date, date)      to authenticated;
    grant execute on function public.club_month_series(uuid, int)      to authenticated;
  end if;
end $$;

-- =========================================================================
-- 0016_deal.sql
-- =========================================================================

-- Pokerleague — de deal aan de finaletafel
--
-- Wat er in een zaal gebeurt: er zitten nog drie of vier mensen, het is laat,
-- de blinds zijn hoog en iemand stelt voor om te verdelen. Dan wil de tafel
-- twee cijfers zien. ICM houdt rekening met de prijzenladder — een grote
-- stapel is niet evenredig meer waard, want je kan maar één keer eerste
-- worden. Chipchop verdeelt gewoon naar rato van de chips. Het verschil
-- tussen die twee is precies waar de discussie over gaat, dus ze horen naast
-- elkaar op het scherm en niet één van de twee "omdat die eerlijker is".
--
-- De berekening zelf staat in de browser (src/lib/tournament/deal.ts, met
-- tests). Wat hier staat is het vastleggen: welk voorstel er op het
-- zaalscherm hangt, en wat er gebeurt als de tafel akkoord gaat. Dat hoort in
-- de database, want het zaalscherm en het floor-scherm zijn twee toestellen
-- die hetzelfde moeten tonen.

-- ---------------------------------------------------------------------------
-- 1. De prijzenladder van een lopend tornooi
-- ---------------------------------------------------------------------------
-- Het floor-scherm moet weten hoeveel er nog te verdelen valt. Dat is niet
-- de hele pot: wie al uitbetaald is aan plaats 5 en 6 telt niet meer mee.
-- Deze functie geeft de volledige ladder; de app pakt daar de bovenste N van,
-- met N het aantal spelers dat nog zit.

create or replace function public.tournament_prizes(p_tournament_id uuid)
returns table (place int, amount_cents int)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- De uitvoerkolommen heten net zo als de kolommen van calc_payouts. Zonder
-- deze regel weet plpgsql niet welke van de twee je bedoelt en weigert hij.
#variable_conflict use_column
declare
  t           tournaments%rowtype;
  v_prizepool int;
  v_entries   int;
  v_tiers     jsonb;
  v_rounding  int;
begin
  select * into t from tournaments where id = p_tournament_id;
  if not found then
    return;
  end if;

  if not public.is_service_context()
     and not public.has_club_role(t.club_id, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten' using errcode = 'insufficient_privilege';
  end if;

  select count(distinct player_id) into v_entries
  from tournament_players where tournament_id = p_tournament_id;

  select coalesce(sum(amount_cents), 0) into v_prizepool
  from buyins where tournament_id = p_tournament_id and not is_void;

  select coalesce(pt.tiers, '[{"min_entries":1,"percentages":[100]}]'::jsonb),
         coalesce(pt.rounding, 500)
  into v_tiers, v_rounding
  from tournaments tt
  left join payout_templates pt on pt.id = tt.payout_template_id
  where tt.id = p_tournament_id;

  return query
  select cp.place, cp.amount_cents
  from public.calc_payouts(v_prizepool, v_entries, v_tiers, v_rounding) cp
  order by cp.place;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Een voorstel op tafel leggen
-- ---------------------------------------------------------------------------
-- Hoogstens één openstaand voorstel per tornooi; die regel staat al als
-- unieke index op de tabel. Een nieuw voorstel vervangt dus het vorige in
-- plaats van ernaast te komen — anders hangt er een verouderd bedrag op de
-- muur terwijl de tafel het over iets anders heeft.

create or replace function public.deal_propose(
  p_tournament_id uuid,
  p_method        deal_method,
  p_shares        jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  t      tournaments%rowtype;
  v_id   uuid;
  v_pool int;
  v_sum  int;
begin
  select * into t from tournaments where id = p_tournament_id;
  if not found then
    raise exception 'Tornooi bestaat niet';
  end if;

  if not public.is_service_context()
     and not public.has_club_role(t.club_id, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten om een deal voor te stellen'
      using errcode = 'insufficient_privilege';
  end if;

  if t.status in ('finished', 'cancelled') then
    raise exception 'Dit tornooi is al afgelopen' using errcode = 'check_violation';
  end if;

  if jsonb_typeof(p_shares) <> 'array' or jsonb_array_length(p_shares) < 2 then
    raise exception 'Een deal heeft minstens twee spelers nodig'
      using errcode = 'check_violation';
  end if;

  select coalesce(sum((s->>'agreed_cents')::int), 0) into v_sum
  from jsonb_array_elements(p_shares) s;

  if v_sum <= 0 then
    raise exception 'De bedragen in het voorstel zijn leeg' using errcode = 'check_violation';
  end if;

  v_pool := v_sum;

  -- Het vorige voorstel intrekken in plaats van weggooien: je wil achteraf
  -- kunnen zien dat er twee keer onderhandeld is.
  update tournament_deals
  set status = 'rejected', decided_at = now()
  where tournament_id = p_tournament_id and status = 'proposed';

  insert into tournament_deals (
    club_id, tournament_id, method, status, pool_cents, shares, created_by
  ) values (
    t.club_id, p_tournament_id, p_method, 'proposed', v_pool, p_shares, auth.uid()
  )
  returning id into v_id;

  return v_id;
end;
$$;

-- Voorstel van tafel halen zonder akkoord.
create or replace function public.deal_cancel(p_tournament_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  t tournaments%rowtype;
begin
  select * into t from tournaments where id = p_tournament_id;
  if not found then
    return;
  end if;

  if not public.is_service_context()
     and not public.has_club_role(t.club_id, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten' using errcode = 'insufficient_privilege';
  end if;

  update tournament_deals
  set status = 'rejected', decided_at = now()
  where tournament_id = p_tournament_id and status = 'proposed';
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Akkoord: het tornooi eindigt met deze bedragen
-- ---------------------------------------------------------------------------
-- Eerst gewoon afsluiten zoals altijd — dat zet de eindplaatsen op chipcount
-- en berekent punten. Daarna overschrijven we het prijzengeld van wie in de
-- deal zat. De punten blijven wat ze zijn: die horen bij hoe ver je kwam, en
-- niet bij wat je onderhandelde.

create or replace function public.deal_accept(p_tournament_id uuid)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  t        tournaments%rowtype;
  d        tournament_deals%rowtype;
  v_rows   int;
  r        record;
begin
  select * into t from tournaments where id = p_tournament_id;
  if not found then
    raise exception 'Tornooi bestaat niet';
  end if;

  if not public.is_service_context()
     and not public.has_club_role(t.club_id, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten om deze deal te bevestigen'
      using errcode = 'insufficient_privilege';
  end if;

  select * into d from tournament_deals
  where tournament_id = p_tournament_id and status = 'proposed';

  if not found then
    raise exception 'Er ligt geen voorstel op tafel' using errcode = 'check_violation';
  end if;

  update tournament_deals
  set status = 'accepted', decided_at = now()
  where id = d.id;

  v_rows := public.floor_finish_tournament(p_tournament_id);

  -- Prijzengeld overschrijven voor wie meedeed aan de deal.
  for r in
    select (s->>'tournament_player_id')::uuid as tp_id,
           (s->>'agreed_cents')::int          as cents
    from jsonb_array_elements(d.shares) s
  loop
    update tournament_results tr
    set prize_cents = r.cents
    from tournament_players tp
    where tp.id = r.tp_id
      and tr.tournament_id = p_tournament_id
      and tr.player_id = tp.player_id;
  end loop;

  return v_rows;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Het zaalscherm mag het voorstel zien
-- ---------------------------------------------------------------------------
-- Realtime, want floor en beamer zijn twee toestellen die hetzelfde moeten
-- tonen op hetzelfde moment.

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'tournament_deals'
  ) then
    alter publication supabase_realtime add table tournament_deals;
  end if;
end $$;

alter table tournament_deals replica identity full;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function public.tournament_prizes(uuid)                       to authenticated;
    grant execute on function public.deal_propose(uuid, deal_method, jsonb)        to authenticated;
    grant execute on function public.deal_cancel(uuid)                             to authenticated;
    grant execute on function public.deal_accept(uuid)                             to authenticated;
  end if;
end $$;
