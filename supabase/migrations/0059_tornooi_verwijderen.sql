-- Pokerleague — het aantal inschrijvingen uit het zicht, en een avond kunnen wissen
--
-- Twee dingen die niets met elkaar te maken hebben behalve dat ze allebei over
-- vertrouwen gaan: wie mag wat zien, en wie mag wat weggooien.
--
-- ---------------------------------------------------------------------------
-- 1. Het aantal inschrijvingen is niet voor spelers
-- ---------------------------------------------------------------------------
-- Het stond op twee plaatsen: op de affichepagina ("12 ingeschreven") en in de
-- kalender van de speler ("12 komen"). Dat leest als sfeerbeeld maar werkt als
-- het tegenovergestelde: staat er drie, dan denkt de volgende bezoeker dat het
-- niet doorgaat en schrijft hij zich niet in. Een lage teller houdt zichzelf
-- laag. En het gaat de zaal ook niet aan hoe vol het is — dat is iets tussen de
-- floor en zijn tafels.
--
-- **Het weghalen uit het scherm volstaat niet.** Deze functies zijn RPC's die
-- iedereen mag aanroepen; wie het getal uit de tabel haalt, heeft het gewoon.
-- Dus gaat de kolom eruit, en dan bestaat het antwoord niet meer.
--
-- De floor houdt zijn lijst: `tournament_rsvp_list` is afgeschermd op rol en
-- blijft ongemoeid.
--
-- Wat blijft staan is `entries` — hoeveel mensen er werkelijk aan tafel zitten
-- op een avond die loopt. Dat is geen inschrijvingsteller maar de veldgrootte,
-- en die staat sowieso al op het live-bord.

-- `returns table` verandert van vorm, dus eerst weg. `create or replace` kan
-- het rijtype niet aanpassen en geeft anders een fout die niets uitlegt.
drop function if exists public.tournament_signup_card(text, uuid);

