-- Pokerleague — de speler doet alles op het platform, de club werkt op haar eigen domein
--
-- Tot nu stond bijna alles twee keer open. Een clubdomein toonde kalender,
-- klassement en uitslagen aan iedereen, en het platform deed hetzelfde nog
-- eens. Dat leverde twee problemen op die op hetzelfde neerkomen.
--
-- **Voor de speler was niet uit te leggen waar iets stond.** Zijn resultaten
-- op de ene plek, het klassement op de andere, en op geen van beide iets dat
-- naar de andere wees. Dat is de verwarring waar dit hele stuk over gaat.
--
-- **En het stond wijder open dan bedoeld.** Wie speelde, wanneer, en hoe hij
-- eindigde — dat is met pseudoniemen nog altijd een tijdlijn van iemands
-- avonden, leesbaar voor wie de clubnaam kent. Voor een uitslagenlijst van een
-- pokerclub is "iedereen op internet" een ruimere kring dan nodig.
--
-- Vanaf nu:
--
--   * **Clubinfo blijft open.** Naam, gemeente, adres, speeldag, contact,
--     openingsdatum. Dat is een uithangbord en dat hoort vindbaar te zijn,
--     ook via Google — anders vindt een nieuwe speler de club nooit.
--   * **Cijfers vragen een account.** Kalender, uitslagen, klassement en
--     deelnemerslijsten. Gratis, in twee velden, maar wel een account.
--   * **De zaalklok is voor de floor.** Die opent hij in de zaal; het is geen
--     pagina om ergens naar door te sturen.

-- ---------------------------------------------------------------------------
-- 1. De publieke clubfuncties gaan dicht voor bezoekers
-- ---------------------------------------------------------------------------
-- Ze blijven bestaan en ze blijven precies hetzelfde doen — inclusief de
-- naamregel, die is niet vervangen door deze afscherming maar staat erachter.
-- Een aangemelde speler is nog altijd een vreemde voor de mensen op die lijst.
--
-- **Intrekken bij `anon` volstaat niet.** PostgreSQL geeft bij het aanmaken van
-- een functie automatisch EXECUTE aan `PUBLIC`, en `anon` erft dat. Wie alleen
-- `revoke ... from anon` schrijft, ziet zijn migratie zonder fout doorlopen en
-- verandert precies niets — een afscherming die stilzwijgend niet werkt is
-- erger dan geen afscherming, want je denkt dat het geregeld is. Dus eerst weg
-- bij PUBLIC, dan gericht teruggeven aan wie het wél mag.

do $$
declare
  fn text;
  r   text;
begin
  foreach fn in array array[
    'public.club_public_clock(uuid)',
    'public.club_public_levels(uuid)',
    'public.club_public_seats(uuid)',
    'public.club_public_result(uuid)',
    'public.club_public_standings(text, date, date)',
    'public.tournament_prizes(uuid)'
  ] loop
    execute format('revoke execute on function %s from public', fn);

    if exists (select 1 from pg_roles where rolname = 'anon') then
      execute format('revoke execute on function %s from anon', fn);
    end if;

    foreach r in array array['authenticated', 'service_role'] loop
      if exists (select 1 from pg_roles where rolname = r) then
        execute format('grant execute on function %s to %I', fn, r);
      end if;
    end loop;
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- 2. En de agenda ook
-- ---------------------------------------------------------------------------
-- De kalender leest rechtstreeks uit `tournaments`, want daar staan geen namen
-- bij. Die leesregel liet elk publiek tornooi door aan iedereen, ook zonder
-- account. Nu moet je aangemeld zijn — en de rest van de regel blijft staan:
-- staf ziet alles van de eigen club, leden zien wat voor leden bedoeld is.

drop policy if exists tournaments_read on tournaments;
create policy tournaments_read on tournaments
  for select using (
    public.is_club_member(club_id)
    or (auth.uid() is not null and player_visibility = 'public')
    or (player_visibility = 'members' and public.is_club_player(club_id))
  );

comment on policy tournaments_read on tournaments is
  'Staf ziet alles van de eigen club. Een aangemelde speler ziet publieke tornooien van elke club en de ledentornooien van zijn eigen clubs. Een bezoeker zonder account ziet niets: de agenda hoort bij het platform, niet bij de etalage.';

-- ---------------------------------------------------------------------------
-- 3. Wat een bezoeker wél te zien krijgt
-- ---------------------------------------------------------------------------
-- Eén functie voor het visitekaartje, zodat de clubpagina niet meer op de hele
-- `clubs`-rij hoeft te leunen. Die rij bevat namelijk ook `settings` en
-- `compliance` — instellingen die niemand van buiten hoeft te kennen, en die
-- vandaag gewoon meekomen in elke select die een pagina doet.
--
-- De kolommen hieronder zijn met opzet opgesomd en niet `select *`. Wie er
-- later een veld bij zet op `clubs`, zet het niet per ongeluk op straat.

create or replace function public.club_card(p_slug text)
returns table (
  slug          text,
  name          text,
  city          text,
  intro         text,
  address_line  text,
  maps_url      text,
  play_rhythm   text,
  contact_email text,
  contact_phone text,
  opens_on      date,
  logo_url      text,
  primary_color text,
  locale        text,
  open_signup   boolean,
  members       int
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    c.slug, c.name, c.city, c.intro, c.address_line, c.maps_url, c.play_rhythm,
    c.contact_email, c.contact_phone, c.opens_on, c.logo_url, c.primary_color,
    c.locale, c.open_signup,
    (select count(*)::int from club_players cp where cp.club_id = c.id)
  from clubs c
  where c.slug = p_slug and c.is_active
$$;

comment on function public.club_card(text) is
  'Het visitekaartje van een club: waar het is, wanneer er gespeeld wordt, aan wie je iets vraagt. Bewust open voor bezoekers zonder account — een club moet vindbaar zijn. Bewust een opsomming van kolommen en geen select *, zodat een nieuw veld op clubs niet vanzelf publiek wordt.';

create or replace function public.club_cards()
returns table (
  slug        text,
  name        text,
  city        text,
  intro       text,
  logo_url    text,
  play_rhythm text,
  open_signup boolean,
  members     int
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    c.slug, c.name, c.city, c.intro, c.logo_url, c.play_rhythm, c.open_signup,
    (select count(*)::int from club_players cp where cp.club_id = c.id)
  from clubs c
  where c.is_active
  order by c.name
$$;

comment on function public.club_cards() is
  'Alle actieve clubs, voor de clubgids op het platform. Geen custom_domain: een bezoeker hoort naar de clubpagina op het platform te gaan, niet naar het werkdomein van de club.';

-- ---------------------------------------------------------------------------
-- 4. Rechten
-- ---------------------------------------------------------------------------

do $$
declare r text;
begin
  foreach r in array array['anon', 'authenticated'] loop
    if exists (select 1 from pg_roles where rolname = r) then
      execute format('grant execute on function public.club_card(text) to %I', r);
      execute format('grant execute on function public.club_cards()    to %I', r);
    end if;
  end loop;
end $$;
