-- Pokerleague — het platform door de ogen van wie het bezit
--
-- Tot nu kon iedereen alles zien behalve degene die het bouwt. Een club ziet
-- haar eigen cijfers, een speler ziet zijn eigen avonden, en wie wil weten
-- hoeveel clubs er zijn, hoeveel mensen erin zitten en hoeveel geld er over de
-- tafels gaat, moet het in de SQL-editor bij elkaar tikken. Dat is precies de
-- vraag die je 's avonds stelt en waar je dan geen zin meer in hebt.
--
-- Deze migratie zet daar drie dingen voor neer.
--
--   1. **Wie mag het zien.** Een tabelletje met e-mailadressen in plaats van
--      een adres in de code: iemand toevoegen is dan één regel SQL en geen
--      nieuwe deploy. En het staat in de database, waar de controle ook
--      gebeurt — een controle in de frontend is een gordijn, geen slot.
--
--   2. **Wat het kost en opbrengt.** `club_billing` houdt per club bij wat er
--      afgesproken is: opstartkost, maandbedrag, vanaf wanneer. Zonder die
--      tabel is "hoeveel verdien ik" een vraag die de database niet kán
--      beantwoorden, hoeveel tornooien er ook in staan.
--
--   3. **De cijfers zelf.** Zes functies die elk één vraag beantwoorden, zodat
--      de pagina zes keer iets ophaalt in plaats van dertig keer. Allemaal
--      `security definer` met de rechtencontrole er hard in: de functie is de
--      grens, niet de pagina die haar aanroept.
--
-- Bewust géén view op alles. Een view zou de RLS van de onderliggende tabellen
-- meeslepen en dan zie je als beheerder precies niets, want je bent bij geen
-- enkele club lid.

-- ---------------------------------------------------------------------------
-- 1. Wie is er beheerder van het platform
-- ---------------------------------------------------------------------------

create table if not exists platform_admins (
  email      text primary key,
  note       text,
  created_at timestamptz not null default now()
);

comment on table platform_admins is
  'E-mailadressen die het platformdashboard mogen zien. Los van club_members: dit gaat over PokerLeague zelf, niet over een club.';

alter table platform_admins enable row level security;

-- Geen enkele policy, met opzet. Alleen `service_role` en de functies
-- hieronder (security definer) komen erbij. Wie beheerder is, is niets voor
-- een clubbestuur om te kunnen uitlezen.
--
-- En de rechten er bovenop ingetrokken. Supabase geeft nieuwe tabellen in
-- `public` standaard aan `anon` en `authenticated`; RLS zonder policy houdt
-- ze dan wel tegen, maar dan hangt de afscherming aan één schakel. Twee
-- sloten op een tabel die niemand nodig heeft is geen overdaad.
revoke all on table platform_admins from anon, authenticated;

insert into platform_admins (email, note)
values ('arne@halcoservices.be', 'Halco Services — eigenaar')
on conflict (email) do nothing;

/**
 * Is de aangemelde gebruiker beheerder van het platform?
 *
 * Op e-mailadres en niet op user-id, zodat je iemand kan toevoegen vóór hij
 * een account heeft. Hoofdletterongevoelig, want niemand tikt zijn adres
 * twee keer hetzelfde.
 *
 * In servicecontext (de SQL-editor van Supabase) is het antwoord ja. Dat is
 * dezelfde afspraak als bij `club_stats` en het scheelt dat je je eigen
 * cijfers niet kan bekijken op de plek waar je ze zelf hebt ingevoerd.
 */
create or replace function public.is_platform_admin()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.is_service_context() or exists (
    select 1
    from platform_admins pa
    join auth.users u on lower(u.email) = lower(pa.email)
    where u.id = auth.uid()
  );
$$;

comment on function public.is_platform_admin() is
  'True als de aangemelde gebruiker in platform_admins staat. De grens voor alles wat platformbreed is.';

