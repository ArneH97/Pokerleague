-- Pokerleague — wat een sessie je kostte, niet alleen wat ze opbracht
--
-- `my_results` gaf prijzengeld terug en verder niets over geld. Dat is precies
-- de helft van het enige getal dat een pokerspeler echt bijhoudt: **netto**.
-- Veertig euro winnen op een avond die zestig kostte is geen goede avond, en
-- een profielpagina die alleen het prijzengeld optelt vertelt een verhaal dat
-- structureel te mooi is.
--
-- Wat er meekomt is alles wat hij die avond in de pot stak: inkoop, rebuys,
-- add-ons, fee en bounty. Dat staat allemaal in `buyins`, per speler per
-- tornooi — de floor boekt het daar bij elke handeling.
--
-- Bewust de volledige som en niet alleen de inkoop. Wie drie keer herkoopt
-- heeft drie keer betaald, en een netto dat die rebuys negeert is geen netto.

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
    coalesce((
      select sum(b.amount_cents + b.fee_cents + coalesce(b.bounty_cents, 0))::int
      from buyins b
      where b.tournament_id = r.tournament_id and b.player_id = r.player_id
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
  'Alle afgesloten sessies van de aangemelde speler, met wat ze opbrachten én wat ze kostten. De inleg is de volledige som uit buyins — inkoop, rebuys, add-ons, fee en bounty — want een netto dat rebuys negeert is geen netto.';

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function public.my_results() to authenticated;
  end if;
end $$;
