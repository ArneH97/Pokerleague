-- Pokerleague — jouw cijfers bij één club
--
-- De klacht die dit oplost, in de woorden waarin ze binnenkwam: *"het is heel
-- verwarrend voor spelers en clubs wat dan juist waar staat en wat PokerLeague
-- is en wat Cutoff is."* Terecht, en het is geen tekstprobleem. De informatie
-- die het onderscheid zou uitleggen bestond gewoon nergens.
--
-- Want dit is wat er is: een speler ziet op de clubpagina het klassement van
-- iedereen, en op zijn eigen pagina de optelsom van alles. Nergens ziet hij
-- het ene ding waarmee het kwartje valt — *wat hij bij déze club heeft staan.*
-- Zonder dat blijft "PokerLeague" een tweede site waar toevallig ook iets van
-- hem staat, in plaats van de plek waar zijn clubs samenkomen.
--
-- Deze functie geeft precies dat: per club waar hij ooit speelde zijn eigen
-- regel, met zijn plaats in dat klassement erbij.
--
-- **Waarom dezelfde filters als het publieke klassement.** Er zou iets voor te
-- zeggen zijn om hier álles mee te tellen, ook besloten avonden — hij speelde
-- ze tenslotte. Toch niet gedaan. Als hier "12e van 47" staat en op de
-- klassementpagina van de club tellen ze hem als veertiende, dan is het cijfer
-- erger dan geen cijfer: dan klopt er iets niet en weet niemand wat. Een getal
-- dat hij kan narekenen op de pagina ernaast is meer waard dan een getal dat
-- vollediger is.

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
  -- Alleen de clubs waar hij effectief resultaten heeft. Het rekenwerk
  -- hieronder telt álle spelers van die clubs op om zijn plaats te bepalen,
  -- en dat wil je niet over het hele platform doen.
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
      sum(r.prize_cents)::bigint                          as prize_cents,
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
      -- rank() en niet row_number(): twee spelers met evenveel punten en
      -- dezelfde beste plaats staan echt gelijk, en dan is "jij bent zevende
      -- en hij achtste" verzonnen.
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
  'Per club waar de aangemelde speler resultaten heeft: zijn eigen cijfers en zijn plaats in dat klassement. Gebruikt dezelfde filters als club_public_standings, zodat zijn plaats overeenkomt met wat hij op de klassementpagina van de club ziet staan. Zonder slug alle clubs, met slug alleen die ene.';

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function public.my_club_stats(text) to authenticated;
  end if;
end $$;