grant execute on function public.is_platform_admin() to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Wat er per club is afgesproken
-- ---------------------------------------------------------------------------
-- Bedragen in cent, zoals overal. Standaard staat het tarief dat vandaag in de
-- brochure staat: 500 euro opstart en 39 euro per maand. Een club met een
-- andere afspraak — een proefperiode, een korting het eerste jaar — pas je aan
-- op haar eigen regel; de cijfers volgen vanzelf.

create table if not exists club_billing (
  club_id       uuid primary key references clubs(id) on delete cascade,
  plan          text    not null default 'standaard',
  setup_cents   int     not null default 50000,
  monthly_cents int     not null default 3900,
  started_on    date    not null default current_date,
  ended_on      date,             -- null = loopt nog
  notes         text,
  created_at    timestamptz not null default now()
);

comment on table club_billing is
  'De afspraak per club: opstartkost, maandbedrag en vanaf wanneer. Voedt de omzetcijfers op het platformdashboard.';

alter table club_billing enable row level security;

-- Ook hier geen policy en dezelfde intrekking. Wat een andere club betaalt,
-- is niets voor een clubbestuur — en voor het bestuur van de eigen club staat
-- het niet in de weg, want die vraag komt in het product nergens voor.
revoke all on table club_billing from anon, authenticated;

-- Elke club die er al is, krijgt een regel op de standaardvoorwaarden, met de
-- aanmaakdatum van de club als startdatum. Klopt er iets niet, dan is dat één
-- update — dat is beter dan een lege tabel waarin je alles zelf moet invoeren.
insert into club_billing (club_id, started_on)
select c.id, c.created_at::date from clubs c
on conflict (club_id) do nothing;

/**
 * Een nieuwe club krijgt meteen een facturatieregel.
 *
 * Anders staat een club die je vandaag aanmaakt morgen niet in de omzet, en
 * ontdek je dat pas als het bedrag niet klopt.
 */
create or replace function public.club_billing_default()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into club_billing (club_id, started_on)
  values (new.id, new.created_at::date)
  on conflict (club_id) do nothing;
  return new;
end;
$$;

drop trigger if exists clubs_billing_default on clubs;
create trigger clubs_billing_default
  after insert on clubs
  for each row execute function public.club_billing_default();

/**
 * Hoeveel maanden er tot vandaag gefactureerd zijn voor één regel.
 *
 * De maand van instap telt mee — een club die op 20 januari begint, betaalt
 * januari. Dat is de afspraak zoals ze gemaakt is; als dat ooit pro rata
 * wordt, staat het hier op één plek.
 */
create or replace function public.billing_months(p_start date, p_end date)
returns int
language sql
immutable
as $$
  select greatest(
    0,
    (date_part('year',  age(date_trunc('month', coalesce(p_end, current_date))::date,
                            date_trunc('month', p_start)::date)) * 12
   + date_part('month', age(date_trunc('month', coalesce(p_end, current_date))::date,
                            date_trunc('month', p_start)::date)))::int + 1
  );
$$;

-- ---------------------------------------------------------------------------
-- 3. De cijfers
-- ---------------------------------------------------------------------------
-- Alle bedragen komen uit twee plaatsen en die betekenen niet hetzelfde:
--
--   * `buyins` is wat er binnenkomt aan de deur. `amount_cents` gaat naar de
--     prijzenpot, `fee_cents` is wat de club overhoudt, `bounty_cents` zit in
--     de koppen. Samen is dat "wat er rondgaat".
--   * `tournament_results.prize_cents` is wat er weer uitgaat.
--
-- Alleen niet-getekende boekingen (`is_void = false`) tellen mee, en alleen
-- afgesloten tornooien — een lopende avond heeft nog geen uitslag en zou de
-- gemiddeldes vervuilen.

/**
 * Eén rij met alles wat je in één oogopslag wil zien.
 */
