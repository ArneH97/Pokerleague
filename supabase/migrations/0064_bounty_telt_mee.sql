-- Pokerleague — de bounties die je wint, tellen mee in wat je won
--
-- **Het probleem.** Op je eigen pagina staat per avond een netto: wat de
-- avond opbracht min wat ze kostte. De kostenkant klopte volledig — inkoop,
-- rebuys, add-ons, fee én het bountydeel van elke inkoop, want dat betaal je
-- ook. De opbrengstkant telde alleen het prijzengeld uit de prijzenladder.
--
-- De bounties die je die avond ophaalde stonden er niet bij.
--
-- Dat is geen afrondingsverschil. Je betaalt de bounty bij het inkopen en je
-- krijgt hem terug door mensen uit te schakelen; alleen de ene helft tellen
-- maakt van elke bountyavond een slechtere avond dan ze was, en het meest bij
-- de speler die het best speelde. Wie vier koppen pakte op een avond met
-- twintig euro bounty, miste tachtig euro in zijn eigen overzicht.
--
-- **Waar het misging, en waar niet.** Het platformoverzicht in het beheer
-- rekende al met prijzengeld plus bounty, en `season_standings` ook. Drie
-- andere plekken niet:
--
--   my_results            je eigen pagina — het netto per avond
--   club_member_overview  het ledenbestand — het saldo per speler
--   club_standings_period je jaar- en maandklassement — de kolom prijzengeld
--   my_club_stats         je cijfers per club
--
-- Dat de ene functie het wel deed en de andere niet, is precies hoe zoiets
-- ontstaat: elke functie telde zijn eigen som op. Hierna betekent "gewonnen"
-- overal hetzelfde — prijzengeld plus bounties — en staat het in de
-- commentaar van elke functie zodat de volgende die erbij komt het ook doet.
--
-- `cashes` blijft wél op het prijzengeld alleen staan. In de prijzen eindigen
-- is iets anders dan een kop pakken, en een speler die drie bounties won maar
-- als twaalfde eindigde, is niet "in the money" geweest.

-- ---------------------------------------------------------------------------
-- 1. Je eigen pagina
-- ---------------------------------------------------------------------------

drop function if exists public.my_results();