create or replace function public.tournament_signup_card(
  p_club_slug     text,
  p_tournament_id uuid default null
)
returns table (
  tournament_id  uuid,
  name           text,
  scheduled_at   timestamptz,
  status         text,
  buyin_cents    int,
  fee_cents      int,
  starting_stack int,
  bonus_stack    int,
  is_open        boolean,
  club_slug      text,
  club_name      text,
  city           text,
  address_line   text,
  maps_url       text,
  logo_url       text,
  primary_color  text,
  currency       char(3),
  timezone       text,
  locale         text
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with c as (
    select * from clubs where slug = p_club_slug and is_active
  ),
  t as (
    select t.*
    from tournaments t
    join c on c.id = t.club_id
    where (p_tournament_id is null or t.id = p_tournament_id)
      and t.status = 'scheduled'
      -- Zonder id: de eerstvolgende. Zo kan er één kort adres op de affiche
      -- staan dat volgende maand vanzelf naar de volgende avond wijst.
      and (p_tournament_id is not null or t.scheduled_at > now())
    order by t.scheduled_at
    limit 1
  )
  select
    t.id, t.name, t.scheduled_at, t.status::text,
    t.buyin_cents, t.fee_cents, t.starting_stack, t.prereg_bonus_stack,
    -- Open tot het tornooi begint. Daarna is inschrijven zinloos: dan sta je
    -- aan de deur en doet de floor het.
    (t.status = 'scheduled' and t.scheduled_at > now()),
    c.slug, c.name, c.city, c.address_line, c.maps_url, c.logo_url,
    c.primary_color, c.currency, c.timezone, c.locale
  from t cross join c;
$$;

comment on function public.tournament_signup_card(text, uuid) is
  'De gegevens voor de publieke inschrijfpagina van één avond. Bewust zonder het aantal inschrijvingen: dat gaat de bezoeker niet aan, en een lage teller houdt zichzelf laag.';

drop function if exists public.my_calendar(int);

create or replace function public.my_calendar(p_days int default 120)
returns table (
  tournament_id  uuid,
  name           text,
  scheduled_at   timestamptz,
  status         text,
  club_slug      text,
  club_name      text,
  logo_url       text,
  primary_color  text,
  currency       char(3),
  timezone       text,
  buyin_cents    int,
  fee_cents      int,
  bonus_stack    int,
  entries        int,
  i_play         boolean,
  i_rsvp         boolean,
  can_rsvp       boolean
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with me as (
    select id from players
    where auth_user_id = auth.uid() and merged_into_id is null
  ),
  mijn_clubs as (
    select cp.club_id from club_players cp where cp.player_id = (select id from me)
  )
  select
    t.id,
    t.name,
    t.scheduled_at,
    t.status::text,
    c.slug,
    c.name,
    c.logo_url,
    c.primary_color,
    c.currency,
    c.timezone,
    t.buyin_cents,
    t.fee_cents,
    t.prereg_bonus_stack,
    (select count(*)::int from tournament_players x where x.tournament_id = t.id),
    exists (
      select 1 from tournament_players x
      where x.tournament_id = t.id and x.player_id = (select id from me)
    ),
    -- Of híj ingeschreven staat, blijft hij wél zien. Dat is zijn eigen
    -- gegeven en het antwoord op de enige vraag die hij hier heeft.
    exists (
      select 1 from tournament_registrations r
      where r.tournament_id = t.id and r.player_id = (select id from me)
        and r.cancelled_at is null
    ),
    -- Inschrijven kan zolang de avond gepland is en nog moet beginnen. Zit je
    -- al aan tafel, dan is de vraag niet meer aan de orde.
    (t.status = 'scheduled' and t.scheduled_at > now()
     and not exists (select 1 from tournament_players x
                     where x.tournament_id = t.id and x.player_id = (select id from me)))
  from tournaments t
  join clubs c on c.id = t.club_id
  where t.club_id in (select club_id from mijn_clubs)
    and t.status in ('scheduled', 'running', 'paused')
    and (t.player_visibility = 'public'
         or (t.player_visibility = 'members' and public.is_club_player(t.club_id))
         or public.is_club_member(t.club_id))
    and t.scheduled_at >= now() - interval '12 hours'
    and t.scheduled_at <= now() + make_interval(days => greatest(1, p_days))
  order by t.scheduled_at;
$$;

comment on function public.my_calendar(int) is
  'De komende avonden bij de clubs van deze speler. Toont wel of hij zelf ingeschreven staat, niet hoeveel anderen.';

-- ---------------------------------------------------------------------------
-- 2. Een avond verwijderen
-- ---------------------------------------------------------------------------
-- Tot nu toe kon dat alleen met een script in de SQL-editor, en dat is een
-- omweg voor iets wat regelmatig nodig is: een testavond, een dubbel
-- aangemaakt tornooi, een zondag die niet doorgaat.
--
-- **Alles gaat mee.** Deelnames, inkopen, uitschakelingen, inschrijvingen,
-- tafels, uitslag. Dat volgt uit de cascade op de tabellen; er is hier niets
-- apart te wissen. Het klassement rekent uit `tournament_results`, dus dat
-- klopt meteen weer.
--
-- **Maar niet iedereen mag alles.** Een avond die nooit gespeeld is, is
-- rommel opruimen — dat mag een floor. Een avond mét uitslag weggooien
-- verandert het klassement van de club, en wie dat doet moet het ook mogen
-- beslissen: alleen owner en admin. Dat onderscheid staat hier en niet in het
-- scherm, want een knop die je verbergt is geen beveiliging.
--
-- **Afgelasten is iets anders dan wissen.** Een avond die niet doorgaat maar
-- wel bestond, zet je op `cancelled`; dan blijft hij in de geschiedenis staan.
-- Wissen is voor wat er nooit had mogen zijn.

create or replace function public.tournament_delete_info(p_tournament_id uuid)
returns table (
  name           text,
  status         text,
  scheduled_at   timestamptz,
  spelers        int,
  inschrijvingen int,
  inkopen        int,
  uitslagen      int,
  mag_ik         boolean
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  t tournaments%rowtype;
begin
  select * into t from tournaments where id = p_tournament_id;
  if not found then
    raise exception 'Tornooi bestaat niet';
  end if;

  if not public.is_service_context()
     and not public.has_club_role(t.club_id, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten' using errcode = 'insufficient_privilege';
  end if;

  return query
  select
    t.name,
    t.status::text,
    t.scheduled_at,
    (select count(*)::int from tournament_players x where x.tournament_id = t.id),
    (select count(*)::int from tournament_registrations x
      where x.tournament_id = t.id and x.cancelled_at is null),
    (select count(*)::int from buyins x where x.tournament_id = t.id),
    (select count(*)::int from tournament_results x where x.tournament_id = t.id),
    -- Mag de aanroeper hem ook werkelijk wissen, of ziet hij alleen de cijfers?
    (public.is_service_context()
     or public.has_club_role(t.club_id, array['owner','admin']::club_role[])
     or not exists (select 1 from tournament_results x where x.tournament_id = t.id)
        and not exists (select 1 from tournament_players x where x.tournament_id = t.id));
end;
$$;

comment on function public.tournament_delete_info(uuid) is
  'Wat er aan een avond hangt, zodat het scherm kan tonen wat er precies verdwijnt voor er iemand op verwijderen drukt.';

create or replace function public.floor_delete_tournament(p_tournament_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  t          tournaments%rowtype;
  v_spelers  int;
  v_uitslag  int;
  v_naam     text;
  v_str      uuid;
begin
  select * into t from tournaments where id = p_tournament_id;
  if not found then
    raise exception 'Tornooi bestaat niet';
  end if;

  if not public.is_service_context()
     and not public.has_club_role(t.club_id, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten' using errcode = 'insufficient_privilege';
  end if;

  select count(*) into v_spelers from tournament_players where tournament_id = t.id;
  select count(*) into v_uitslag from tournament_results where tournament_id = t.id;

  -- Er is gespeeld. Dan raakt wissen de geschiedenis van de club, en dat is
  -- geen beslissing voor tijdens een avond.
  if (v_spelers > 0 or v_uitslag > 0)
     and not public.is_service_context()
     and not public.has_club_role(t.club_id, array['owner','admin']::club_role[]) then
    raise exception 'Aan deze avond hangt al gespeeld werk (% deelnames, % uitslagregels). Alleen een beheerder kan die verwijderen.',
      v_spelers, v_uitslag
      using errcode = 'insufficient_privilege';
  end if;

  v_naam := t.name;
  v_str := t.structure_id;

  delete from tournaments where id = p_tournament_id;

  -- Had die avond een eigen kopie van de blindstructuur — die maakt het
  -- systeem aan zodra je tijdens het spelen aan de levels komt — dan hangt ze
  -- nu nergens meer aan. Clubsjablonen blijven, die hebben geen tornooi nodig.
  if v_str is not null then
    delete from blind_structures bs
    where bs.id = v_str
      and bs.club_id = t.club_id
      and bs.description like 'Eigen structuur van deze avond%'
      and not exists (select 1 from tournaments x where x.structure_id = bs.id);
  end if;

  return jsonb_build_object(
    'name', v_naam,
    'players', v_spelers,
    'results', v_uitslag);
end;
$$;

comment on function public.floor_delete_tournament(uuid) is
  'Verwijdert een avond met alles wat eraan hangt. Een avond waar al gespeeld is, kan alleen door owner of admin.';

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function public.tournament_signup_card(text, uuid)     to anon, authenticated;
    grant execute on function public.my_calendar(int)                       to authenticated;
    grant execute on function public.tournament_delete_info(uuid)           to authenticated;
    grant execute on function public.floor_delete_tournament(uuid)          to authenticated;
  end if;
end $$;
