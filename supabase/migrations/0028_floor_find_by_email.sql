-- Pokerleague — de floor vindt iemand die al op het platform staat
--
-- Twee dingen die aan het licht kwamen bij het eerste echte gebruik.
--
-- **De zoekfunctie aan de deur keek alleen in het eigen ledenbestand.** Dat
-- klopt voor het gewone geval — je zoekt iemand die hier al speelde — maar het
-- klopt niet voor de speler die zich op het platform registreerde en vanavond
-- voor het eerst komt. Die bestaat wel degelijk, alleen niet bij deze club, en
-- dus zag de floor niets en tikte hij hem in als nieuwe man. Dat ging goed —
-- het mailadres is de sleutel en de koppeling gebeurde alsnog — maar de floor
-- kon dat niet weten en had geen enkele bevestiging.
--
-- Zoeken over het hele platform op naam is geen optie: dan kan elke club met
-- een floor-account de spelersbestanden van alle andere clubs uitlezen door
-- letters in te typen. Op een volledig mailadres wél. Dat adres is geen
-- vondst maar een gegeven: de floor heeft het net van die persoon gehoord.
-- Wie het al weet, weet niets nieuws.
--
-- **En de weergavenaam bleef hangen.** Wie zich registreerde vóór zijn naam
-- bekend was kreeg het stuk voor de apenstaart van zijn mailadres als naam.
-- De trigger die display_name bijhoudt vult alleen aan wat leeg is — terecht,
-- anders overschrijf je wat een club bewust instelde — dus bleef dat staan
-- ook nadat voornaam en achternaam alsnog binnenkwamen.

-- ---------------------------------------------------------------------------
-- 1. Opzoeken op volledig mailadres
-- ---------------------------------------------------------------------------

create or replace function public.floor_find_by_email(
  p_club_id uuid,
  p_email   text
)
returns table (
  player_id    uuid,
  display_name text,
  is_member    boolean,
  has_account  boolean
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_email text := lower(trim(coalesce(p_email, '')));
begin
  if not public.is_service_context()
     and not public.has_club_role(p_club_id, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten' using errcode = 'insufficient_privilege';
  end if;

  -- Alleen een volledig adres. Een halve zoekterm zou dit een zoekmachine
  -- door andermans ledenbestand maken.
  if v_email = '' or v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    return;
  end if;

  return query
  select
    p.id,
    p.display_name,
    exists (select 1 from club_players cp where cp.club_id = p_club_id and cp.player_id = p.id),
    p.auth_user_id is not null
  from players p
  where lower(p.email) = v_email
    and p.merged_into_id is null
  limit 1;
end;
$$;

comment on function public.floor_find_by_email(uuid, text) is
  'Zoekt een speler op volledig mailadres over het hele platform, zodat de floor iemand die elders al speelt niet als nieuwe persoon intikt. Bewust geen zoeken op naamfragmenten: dat zou de ledenbestanden van andere clubs doorzoekbaar maken.';

-- ---------------------------------------------------------------------------
-- 2. Eigen naam wint van de noodnaam
-- ---------------------------------------------------------------------------

create or replace function public.claim_my_player(
  p_first_name text default null,
  p_last_name  text default null,
  p_username   text default null,
  p_listing    boolean default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid   uuid  := auth.uid();
  v_email text  := public.auth_email();
  v_meta  jsonb := public.auth_meta();
  v_id    uuid;
  v_first text    := coalesce(nullif(trim(p_first_name), ''), nullif(trim(v_meta->>'first_name'), ''));
  v_last  text    := coalesce(nullif(trim(p_last_name),  ''), nullif(trim(v_meta->>'last_name'),  ''));
  v_user  text    := coalesce(nullif(trim(p_username),   ''), nullif(trim(v_meta->>'username'),   ''));
  v_list  boolean := coalesce(p_listing, (v_meta->>'public_listing')::boolean, false);
  -- De naam zoals die op een scherm hoort te staan, als we hem kennen.
  v_full  text    := nullif(trim(coalesce(v_first, '') || ' ' || coalesce(v_last, '')), '');
begin
  if v_uid is null then
    raise exception 'Niet aangemeld' using errcode = 'insufficient_privilege';
  end if;
  if v_email is null then
    raise exception 'Dit account heeft geen mailadres' using errcode = 'check_violation';
  end if;

  select id into v_id
  from players
  where auth_user_id = v_uid and merged_into_id is null;

  if found then
    update players
    set first_name   = coalesce(first_name, v_first),
        last_name    = coalesce(last_name,  v_last),
        username     = coalesce(username,   v_user),
        -- Stond er nog de noodnaam uit het mailadres, dan wint de echte naam.
        -- Een naam die iemand zelf opgaf is beter dan wat wij verzonnen; een
        -- naam die de club instelde laten we staan zolang die er al was.
        display_name = case
          when v_full is not null and display_name = split_part(lower(v_email), '@', 1)
          then v_full else display_name end
    where id = v_id;
    return v_id;
  end if;

  select id into v_id
  from players
  where lower(email) = v_email
    and auth_user_id is null
    and merged_into_id is null
  limit 1;

  if found then
    update players
    set auth_user_id   = v_uid,
        link_state     = 'claimed',
        first_name     = coalesce(v_first, first_name),
        last_name      = coalesce(v_last,  last_name),
        username       = coalesce(username, v_user),
        display_name   = coalesce(v_full, display_name),
        public_listing = v_list
    where id = v_id;
    return v_id;
  end if;

  insert into players (
    display_name, first_name, last_name, username, email,
    auth_user_id, link_state, public_listing
  ) values (
    coalesce(v_full, split_part(v_email, '@', 1)),
    v_first, v_last, v_user, v_email, v_uid, 'claimed', v_list
  )
  returning id into v_id;

  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Wat er al scheef staat rechttrekken
-- ---------------------------------------------------------------------------
-- Profielen waar de weergavenaam nog het stuk voor de apenstaart is, terwijl
-- voornaam en achternaam intussen wel ingevuld zijn.

update players
set display_name = trim(first_name || ' ' || last_name)
where first_name is not null
  and last_name is not null
  and email is not null
  and display_name = split_part(lower(email), '@', 1);

-- ---------------------------------------------------------------------------
-- 4. Rechten
-- ---------------------------------------------------------------------------

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function public.floor_find_by_email(uuid, text) to authenticated;
  end if;
end $$;