create or replace function public.my_results()
returns table (
  tournament_id uuid,
  tournament    text,
  club_name     text,
  club_slug     text,
  played_on     timestamptz,
  place         int,
  entries       int,
  prize_cents   int,
  /** De bounties die hij die avond ophaalde. Hoort bij wat de avond opbracht. */
  bounty_cents  int,
  spent_cents   int,
  points        numeric,
  knockouts     int
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    r.tournament_id, t.name, c.name, c.slug,
    r.finished_at, r.position, r.entries_total,
    r.prize_cents,
    coalesce(r.bounty_cents, 0),
    coalesce((
      select sum(b.amount_cents + b.fee_cents + coalesce(b.bounty_cents, 0))::int
      from buyins b
      where b.tournament_id = r.tournament_id and b.player_id = r.player_id
        and not b.is_void
    ), 0),
    r.points, r.knockouts
  from tournament_results r
  join players p     on p.id = r.player_id
  join tournaments t on t.id = r.tournament_id
  join clubs c       on c.id = t.club_id
  where p.auth_user_id = auth.uid()
  order by r.finished_at desc;
$$;

comment on function public.my_results() is
  'Alle afgesloten sessies van de aangemelde speler. Opbrengst = prize_cents + bounty_cents; kost = de volledige som uit buyins, inkoop, rebuys, add-ons, fee en bounty. Niet-getelde inkopen (is_void) blijven erbuiten.';

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function public.my_results() to authenticated;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 2. Je cijfers per club
-- ---------------------------------------------------------------------------

create or replace function public.my_club_stats(p_club_slug text default null)
returns table (
  club_slug     text,
  club_name     text,
  club_city     text,
  logo_url      text,
  tournaments   int,
  points        numeric,
  best_position int,
  cashes        int,
  knockouts     int,
  prize_cents   bigint,
  rank          int,
  of_players    int,
  last_played   date
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
    select distinct t.club_id
    from tournament_results r
    join tournaments t on t.id = r.tournament_id
    where r.player_id = (select id from me)
  ),
  agg as (
    select
      t.club_id,
      r.player_id,
      count(*)::int                                       as tournaments,
      sum(r.points)                                       as points,
      min(r.position)::int                                as best_position,
      count(*) filter (where r.prize_cents > 0)::int      as cashes,
      sum(r.knockouts)::int                               as knockouts,
      -- Prijzengeld én bounties: zie de kop van deze migratie.
      sum(r.prize_cents + coalesce(r.bounty_cents, 0))::bigint as prize_cents,
      max((r.finished_at at time zone c.timezone)::date)  as last_played
    from tournament_results r
    join tournaments t on t.id = r.tournament_id
    join clubs c       on c.id = t.club_id
    where t.club_id in (select club_id from mijn_clubs)
      and c.is_active
      and t.player_visibility = 'public'
      and t.status = 'finished'
    group by t.club_id, r.player_id
  ),
  ranked as (
    select
      agg.*,
      rank() over (partition by club_id order by points desc, best_position) as rnk,
      count(*) over (partition by club_id)                                   as total
    from agg
  )
  select
    c.slug, c.name, c.city, c.logo_url,
    a.tournaments, a.points, a.best_position, a.cashes, a.knockouts,
    a.prize_cents, a.rnk::int, a.total::int, a.last_played
  from ranked a
  join clubs c on c.id = a.club_id
  where a.player_id = (select id from me)
    and (p_club_slug is null or c.slug = p_club_slug)
  order by a.last_played desc nulls last
$$;

comment on function public.my_club_stats(text) is
  'Per club waar de aangemelde speler resultaten heeft: zijn eigen cijfers en zijn plaats in dat klassement. prize_cents is prijzengeld plus bounties. Zonder slug alle clubs, met slug alleen die ene.';

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function public.my_club_stats(text) to authenticated;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 3. Het ledenbestand
-- ---------------------------------------------------------------------------
-- Alleen de ene som verandert. De rest van de functie blijft letterlijk wat
-- ze was; ze staat hier in haar geheel omdat create or replace niet anders
-- kan, niet omdat er meer aan veranderd is.

create or replace function public.club_member_overview(p_club_id uuid)
returns table (
  player_id      uuid,
  display_name   text,
  username       text,
  email          text,
  no_email_reason text,
  link_state     player_link_state,
  joined_on      date,
  entries        int,
  last_played    timestamptz,
  best_position  int,
  cashes         int,
  total_prize    int,
  total_spent    int,
  knockouts      int
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
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
      -- Prijzengeld én bounties, zodat het saldo hiernaast klopt: de
      -- bounty staat aan de kostenkant immers ook in de inleg.
      sum(r.prize_cents + coalesce(r.bounty_cents, 0)) as total_prize,
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
  'Het ledenbestand van één club met de cijfers per speler. total_prize is prijzengeld plus bounties, zodat het naast de inleg een echt saldo is. Alleen voor staf: er staan mailadressen in.';

-- ---------------------------------------------------------------------------
-- 4. Het jaar- en maandklassement
-- ---------------------------------------------------------------------------
-- `season_standings` telde de bounties al mee. Dat de jaarstand ernaast dat
-- niet deed, betekende dat dezelfde speler over dezelfde avonden twee
-- verschillende bedragen kon hebben, afhankelijk van welk tabblad je aanklikt.

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
    coalesce(sum(r.prize_cents + coalesce(r.bounty_cents, 0)), 0)::int as total_prize,
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
  'Klassement over een vrije periode (maand, jaar, ...). Telt álle resultaten in die periode; total_prize is prijzengeld plus bounties, net als bij season_standings(). Voor het seizoensklassement met de beste-N-regel: season_standings().';

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function public.club_standings_period(uuid, date, date) to authenticated;
  end if;
end $$;
