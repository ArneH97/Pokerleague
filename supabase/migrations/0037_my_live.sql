-- Pokerleague — wat er nú aan tafel gebeurt, voor de speler zelf
--
-- Een speler die aan het spelen is, heeft een telefoon in zijn zak en één
-- vraag: hoe sta ik ervoor. Hoeveel zijn er nog, hoe groot is de pot, hoeveel
-- is een gemiddelde stapel — en klopt wat de floor van míjn stapel noteerde.
--
-- Dat laatste is het punt waarom dit meer is dan een leuk schermpje. De
-- chipcount die op het zaalscherm staat komt van iemand die twintig stapels na
-- elkaar intikt. Laat je de speler zijn eigen aantal ingeven, dan klopt het
-- vaker en heeft de floor er minder werk aan. De regels daarvoor staan sinds
-- 0005 in `guard_player_chip_update`: alleen je eigen rij, alleen het
-- chipaantal, en alleen zolang je nog actief bent.
--
-- Deze functie geeft dus geen nieuwe rechten. Ze verzamelt alleen wat er over
-- die avonden te zeggen valt op één plek, zodat de startpagina niet vijf
-- losse queries hoeft te doen.

create or replace function public.my_live_tournaments()
returns table (
  tournament_id        uuid,
  tournament_player_id uuid,
  name                 text,
  club_slug            text,
  club_name            text,
  logo_url             text,
  primary_color        text,
  currency             char(3),
  status               text,
  clock                text,
  level_idx            int,
  my_chips             int,
  my_chips_by          text,
  players_left         int,
  entries              int,
  avg_stack            int,
  prize_pool_cents     bigint
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
  mijn as (
    select tp.*
    from tournament_players tp
    join tournaments t on t.id = tp.tournament_id
    where tp.player_id = (select id from me)
      -- Lopend of gepauzeerd. Een afgesloten avond hoort bij je resultaten,
      -- niet bij "waar zit ik nu".
      and t.status in ('running', 'paused')
      and tp.status in ('active', 'registered')
  )
  select
    t.id,
    m.id,
    t.name,
    c.slug,
    c.name,
    c.logo_url,
    c.primary_color,
    c.currency,
    t.status::text,
    t.clock::text,
    t.level_idx,
    m.chip_count,
    m.chip_count_by,
    (select count(*)::int from tournament_players x
     where x.tournament_id = t.id and x.status in ('active', 'registered')),
    (select count(*)::int from tournament_players x where x.tournament_id = t.id),
    -- Gemiddelde stapel over wie er nog zit. Nul spelers kan hier niet, want
    -- hijzelf zit er nog — maar deling door nul is geen risico dat je op
    -- toeval laat berusten.
    (select case when count(*) filter (where x.status in ('active','registered')) = 0 then 0
                 else (sum(x.chip_count) filter (where x.status in ('active','registered'))
                       / count(*) filter (where x.status in ('active','registered')))::int end
     from tournament_players x where x.tournament_id = t.id),
    (select coalesce(sum(b.amount_cents), 0)::bigint
     from buyins b where b.tournament_id = t.id)
  from mijn m
  join tournaments t on t.id = m.tournament_id
  join clubs c       on c.id = t.club_id
  order by t.scheduled_at desc
$$;

comment on function public.my_live_tournaments() is
  'De tornooien waar de aangemelde speler op dit moment in zit, met de cijfers van die avond en zijn eigen stapel. Geeft geen nieuwe rechten: zijn chipaantal wijzigen loopt nog altijd via de gewone update op tournament_players, bewaakt door guard_player_chip_update.';

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function public.my_live_tournaments() to authenticated;
  end if;
end $$;
