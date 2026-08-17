-- Pokerleague — publieke namen afkorten tot "Arne H."
--
-- Tot nu stond er op de publieke pagina's ofwel een volledige naam, ofwel een
-- gebruikersnaam. Dat is een keuze tussen te veel en te weinig: een volledige
-- naam met gemeente erbij is een persoonsgegeven dat een pokerclub niet hoeft
-- rond te strooien, en "Speler a3f2" maakt een klassement onleesbaar voor de
-- mensen die erin staan.
--
-- De voornaam met de eerste letter van de achternaam ligt daartussen en is
-- wat elke club op een uitslagblad zet. Aan tafel weet iedereen wie "Arne H."
-- is; een vreemde die de pagina vindt weet dat niet, en heeft er ook niets aan.
--
-- Dit geldt overal waar een buitenstaander een naam ziet: het klassement, de
-- uitslag van een avond, en de deelnemerslijst van een lopend tornooi. De
-- clubkant verandert niet — daar staat de volledige naam, want de floor moet
-- weten wie er voor hem staat.

-- ---------------------------------------------------------------------------
-- 1. Afkorten
-- ---------------------------------------------------------------------------

create or replace function public.short_name(p_full text)
returns text
language sql
immutable
as $$
  with woorden as (
    select regexp_split_to_array(trim(regexp_replace(coalesce(p_full, ''), '\s+', ' ', 'g')), ' ') as w
  )
  select case
    -- Geen naam, of één woord: dan valt er niets af te korten. "Julien"
    -- blijft "Julien".
    when array_length(w, 1) is null or array_length(w, 1) < 2 then coalesce(p_full, '')
    -- Anders: het eerste woord voluit, en de eerste letter van het tweede.
    -- Bij "Marcel Van de Putte" is dat "Marcel V." — de eerste letter van de
    -- achternaam, en niet die van het laatste woord, want dan werd het "P."
    -- en dat herkent niemand.
    else w[1] || ' ' || upper(left(w[2], 1)) || '.'
  end
  from woorden;
$$;

comment on function public.short_name(text) is
  'Voornaam plus de eerste letter van de achternaam: "Arne Halsberghe" wordt "Arne H.". Namen van één woord blijven staan.';

-- ---------------------------------------------------------------------------
-- 2. De naamregel gebruikt de afkorting
-- ---------------------------------------------------------------------------
-- Zelfde functie, zelfde plaats, alleen korter antwoord. Alles wat erop
-- steunt — de deelnemerslijst, de uitslag, het klassement — volgt vanzelf.

create or replace function public.public_name(
  p_display        text,
  p_username       text,
  p_id             uuid,
  p_public_listing boolean,
  p_public_profile boolean,
  p_club_names     boolean
)
returns text
language sql
immutable
as $$
  select case
    when coalesce(p_club_names, false)
      or (coalesce(p_public_listing, false) and coalesce(p_public_profile, false))
    then public.short_name(p_display)
    else coalesce(nullif(trim(p_username), ''), 'Speler ' || left(p_id::text, 4))
  end;
$$;

comment on function public.public_name(text, text, uuid, boolean, boolean, boolean) is
  'De enige plek waar bepaald wordt hoe een buitenstaander een speler ziet. Toont een club namen, dan is dat de afgekorte vorm ("Arne H."); anders een gebruikersnaam.';

-- ---------------------------------------------------------------------------
-- 3. Rechten
-- ---------------------------------------------------------------------------

do $$
declare
  r text;
begin
  foreach r in array array['anon', 'authenticated'] loop
    if exists (select 1 from pg_roles where rolname = r) then
      execute format('grant execute on function public.short_name(text) to %I', r);
    end if;
  end loop;
end $$;
