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