drop function if exists public.platform_overview();
create or replace function public.platform_overview()
returns table (
  clubs             int,
  clubs_active      int,
  staff             int,
  players           int,
  players_claimed   int,
  players_shadow    int,
  memberships       int,
  multi_club        int,
  tournaments       int,
  upcoming          int,
  entries           int,
  entries_30d       int,
  avg_field         numeric,
  pot_cents         bigint,
  fee_cents         bigint,
  bounty_cents      bigint,
  prize_cents       bigint,
  active_30d        int,
  active_90d        int,
  new_players_30d   int,
  mrr_cents         bigint,
  arr_cents         bigint,
  setup_cents       bigint,
  revenue_cents     bigint,
  first_night       date,
  last_night        date
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_platform_admin() then
    raise exception 'Geen rechten op de platformcijfers'
      using errcode = 'insufficient_privilege';
  end if;

  return query
  with tours as (
    select t.id, t.club_id, t.ended_at, t.scheduled_at
    from tournaments t
    where t.status = 'finished' and t.ended_at is not null
  ),
  res as (
    select r.player_id as r_player, r.prize_cents as r_prize, x.ended_at as r_end
    from tournament_results r
    join tours x on x.id = r.tournament_id
  ),
  geld as (
    select b.amount_cents as g_pot, b.fee_cents as g_fee, b.bounty_cents as g_bounty
    from buyins b
    join tours x on x.id = b.tournament_id
    where not b.is_void
  ),
  velden as (
    select r.tournament_id, count(*) as n
    from tournament_results r
    join tours x on x.id = r.tournament_id
    group by r.tournament_id
  ),
  fact as (
    select b.setup_cents as f_setup, b.monthly_cents as f_month,
           b.started_on as f_start, b.ended_on as f_end
    from club_billing b
    join clubs c on c.id = b.club_id
    where c.is_active
  )
  select
    (select count(*) from clubs)::int,
    (select count(*) from clubs where is_active)::int,
    (select count(distinct user_id) from club_members)::int,
    (select count(*) from players where merged_into_id is null)::int,
    (select count(*) from players where merged_into_id is null and link_state = 'claimed')::int,
    (select count(*) from players where merged_into_id is null and link_state <> 'claimed')::int,
    (select count(*) from club_players)::int,
    (select count(*) from (
       select player_id from club_players group by player_id having count(distinct club_id) > 1
     ) q)::int,
    (select count(*) from tours)::int,
    (select count(*) from tournaments where status in ('scheduled','running','paused'))::int,
    (select count(*) from res)::int,
    (select count(*) from res where r_end >= now() - interval '30 days')::int,
    (select coalesce(round(avg(n), 1), 0) from velden),
    (select coalesce(sum(g_pot), 0) from geld)::bigint,
    (select coalesce(sum(g_fee), 0) from geld)::bigint,
    (select coalesce(sum(g_bounty), 0) from geld)::bigint,
    (select coalesce(sum(r_prize), 0) from res)::bigint,
    (select count(distinct r_player) from res where r_end >= now() - interval '30 days')::int,
    (select count(distinct r_player) from res where r_end >= now() - interval '90 days')::int,
    (select count(*) from players
      where merged_into_id is null and created_at >= now() - interval '30 days')::int,
    (select coalesce(sum(f_month), 0) from fact where f_end is null)::bigint,
    (select coalesce(sum(f_month), 0) * 12 from fact where f_end is null)::bigint,
    (select coalesce(sum(f_setup), 0) from fact)::bigint,
    (select coalesce(sum(f_setup + f_month
                         * public.billing_months(f_start, f_end)), 0) from fact)::bigint,
    -- De speeldatum en niet het moment van afsluiten. Een donderdagavond die
    -- om kwart voor één eindigt is een avond van donderdag; wie hier `ended_at`
    -- neemt ziet vrijdag staan en gaat zich afvragen wie er op vrijdag speelde.
    (select min((x.scheduled_at at time zone 'Europe/Brussels')::date) from tours x),
    (select max((x.scheduled_at at time zone 'Europe/Brussels')::date) from tours x);
end;
$$;

comment on function public.platform_overview() is
  'De kerncijfers van het hele platform in één rij: clubs, mensen, avonden, geld en omzet.';

/**
 * Eén regel per club, zodat je ze naast elkaar kan leggen.
 */
drop function if exists public.platform_clubs();
create or replace function public.platform_clubs()
returns table (
  slug          text,
  name          text,
  city          text,
  primary_color text,
  is_active     boolean,
  since         date,
  members       int,
  claimed       int,
  staff         int,
  tournaments   int,
  entries       int,
  avg_field     numeric,
  pot_cents     bigint,
  fee_cents     bigint,
  active_30d    int,
  last_night    date,
  monthly_cents int,
  revenue_cents bigint
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_platform_admin() then
    raise exception 'Geen rechten op de platformcijfers'
      using errcode = 'insufficient_privilege';
  end if;

  return query
  with tours as (
    select t.id, t.club_id, t.ended_at, t.scheduled_at
    from tournaments t
    where t.status = 'finished' and t.ended_at is not null
  ),
  res as (
    select r.club_id, r.tournament_id, r.player_id, x.ended_at
    from tournament_results r
    join tours x on x.id = r.tournament_id
  )
  select
    c.slug,
    c.name,
    c.city,
    c.primary_color,
    c.is_active,
    c.created_at::date,
    (select count(*) from club_players cp where cp.club_id = c.id)::int,
    (select count(*) from club_players cp
      join players p on p.id = cp.player_id
      where cp.club_id = c.id and p.link_state = 'claimed')::int,
    (select count(*) from club_members m where m.club_id = c.id)::int,
    (select count(*) from tours x where x.club_id = c.id)::int,
    (select count(*) from res r where r.club_id = c.id)::int,
    coalesce((select round(avg(n), 1) from (
       select count(*) as n from res r where r.club_id = c.id group by r.tournament_id
     ) q), 0),
    coalesce((select sum(b.amount_cents) from buyins b
      join tours x on x.id = b.tournament_id
      where b.club_id = c.id and not b.is_void), 0)::bigint,
    coalesce((select sum(b.fee_cents) from buyins b
      join tours x on x.id = b.tournament_id
      where b.club_id = c.id and not b.is_void), 0)::bigint,
    (select count(distinct r.player_id) from res r
      where r.club_id = c.id and r.ended_at >= now() - interval '30 days')::int,
    (select max((x.scheduled_at at time zone 'Europe/Brussels')::date)
     from tours x where x.club_id = c.id),
    coalesce(bi.monthly_cents, 0),
    coalesce(bi.setup_cents + bi.monthly_cents
             * public.billing_months(bi.started_on, bi.ended_on), 0)::bigint
  from clubs c
  left join club_billing bi on bi.club_id = c.id
  order by c.name;
end;
$$;

comment on function public.platform_clubs() is
  'Per club: leden, staf, avonden, deelnames, geld en wat ze opbrengt.';

/**
 * Het verloop per maand — de grafiek waar je het eerst naar kijkt.
 *
 * De maanden komen uit een reeks en niet uit de gegevens, zodat een maand
 * zonder avond als een gat in de lijn te zien is en niet stilletjes wegvalt.
 * Tijdzone Brussel: de avond van 31 januari om 23u is een avond van januari.
 */
drop function if exists public.platform_month_series(int);
create or replace function public.platform_month_series(p_months int default 12)
returns table (
  month           date,
  tournaments     int,
  entries         int,
  pot_cents       bigint,
  fee_cents       bigint,
  prize_cents     bigint,
  new_players     int,
  active_players  int,
  revenue_cents   bigint
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_tz text := 'Europe/Brussels';
begin
  if not public.is_platform_admin() then
    raise exception 'Geen rechten op de platformcijfers'
      using errcode = 'insufficient_privilege';
  end if;

  return query
  with maanden as (
    select generate_series(
      date_trunc('month', (now() at time zone v_tz))::date - ((greatest(p_months, 1) - 1) || ' months')::interval,
      date_trunc('month', (now() at time zone v_tz))::date,
      '1 month'::interval
    )::date as m
  ),
  tours as (
    select t.id, date_trunc('month', (t.ended_at at time zone v_tz))::date as m
    from tournaments t
    where t.status = 'finished' and t.ended_at is not null
  ),
  res as (
    select r.player_id, r.prize_cents, x.m
    from tournament_results r
    join tours x on x.id = r.tournament_id
  ),
  geld as (
    select b.amount_cents, b.fee_cents, x.m
    from buyins b
    join tours x on x.id = b.tournament_id
    where not b.is_void
  ),
  -- Eerste avond ooit van een speler: dat is wat "nieuw" betekent.
  eerste as (
    select r.player_id, min(x.m) as m
    from tournament_results r
    join tours x on x.id = r.tournament_id
    group by r.player_id
  )
  select
    d.m,
    (select count(*) from tours x where x.m = d.m)::int,
    (select count(*) from res r where r.m = d.m)::int,
    (select coalesce(sum(g.amount_cents), 0) from geld g where g.m = d.m)::bigint,
    (select coalesce(sum(g.fee_cents), 0) from geld g where g.m = d.m)::bigint,
    (select coalesce(sum(r.prize_cents), 0) from res r where r.m = d.m)::bigint,
    (select count(*) from eerste e where e.m = d.m)::int,
    (select count(distinct r.player_id) from res r where r.m = d.m)::int,
    -- Wat er die maand aan abonnement liep, plus de opstart in de maand van
    -- instap. Zo zie je de sprong die een nieuwe club maakt.
    (select coalesce(sum(
       b.monthly_cents
       + case when date_trunc('month', b.started_on)::date = d.m then b.setup_cents else 0 end
     ), 0)
     from club_billing b
     where date_trunc('month', b.started_on)::date <= d.m
       and (b.ended_on is null or date_trunc('month', b.ended_on)::date >= d.m))::bigint
  from maanden d
  order by d.m;
end;
$$;

comment on function public.platform_month_series(int) is
  'Per maand: avonden, deelnames, geld over de tafels en de omzet van het platform.';

/**
 * Deelnames per club per maand — voor een gestapelde grafiek.
 *
 * Apart van de vorige functie omdat het een andere vorm heeft: daar één rij
 * per maand, hier één rij per maand per club. Ze in elkaar schuiven levert
 * een tabel op waar de helft van de kolommen leeg staat.
 */
drop function if exists public.platform_club_month_series(int);
create or replace function public.platform_club_month_series(p_months int default 12)
returns table (
  month         date,
  slug          text,
  name          text,
  primary_color text,
  tournaments   int,
  entries       int
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_tz text := 'Europe/Brussels';
begin
  if not public.is_platform_admin() then
    raise exception 'Geen rechten op de platformcijfers'
      using errcode = 'insufficient_privilege';
  end if;

  return query
  with maanden as (
    select generate_series(
      date_trunc('month', (now() at time zone v_tz))::date - ((greatest(p_months, 1) - 1) || ' months')::interval,
      date_trunc('month', (now() at time zone v_tz))::date,
      '1 month'::interval
    )::date as m
  ),
  tours as (
    select t.id, t.club_id, date_trunc('month', (t.ended_at at time zone v_tz))::date as m
    from tournaments t
    where t.status = 'finished' and t.ended_at is not null
  )
  select
    d.m,
    c.slug,
    c.name,
    c.primary_color,
    (select count(*) from tours x where x.club_id = c.id and x.m = d.m)::int,
    (select count(*) from tournament_results r
      join tours x on x.id = r.tournament_id
      where x.club_id = c.id and x.m = d.m)::int
  from maanden d
  cross join clubs c
  order by d.m, c.name;
end;
$$;

comment on function public.platform_club_month_series(int) is
  'Deelnames en avonden per club per maand, voor een gestapelde grafiek.';

/**
 * Wie er het meest speelt, over alle clubs heen.
 *
 * Dit is het cijfer dat een clubdashboard nooit kan geven: iemand die bij twee
 * clubs speelt, staat bij allebei half in beeld en hier volledig.
 */
drop function if exists public.platform_top_players(int);
create or replace function public.platform_top_players(p_limit int default 10)
returns table (
  display_name   text,
  clubs          int,
  entries        int,
  wins           int,
  cashes         int,
  invested_cents bigint,
  won_cents      bigint,
  net_cents      bigint,
  last_played    date
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_platform_admin() then
    raise exception 'Geen rechten op de platformcijfers'
      using errcode = 'insufficient_privilege';
  end if;

  return query
  with tours as (
    select t.id, t.ended_at
    from tournaments t
    where t.status = 'finished' and t.ended_at is not null
  ),
  res as (
    select r.*, x.ended_at
    from tournament_results r
    join tours x on x.id = r.tournament_id
  )
  select
    p.display_name,
    (select count(distinct cp.club_id) from club_players cp where cp.player_id = p.id)::int,
    count(*)::int,
    count(*) filter (where r.position = 1)::int,
    count(*) filter (where r.prize_cents > 0)::int,
    coalesce(sum(r.invested_cents), 0)::bigint,
    coalesce(sum(r.prize_cents + r.bounty_cents), 0)::bigint,
    coalesce(sum(r.prize_cents + r.bounty_cents - r.invested_cents), 0)::bigint,
    max(r.ended_at)::date
  from res r
  join players p on p.id = r.player_id
  where p.merged_into_id is null
  group by p.id, p.display_name
  order by count(*) desc, sum(r.prize_cents) desc nulls last
  limit greatest(p_limit, 1);
end;
$$;

comment on function public.platform_top_players(int) is
  'De spelers met de meeste deelnames over alle clubs heen, met hun saldo.';

/**
 * De laatste avonden van het hele platform, door elkaar.
 *
 * Dit is het scherm waar je op kijkt om te zien of er nog leven in zit —
 * één blik en je weet welke club wanneer voor het laatst gespeeld heeft.
 */
drop function if exists public.platform_recent(int);
create or replace function public.platform_recent(p_limit int default 8)
returns table (
  slug          text,
  club          text,
  primary_color text,
  name          text,
  played_on     date,
  ended_at      timestamptz,
  entries       int,
  pot_cents     bigint,
  winner        text
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_platform_admin() then
    raise exception 'Geen rechten op de platformcijfers'
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select
    c.slug,
    c.name,
    c.primary_color,
    t.name,
    (t.scheduled_at at time zone 'Europe/Brussels')::date,
    t.ended_at,
    (select count(*) from tournament_results r where r.tournament_id = t.id)::int,
    coalesce((select sum(b.amount_cents) from buyins b
      where b.tournament_id = t.id and not b.is_void), 0)::bigint,
    (select p.display_name from tournament_results r
      join players p on p.id = r.player_id
      where r.tournament_id = t.id and r.position = 1 limit 1)
  from tournaments t
  join clubs c on c.id = t.club_id
  where t.status = 'finished' and t.ended_at is not null
  -- Twee avonden die binnen dezelfde seconde afgesloten worden — bij het
  -- inlezen van een oud seizoen gebeurt dat — vallen anders in willekeurige
  -- volgorde. De speeldatum breekt de gelijkstand.
  order by t.ended_at desc, t.scheduled_at desc
  limit greatest(p_limit, 1);
end;
$$;

comment on function public.platform_recent(int) is
  'De laatst afgesloten avonden van alle clubs door elkaar.';

-- ---------------------------------------------------------------------------
-- 4. Rechten
-- ---------------------------------------------------------------------------
-- `security definer` draait als de eigenaar en zet de RLS dus opzij. De enige
-- grens is de controle bovenaan elke functie — daarom staat die er in alle
-- zes, en niet één keer in een wrapper waar je later langs kan lopen.

do $$
declare fn text;
begin
  foreach fn in array array[
    'public.platform_overview()',
    'public.platform_clubs()',
    'public.platform_month_series(int)',
    'public.platform_club_month_series(int)',
    'public.platform_top_players(int)',
    'public.platform_recent(int)'
  ] loop
    execute format('revoke all on function %s from public', fn);
    execute format('grant execute on function %s to authenticated, service_role', fn);
  end loop;
end $$;
