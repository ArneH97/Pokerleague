-- Pokerleague — de naam die bij de registratie werd ingevuld raakte zoek
--
-- Wat er misging, en het is een leerzaam foutje.
--
-- Bij het registreren geeft iemand zijn voornaam, achternaam en
-- gebruikersnaam op. Staat bevestiging per mail aan — en dat hoort zo — dan is
-- er op dat moment nog géén sessie: hij moet eerst op de link in zijn mailbox
-- klikken. De browser kon het profiel dus niet meteen opeisen, want er was
-- niemand om het aan toe te kennen.
--
-- Klikt hij daarna op de link, dan komt hij binnen als een aangemelde
-- gebruiker en eist de spelerspagina zijn profiel alsnog op — maar die pagina
-- weet niets van wat hij in het formulier typte. Resultaat: een profiel met
-- als naam het stuk vóór de apenstaart van zijn mailadres.
--
-- De oplossing is niet om die gegevens tussentijds ergens op te slaan. Ze
-- stáán al ergens: signUp() hangt ze aan de gebruiker als user_metadata, en
-- die reist mee in het token. We hoeven ze alleen te lezen.
--
-- Meteen ook twee functies erbij die een vraag beantwoorden waar de
-- spelerspagina tot nu het antwoord op schuldig bleef: bij welke clubs hoor
-- ik, en bij welke ben ik medewerker. Dat zijn twee verschillende dingen en
-- het verschil is niet vanzelfsprekend.

-- ---------------------------------------------------------------------------
-- 1. Wat de gebruiker bij zijn registratie meegaf
-- ---------------------------------------------------------------------------

create or replace function public.auth_meta()
returns jsonb
language sql
stable
as $$
  select coalesce(
    nullif(current_setting('request.jwt.claims', true), '')::jsonb -> 'user_metadata',
    '{}'::jsonb
  );
$$;

comment on function public.auth_meta() is
  'De gegevens die bij signUp() aan het account gehangen zijn. Komen uit het token, dus even betrouwbaar als het mailadres.';

-- ---------------------------------------------------------------------------
-- 2. Opeisen, nu ook zonder dat het formulier iets meestuurt
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
  -- Wat het formulier meestuurt wint; anders wat er bij de registratie is
  -- opgegeven. Zo werkt beide wegen: meteen binnen, of pas na de mail.
  v_first text    := coalesce(nullif(trim(p_first_name), ''), nullif(trim(v_meta->>'first_name'), ''));
  v_last  text    := coalesce(nullif(trim(p_last_name),  ''), nullif(trim(v_meta->>'last_name'),  ''));
  v_user  text    := coalesce(nullif(trim(p_username),   ''), nullif(trim(v_meta->>'username'),   ''));
  v_list  boolean := coalesce(p_listing, (v_meta->>'public_listing')::boolean, false);
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
    -- Al gekoppeld. Toch bijwerken wat er nog ontbreekt: het profiel kan
    -- aangemaakt zijn vóór we bij de metadata konden — precies het geval dat
    -- deze migratie repareert. Wat er al staat blijft staan.
    update players
    set first_name = coalesce(first_name, v_first),
        last_name  = coalesce(last_name,  v_last),
        username   = coalesce(username,   v_user)
    where id = v_id
      and (first_name is null or last_name is null or username is null);
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
        public_listing = v_list
    where id = v_id;
    return v_id;
  end if;

  insert into players (
    display_name, first_name, last_name, username, email,
    auth_user_id, link_state, public_listing
  ) values (
    coalesce(nullif(trim(coalesce(v_first, '') || ' ' || coalesce(v_last, '')), ''),
             split_part(v_email, '@', 1)),
    v_first, v_last, v_user, v_email, v_uid, 'claimed', v_list
  )
  returning id into v_id;

  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Bij welke clubs hoor ik, en waar ben ik medewerker
-- ---------------------------------------------------------------------------
-- Twee verschillende dingen, en het verschil is niet vanzelfsprekend:
--
--   * speler bij een club — je staat in hun ledenbestand, je speelt er mee.
--     Dat gebeurt doordat de club je toevoegt, niet doordat jij ergens klikt.
--   * medewerker van een club — je bedient er de floor of je beheert hem.
--
-- Dezelfde persoon kan beide zijn, of geen van beide. Wie een account maakt op
-- het platform is om te beginnen geen van beide, en dat is precies wat
-- verwarrend is als de pagina er niets over zegt.

create or replace function public.my_clubs()
returns table (
  slug     text,
  name     text,
  city     text,
  logo_url text,
  since    timestamptz
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select c.slug, c.name, c.city, c.logo_url, cp.created_at
  from club_players cp
  join clubs c   on c.id = cp.club_id
  join players p on p.id = cp.player_id
  where p.auth_user_id = auth.uid() and p.merged_into_id is null
  order by c.name;
$$;

create or replace function public.my_staff_clubs()
returns table (
  slug     text,
  name     text,
  logo_url text,
  role     text
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select c.slug, c.name, c.logo_url, m.role::text
  from club_members m
  join clubs c on c.id = m.club_id
  where m.user_id = auth.uid()
  order by c.name;
$$;

comment on function public.my_staff_clubs() is
  'Clubs waar deze gebruiker floor, beheerder of eigenaar is. Hangt aan het account en niet aan het spelersprofiel: staf zijn en spelen zijn twee losse dingen.';

-- ---------------------------------------------------------------------------
-- 4. Rechten
-- ---------------------------------------------------------------------------

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function public.auth_meta()        to authenticated;
    grant execute on function public.my_clubs()         to authenticated;
    grant execute on function public.my_staff_clubs()   to authenticated;
  end if;
end $$;
