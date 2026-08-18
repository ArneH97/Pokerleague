-- Pokerleague — de agenda van een speler, over al zijn clubs heen
--
-- Een speler kon tot nu alleen zien wanneer er gespeeld werd door per club de
-- kalender te openen. Bij één club valt dat mee. Bij twee is het al vervelend,
-- en precies die tweede club is het hele punt van dit platform: als je bij
-- Cutoff én bij Aalst speelt, is de vraag niet "wat doet Aalst donderdag" maar
-- "waar kan ik deze week terecht".
--
-- Vandaar één lijst. Wat komt er aan, bij welke club, wat kost het, en zit ik
-- er al in.
--
-- **Wat hij mag zien is niet nieuw.** Dezelfde regel als `can_view_tournament`:
-- een avond die op `public` staat, of op `members` bij een club waar hij lid
-- van is. Een besloten avond blijft besloten. Deze functie brengt dus niets
-- naar boven wat een speler niet al op de clubpagina te zien kreeg; ze spaart
-- hem alleen het rondklikken.
--
-- **Ook wat nú bezig is.** Een tornooi dat om acht uur begon en waar het al
-- half tien is, is geen verleden tijd — daar kan je nog binnenlopen als de
-- late registratie openstaat. Het staat dus bovenaan en niet nergens.

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
  entries        int,
  i_play         boolean
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
    (select count(*)::int from tournament_players x where x.tournament_id = t.id),
    exists (
      select 1 from tournament_players x
      where x.tournament_id = t.id and x.player_id = (select id from me)
    )
  from tournaments t
  join clubs c on c.id = t.club_id
  where t.club_id in (select club_id from mijn_clubs)
    and t.status in ('scheduled', 'running', 'paused')
    -- Dezelfde zichtbaarheidsregel als overal elders.
    and (t.player_visibility = 'public'
         or (t.player_visibility = 'members' and public.is_club_player(t.club_id))
         or public.is_club_member(t.club_id))
    -- Een avond van gisteren die nooit afgesloten werd, hoort hier niet meer
    -- te blijven staan. Twaalf uur speling: wie 's nachts kijkt ziet de avond
    -- van vanavond nog gewoon staan.
    and t.scheduled_at >= now() - interval '12 hours'
    and t.scheduled_at <= now() + (greatest(p_days, 1) || ' days')::interval
  order by t.scheduled_at
$$;

comment on function public.my_calendar(int) is
  'De komende avonden bij alle clubs van de aangemelde speler, met de prijs en of hij al ingeschreven staat. Volgt dezelfde zichtbaarheidsregel als can_view_tournament.';

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    revoke all on function public.my_calendar(int) from public;
    grant execute on function public.my_calendar(int) to authenticated, service_role;
  end if;
end $$;
