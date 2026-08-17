-- Pokerleague — de publieke kant van een club
--
-- Tot nu was alles achter een login gezet. Dat klopte zolang er alleen een
-- floor en een beamer waren, maar op een tornooiavond zit er ook een zaal vol
-- mensen met een telefoon in de hand, en die willen iets simpels weten: hoe
-- lang nog dit level, hoeveel man zit er nog, wat staat er in de pot, en waar
-- sta ik in het klassement. Daar is geen account voor nodig en die vraag hoort
-- niet aan de floor gesteld te worden terwijl hij een rebuy staat te boeken.
--
-- Twee dingen die deze migratie moet oplossen.
--
-- **De blinds zijn niet leesbaar voor een buitenstaander.** blind_levels hangt
-- aan de club, en de policy laat alleen clubleden en platformsjablonen door.
-- Terecht — een concurrent hoeft niet in je structuren te grasduinen — maar
-- daardoor kan een speler de klok niet zien. Vandaar functies die precies de
-- levels van één publiek tornooi teruggeven en niets meer.
--
-- **Namen zijn persoonsgegevens.** Het platform toont buitenstaanders alleen
-- gebruikersnamen, en pas na toestemming van de speler; zie 0007. Dat is de
-- juiste regel voor pokerleague.be, waar clubs en spelers elkaar niet kennen.
-- Op de eigen pagina's van een club ligt het anders: daar staan de mensen die
-- die avond aan tafel zaten, en een uitslag met "Speler a3f2" erop is voor
-- niemand bruikbaar. Daarom kan een club zeggen dat hij namen toont — met de
-- verantwoordelijkheid die daarbij hoort, want dan moet die toestemming uit
-- het clubreglement of het aanmeldformulier komen.
--
-- Staat die schakelaar uit, dan draaien de pagina's gewoon door op
-- gebruikersnamen. Niets breekt; het leest alleen minder prettig.

-- ---------------------------------------------------------------------------
-- 1. Toont deze club namen op zijn eigen pagina's?
-- ---------------------------------------------------------------------------

alter table clubs add column if not exists public_names boolean not null default false;

comment on column clubs.public_names is
  'Mag deze club de namen van zijn spelers tonen op zijn eigen publieke paginas (uitslagen, klassement, deelnemerslijst)? Standaard nee. Zet een club dit aan, dan verklaart hij dat hij daarvoor toestemming heeft van zijn leden — via het clubreglement of het aanmeldformulier. Dit geldt uitsluitend voor de eigen paginas van de club; de landelijke ranglijsten van PokerLeague blijven werken op players.public_listing.';

-- De naamregel op één plek. Wie hem ergens anders overschrijft, lekt.
create or replace function public.public_name(
  p_display        text,
  p_username       text,
  p_id             uuid,
  p_public_listing boolean,
  p_public_profile boolean,
  p_club_names     boolean
)
returns text
language sql
immutable
as $$
  select case
    when coalesce(p_club_names, false)
      or (coalesce(p_public_listing, false) and coalesce(p_public_profile, false))
    then p_display
    else coalesce(nullif(trim(p_username), ''), 'Speler ' || left(p_id::text, 4))
  end;
$$;

comment on function public.public_name(text, text, uuid, boolean, boolean, boolean) is
  'De enige plek waar bepaald wordt of een buitenstaander een echte naam of een gebruikersnaam ziet.';

-- Mag deze buitenstaander dit tornooi bekijken? Bewust strenger dan
-- can_view_tournament: hier gaat het om wat er zonder account zichtbaar is,
-- dus alleen publieke tornooien van een actieve club.
create or replace function public.is_public_tournament(p_tournament_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from tournaments t
    join clubs c on c.id = t.club_id
    where t.id = p_tournament_id
      and t.player_visibility = 'public'
      and c.is_active
  );
$$;

-- ---------------------------------------------------------------------------
-- 2. De klok, zoals een speler hem op zijn telefoon ziet
-- ---------------------------------------------------------------------------
-- Eén rij met alles wat het scherm nodig heeft. Bewust geen geldregister: de
-- prijzenpot is een totaal en zegt niets over wie wat betaald heeft.

