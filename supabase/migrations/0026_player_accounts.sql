-- Pokerleague — een speler maakt een account
--
-- De volgorde is hier omgekeerd aan wat je zou verwachten, en dat is precies
-- het probleem dat deze migratie oplost.
--
-- Normaal maakt iemand eerst een account en bestaat hij daarna. Bij een
-- pokerclub bestaat hij al lang voordat hij een account maakt: de floor typte
-- zijn naam en mailadres aan de deur, hij speelde acht avonden mee, en hij
-- staat met punten in het klassement. Die rij in `players` heeft alleen nog
-- geen `auth_user_id`.
--
-- Registreert die man zich later, dan mag er géén tweede profiel bijkomen. Dan
-- staat hij twee keer in het ledenbestand, met zijn historie bij de ene helft
-- en zijn account bij de andere. Vandaar dat registreren hier niet "aanmaken"
-- betekent maar "opeisen": we zoeken op mailadres, en alleen als er niets
-- gevonden wordt maken we iets nieuws.
--
-- Dat opeisen kan de speler niet zelf doen met een gewone update. Op het
-- moment dat hij het probeert is het profiel nog van niemand, dus laat geen
-- enkele policy hem erbij. Een functie met de rechten van de eigenaar wel — en
-- die controleert dan zelf het enige wat telt: dat het mailadres van zijn
-- account overeenkomt met dat van het profiel.

-- ---------------------------------------------------------------------------
-- 1. Het mailadres van wie er aanklopt
-- ---------------------------------------------------------------------------
-- Uit het token en niet uit een formulierveld. Anders eist iemand het profiel
-- van zijn buurman op door diens adres in te tikken.

create or replace function public.auth_email()
returns text
language sql
stable
as $$
  select nullif(lower(trim(coalesce(
    current_setting('request.jwt.claim.email', true),
    (current_setting('request.jwt.claims', true)::jsonb ->> 'email')
  ))), '');
$$;

comment on function public.auth_email() is
  'Het geverifieerde mailadres uit het token van de aangemelde gebruiker. Nooit uit een formulier: dat is het verschil tussen opeisen en overnemen.';

-- ---------------------------------------------------------------------------
-- 2. Opeisen of aanmaken
-- ---------------------------------------------------------------------------

create or replace function public.claim_my_player(
  p_first_name text default null,
  p_last_name  text default null,
  p_username   text default null,
  p_listing    boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid   uuid := auth.uid();
  v_email text := public.auth_email();
  v_id    uuid;
begin
  if v_uid is null then
    raise exception 'Niet aangemeld' using errcode = 'insufficient_privilege';
  end if;
  if v_email is null then
    raise exception 'Dit account heeft geen mailadres' using errcode = 'check_violation';
  end if;

  -- Al gekoppeld? Dan is er niets te doen. Deze functie moet twee keer
  -- draaien kunnen: de spelerspagina roept hem aan bij elk bezoek, want een
  -- profiel kan ook ná de registratie door de floor aangemaakt zijn.
  select id into v_id
  from players
  where auth_user_id = v_uid and merged_into_id is null;
  if found then
    return v_id;
  end if;

  -- Bestaat er een profiel op dit adres dat nog van niemand is? Dan is dat
  -- het zijne, met zijn hele historie eraan.
  select id into v_id
  from players
  where lower(email) = v_email
    and auth_user_id is null
    and merged_into_id is null
  limit 1;

  if found then
    update players
    set auth_user_id = v_uid,
        link_state   = 'claimed',
        -- Wat de speler zelf opgeeft wint van wat de floor ooit intikte; die
        -- had haast en hoorde de naam door het lawaai heen.
        first_name   = coalesce(nullif(trim(p_first_name), ''), first_name),
        last_name    = coalesce(nullif(trim(p_last_name), ''), last_name),
        username     = coalesce(username, nullif(trim(p_username), '')),
        public_listing = coalesce(p_listing, public_listing)
    where id = v_id;
    return v_id;
  end if;

  -- Niets gevonden: een speler die nog nooit ergens aan tafel zat.
  insert into players (
    display_name, first_name, last_name, username, email,
    auth_user_id, link_state, public_listing
  ) values (
    coalesce(nullif(trim(coalesce(p_first_name, '') || ' ' || coalesce(p_last_name, '')), ''),
             split_part(v_email, '@', 1)),
    nullif(trim(p_first_name), ''),
    nullif(trim(p_last_name), ''),
    nullif(trim(p_username), ''),
    v_email,
    v_uid,
    'claimed',
    coalesce(p_listing, false)
  )
  returning id into v_id;

  return v_id;
end;
$$;

comment on function public.claim_my_player(text, text, text, boolean) is
  'Koppelt de aangemelde gebruiker aan zijn spelersprofiel: bestaand profiel op hetzelfde mailadres, of anders een nieuw. Meermaals aanroepen is veilig.';

-- ---------------------------------------------------------------------------
-- 3. Mijn eigen gegevens
-- ---------------------------------------------------------------------------
-- Lezen mag via de gewone policy (players_self_update leest ook), maar één
-- functie die alles in één keer teruggeeft scheelt drie rondjes en houdt de
-- kolomkeuze op één plek — zodat er nooit per ongeluk een geboortedatum in
-- een lijst belandt waar hij niet hoort.

create or replace function public.my_player()
returns table (
  id             uuid,
  display_name   text,
  first_name     text,
  last_name      text,
  username       text,
  email          text,
  locale         text,
  public_listing boolean,
  public_profile boolean,
  clubs_count    int,
  results_count  int
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    p.id, p.display_name, p.first_name, p.last_name, p.username, p.email,
    p.locale, p.public_listing, p.public_profile,
    (select count(*)::int from club_players cp where cp.player_id = p.id),
    (select count(*)::int from tournament_results r where r.player_id = p.id)
  from players p
  where p.auth_user_id = auth.uid() and p.merged_into_id is null;
$$;

-- ---------------------------------------------------------------------------
-- 4. Mijn resultaten, over clubs heen
-- ---------------------------------------------------------------------------
-- Dít is waarvoor een speler een account maakt. Niet om zijn gegevens te
-- beheren maar om te zien hoe hij het doet — en over clubs heen is precies
-- wat geen enkele club hem kan tonen.
--
-- Eigen resultaten, dus mét prijzengeld. Dat is zijn eigen geld; de
-- afscherming die op de publieke kant zit gaat over andermans geld.

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
    r.prize_cents, r.points, r.knockouts
  from tournament_results r
  join players p     on p.id = r.player_id
  join tournaments t on t.id = r.tournament_id
  join clubs c       on c.id = t.club_id
  where p.auth_user_id = auth.uid()
  order by r.finished_at desc;
$$;

-- ---------------------------------------------------------------------------
-- 5. Rechten
-- ---------------------------------------------------------------------------

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function public.auth_email()                                  to authenticated;
    grant execute on function public.claim_my_player(text, text, text, boolean)    to authenticated;
    grant execute on function public.my_player()                                   to authenticated;
    grant execute on function public.my_results()                                  to authenticated;
  end if;
end $$;
