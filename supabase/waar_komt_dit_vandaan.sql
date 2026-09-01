-- Pokerleague — waar komen die cijfers op /ik vandaan?
--
-- Dit bestand verandert niets. Het kijkt alleen.
--
-- Je dashboard leest `tournament_results`: per afgesloten avond één rij per
-- speler. Zie je daar acht avonden staan, dan bestaan die acht avonden nog in
-- de databank — met hun club erbij, want zonder club is er geen resultaat.
-- Dat betekent dat het opruimscript niet gedraaid heeft, of gestopt is voor
-- het iets verwijderde.
--
-- Draai dit in de SQL-editor van het project waar pokerleague.be op draait.
-- Belangrijk: hetzelfde project. Twee Supabase-projecten waarvan er eentje
-- opgeruimd is en de andere niet, ziet er van buitenaf precies zo uit als dit.

-- ---------------------------------------------------------------------------
-- 1. Wat er in het geheel staat
-- ---------------------------------------------------------------------------

select
  (select count(*) from clubs)                    as clubs,
  (select count(*) from tournaments)              as avonden,
  (select count(*) from tournament_results)       as uitslagen,
  (select count(*) from players)                  as spelersprofielen,
  (select count(*) from club_players)             as lidmaatschappen,
  (select count(*) from buyins)                   as inkopen;

-- ---------------------------------------------------------------------------
-- 2. Welke clubs, en hoeveel hangt er aan
-- ---------------------------------------------------------------------------

select
  c.slug,
  c.name,
  (select count(*) from tournaments t where t.club_id = c.id)        as avonden,
  (select count(*) from tournament_results r
     join tournaments t on t.id = r.tournament_id
    where t.club_id = c.id)                                          as uitslagen,
  (select count(*) from club_players cp where cp.club_id = c.id)     as leden
from clubs c
order by c.slug;

-- ---------------------------------------------------------------------------
-- 3. Elke avond die er nog staat
-- ---------------------------------------------------------------------------
-- Let op de kolom `naam_exact`: daar staan aanhalingstekens omheen, zodat je
-- een spatie te veel of een hoofdletter ziet. Het opruimscript zoekt de avond
-- die blijft op naam, en één verschil is genoeg om het hele script te laten
-- stoppen zonder iets te doen.

select
  c.slug                       as club,
  '"' || t.name || '"'         as naam_exact,
  t.id                         as tornooi_id,
  t.status,
  t.scheduled_at,
  (select count(*) from tournament_results r where r.tournament_id = t.id) as uitslagen,
  (select count(*) from tournament_players tp where tp.tournament_id = t.id) as deelnames
from tournaments t
join clubs c on c.id = t.club_id
order by t.scheduled_at;

-- ---------------------------------------------------------------------------
-- 4. En dan de vraag zelf: wat voedt jouw dashboard?
-- ---------------------------------------------------------------------------
-- Precies de rijen die `/ik` optelt, met het spelersprofiel erbij waarop ze
-- staan. Staat er meer dan één profiel-id in deze lijst, dan hangen je
-- resultaten aan twee profielen en is dat een tweede ding om op te lossen.

select
  u.email                as jouw_account,
  p.id                   as spelersprofiel,
  p.display_name,
  c.slug                 as club,
  t.name                 as avond,
  r.finished_at::date    as gespeeld_op,
  r.position             as plaats,
  round(r.prize_cents / 100.0, 2) as prijzengeld_euro,
  r.points
from tournament_results r
join players p     on p.id = r.player_id
join tournaments t on t.id = r.tournament_id
join clubs c       on c.id = t.club_id
join auth.users u  on u.id = p.auth_user_id
where lower(u.email) = 'arne@halcoservices.be'
order by r.finished_at desc;

-- Hetzelfde in één regel: het netto dat bovenaan je scherm staat.
select
  count(*)                                          as gespeeld,
  count(*) filter (where r.position = 1)            as gewonnen,
  round(sum(r.prize_cents) / 100.0, 2)               as prijzengeld_euro,
  min(r.finished_at)::date                          as eerste,
  max(r.finished_at)::date                          as laatste
from tournament_results r
join players p    on p.id = r.player_id
join auth.users u on u.id = p.auth_user_id
where lower(u.email) = 'arne@halcoservices.be';
