-- Pokerleague — volledige database-opzet
--
-- GEGENEREERD BESTAND. Bewerk supabase/migrations/*.sql en draai
-- `npm run db:bundle` opnieuw.
--
-- Plak dit in de SQL Editor van Supabase en draai het in één keer.
-- Draait op een lege database; bestaande tabellen worden niet aangeraakt
-- maar zullen wel een foutmelding geven.
--
-- Onderdelen: 0001_schema.sql · 0002_functions.sql · 0003_rls.sql · 0004_realtime.sql · 0005_players.sql · 0006_structures.sql

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