create or replace function public.club_public_clock(p_tournament_id uuid)
returns table (
  tournament_id    uuid,
  name             text,
  status           text,
  clock            text,
  level_idx        int,
  level_started_at timestamptz,
  level_elapsed_ms bigint,
  started_at       timestamptz,
  scheduled_at     timestamptz,
  starting_stack   int,
  addon_stack      int,
  late_reg_level   int,
  entry_cents      int,
  entries          int,
  players_left     int,
  rebuys           int,
  addons           int,
  prize_pool_cents int,
  club_slug        text,
  club_name        text,
  logo_url         text,
  mark_url         text,
  primary_color    text,
  currency         text,
  timezone         text
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    t.id, t.name, t.status::text, t.clock::text,
    t.level_idx, t.level_started_at, t.level_elapsed_ms,
    t.started_at, t.scheduled_at,
    t.starting_stack, t.addon_stack, t.late_reg_level,
    t.buyin_cents + t.fee_cents,
    (select count(*)::int from tournament_players tp where tp.tournament_id = t.id),
    (select count(*)::int from tournament_players tp
      where tp.tournament_id = t.id and tp.status in ('active', 'registered')),
    (select count(*)::int from buyins b
      where b.tournament_id = t.id and not b.is_void and b.kind in ('rebuy', 'reentry')),
    (select count(*)::int from buyins b
      where b.tournament_id = t.id and not b.is_void and b.kind = 'addon'),
    (select coalesce(sum(b.amount_cents), 0)::int from buyins b
      where b.tournament_id = t.id and not b.is_void),
    c.slug, c.name, c.logo_url, c.mark_url, c.primary_color, c.currency, c.timezone
  from tournaments t
  join clubs c on c.id = t.club_id
  where t.id = p_tournament_id
    and public.is_public_tournament(t.id);
$$;

-- De blindstructuur van dít tornooi, en niets anders. De structuren van de
-- club blijven dicht; alleen wat er vanavond gespeeld wordt is zichtbaar.
create or replace function public.club_public_levels(p_tournament_id uuid)
returns table (
  idx        int,
  is_break   boolean,
  label      text,
  small_blind int,
  big_blind  int,
  ante       int,
  duration_s int
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select bl.idx, bl.is_break, bl.label, bl.small_blind, bl.big_blind, bl.ante, bl.duration_s
  from tournaments t
  join blind_levels bl on bl.structure_id = t.structure_id
  where t.id = p_tournament_id
    and public.is_public_tournament(t.id)
  order by bl.idx;
$$;

-- Wie er aan tafel zit en wie eruit is. Geen mailadressen, geen inzet, geen
-- rebuys per persoon — dat laatste is geldregister en dus clubkant.
create or replace function public.club_public_seats(p_tournament_id uuid)
returns table (
  player_name     text,
  status          text,
  finish_position int,
  chip_count      int
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    public.public_name(p.display_name, p.username, p.id,
                       p.public_listing, p.public_profile, c.public_names),
    tp.status::text,
    tp.finish_position,
    tp.chip_count
  from tournament_players tp
  join tournaments t on t.id = tp.tournament_id
  join clubs c       on c.id = t.club_id
  join players p     on p.id = tp.player_id
  where tp.tournament_id = p_tournament_id
    and public.is_public_tournament(tp.tournament_id)
  order by
    case when tp.status in ('active', 'registered') then 0 else 1 end,
    tp.finish_position nulls first,
    coalesce(tp.chip_count, 0) desc,
    p.display_name;
$$;

-- ---------------------------------------------------------------------------
-- 3. De uitslag van een gespeelde avond
-- ---------------------------------------------------------------------------
-- Plaatsen en punten, geen bedragen. Wie wat won is een afspraak tussen de
-- club en die speler; het klassement is wat de zaal aangaat.

create or replace function public.club_public_result(p_tournament_id uuid)
returns table (
  place        int,
  player_name  text,
  points       numeric,
  knockouts    int
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    r.position,
    public.public_name(p.display_name, p.username, p.id,
                       p.public_listing, p.public_profile, c.public_names),
    r.points,
    r.knockouts
  from tournament_results r
  join tournaments t on t.id = r.tournament_id
  join clubs c       on c.id = t.club_id
  join players p     on p.id = r.player_id
  where r.tournament_id = p_tournament_id
    and public.is_public_tournament(r.tournament_id)
  order by r.position;
$$;

-- ---------------------------------------------------------------------------
-- 4. Het klassement
-- ---------------------------------------------------------------------------
-- Dezelfde telling als aan de clubkant, maar zonder het prijzengeld en met de
-- naamregel erop. Alleen afgesloten publieke tornooien tellen mee, zodat de
-- publieke stand niet kan afwijken van wat er publiek te zien was.

create or replace function public.club_public_standings(
  p_club_slug text,
  p_from      date default null,
  p_to        date default null
)
returns table (
  player_name   text,
  tournaments   int,
  points        numeric,
  best_position int,
  cashes        int,
  knockouts     int
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    public.public_name(p.display_name, p.username, p.id,
                       p.public_listing, p.public_profile, c.public_names) as player_name,
    count(*)::int,
    sum(r.points),
    min(r.position)::int,
    count(*) filter (where r.prize_cents > 0)::int,
    sum(r.knockouts)::int
  from tournament_results r
  join tournaments t on t.id = r.tournament_id
  join clubs c       on c.id = t.club_id
  join players p     on p.id = r.player_id
  where c.slug = p_club_slug
    and c.is_active
    and t.player_visibility = 'public'
    and t.status = 'finished'
    and (p_from is null or (r.finished_at at time zone c.timezone)::date >= p_from)
    and (p_to   is null or (r.finished_at at time zone c.timezone)::date <= p_to)
  group by p.id, p.display_name, p.username, p.public_listing, p.public_profile, c.public_names
  order by sum(r.points) desc, min(r.position);
$$;

-- ---------------------------------------------------------------------------
-- 5. Rechten
-- ---------------------------------------------------------------------------
-- Alles hierboven is security definer en filtert zelf op "publiek tornooi van
-- een actieve club". De onderliggende tabellen blijven dicht.

do $$
declare
  r text;
begin
  foreach r in array array['anon', 'authenticated'] loop
    if exists (select 1 from pg_roles where rolname = r) then
      execute format('grant execute on function public.public_name(text,text,uuid,boolean,boolean,boolean) to %I', r);
      execute format('grant execute on function public.is_public_tournament(uuid)   to %I', r);
      execute format('grant execute on function public.club_public_clock(uuid)      to %I', r);
      execute format('grant execute on function public.club_public_levels(uuid)     to %I', r);
      execute format('grant execute on function public.club_public_seats(uuid)      to %I', r);
      execute format('grant execute on function public.club_public_result(uuid)     to %I', r);
      execute format('grant execute on function public.club_public_standings(text,date,date) to %I', r);
    end if;
  end loop;
end $$;
