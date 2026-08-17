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
