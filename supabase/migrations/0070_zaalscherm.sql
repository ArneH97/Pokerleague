-- Pokerleague — een klok voor een tv die te oud is voor de app
--
-- De zaalweergave is een pagina van de app, en de app vraagt een browser van
-- 2023: Next zegt Chrome 111, Tailwind zegt Chrome 111. Een Samsung uit 2023
-- draait Chromium 94, een uit 2020 draait 69. Daar valt de hele stylesheet
-- weg en blijft er een kale lijst links over. Dat is geen schoonheidsfoutje;
-- dat is geen klok.
--
-- Vandaar een tweede weg naar hetzelfde getal: één adres dat kant-en-klare
-- HTML teruggeeft, zonder framework, zonder Tailwind, met alleen dingen die
-- een browser van 2020 al kende. Die pagina zit in de app
-- (`/c/<club>/zaal`), dit bestand levert alleen waar ze haar cijfers haalt.
--
-- **Waarom er een sleutel bij hoort.** Sinds migratie 0034 ziet een bezoeker
-- zonder account niets, ook niet van een publiek tornooi — de deelnemerslijst
-- hoort bij het platform en niet bij de etalage, en dat is een bewuste keuze
-- die hier niet omver mag. Maar een tv kan zich niet aanmelden: iemand zou
-- met een afstandsbediening een mailadres en een wachtwoord moeten intikken,
-- en de meeste tv-browsers gooien die sessie weg zodra ze dichtgaan.
--
-- De uitweg is een sleutel in het adres. Niet de hele wereld mag meekijken,
-- wie de sleutel van de club heeft wel. Dat is precies hetzelfde slot als op
-- de deur van de zaal: geen wachtwoord per persoon, maar één ding dat je
-- hebt of niet hebt.
--
-- **Zonder tornooi-id.** Het adres noemt alleen de club. De functie zoekt
-- zelf de avond die nu bezig is. Dat scheelt niet alleen zesendertig tekens
-- UUID op een afstandsbediening — het betekent ook dat de tv één adres
-- onthoudt en elke zondag vanzelf de juiste avond toont.
--
-- Dit bestand voegt alleen toe. Geen bestaande functie, regel of kolom
-- verandert, dus je mag het midden in een avond draaien.

-- ---------------------------------------------------------------------------
-- 1. De sleutel
-- ---------------------------------------------------------------------------

alter table clubs
  add column if not exists screen_key text;

comment on column public.clubs.screen_key is
  'Sleutel voor het zaalscherm. Staat in het adres dat op de tv in de zaal getikt wordt; wie hem heeft mag de klok van die club zien zonder account.';

/**
 * Een nieuwe sleutel.
 *
 * Kleine letters en cijfers, zonder de tekens die je op een afstandsbediening
 * verkeerd leest of verkeerd kiest: geen 0 tegenover o, geen 1 tegenover l.
 * Tien tekens uit dit alfabet is ruim een biljoen mogelijkheden — genoeg voor
 * iets dat een klok toont en verder niets, en nog net te doen om één keer met
 * een afstandsbediening in te tikken.
 */
create or replace function public.new_screen_key()
returns text
language sql
volatile
as $$
  select string_agg(
    substr('abcdefghjkmnpqrstuvwxyz23456789',
           1 + floor(random() * 31)::int, 1), '')
  from generate_series(1, 10);
$$;

comment on function public.new_screen_key() is
  'Een verse sleutel voor een zaalscherm: tien tekens, zonder tekens die je op een afstandsbediening verwart.';

-- Vanaf nu krijgt elke nieuwe club er vanzelf een. Als standaardwaarde en
-- niet met een trigger: een club zonder sleutel is een club waarvan het
-- zaalscherm het niet doet, en dat wil je niet pas merken op de avond zelf.
alter table clubs
  alter column screen_key set default public.new_screen_key();

-- Elke club die er nog geen heeft, krijgt er een. Wie er al een heeft houdt
-- hem, zodat een tv die al ingetikt staat niet stilvalt.
update clubs
set screen_key = public.new_screen_key()
where screen_key is null;

/**
 * De sleutel opnieuw zetten, voor wie hem kwijt is of wil vervangen.
 *
 * Alleen een eigenaar of beheerder. Een floor hoeft dit niet te kunnen: het
 * is een instelling van de club, geen handeling van een avond, en wie hem
 * verzet legt elke tv in de zaal stil tot het nieuwe adres er staat.
 */
create or replace function public.club_reset_screen_key(p_club_id uuid)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_key text;
begin
  if not public.is_service_context()
     and not public.has_club_role(p_club_id, array['owner','admin']::club_role[]) then
    raise exception 'Geen rechten' using errcode = 'insufficient_privilege';
  end if;

  v_key := public.new_screen_key();
  update clubs set screen_key = v_key where id = p_club_id;
  return v_key;
end;
$$;

comment on function public.club_reset_screen_key(uuid) is
  'Geeft de club een nieuwe schermsleutel en geeft hem terug. Alleen owner en admin; elke tv in de zaal moet daarna het nieuwe adres krijgen.';

-- ---------------------------------------------------------------------------
-- 2. Wat er op het scherm komt
-- ---------------------------------------------------------------------------

/**
 * De klokstand van de avond die nu bezig is bij deze club.
 *
 * Eén rij of geen rij. Geen rij betekent: verkeerde sleutel, club bestaat
 * niet, of er is vanavond niets te zien — en dat verschil hoort de tv niet
 * te weten. Het scherm toont dan de naam van de club en verder niets, en
 * blijft gewoon om de tien seconden opnieuw kijken. Zo mag hij de hele dag
 * aanstaan en springt hij vanzelf aan zodra de floor het tornooi start.
 *
 * **Welke avond "nu bezig" is.** Eerst een lopende avond. Is die er niet, dan
 * de eerstvolgende geplande van vandaag — dan staat de klok al klaar terwijl
 * de zaal volloopt, met de startstapel en de eerste blinds erop. Alles wat
 * verder in de toekomst ligt niet: een scherm dat woensdag al de avond van
 * zondag toont, is een scherm waar niemand meer naar kijkt.
 *
 * De bedragen die hier uitkomen zijn dezelfde als op het zaalscherm van de
 * app: prijzenpot uit het geldregister, chips uit `chips_in_play`. Namen van
 * spelers staan er niet bij. Een klok aan de muur is geen deelnemerslijst.
 */
create or replace function public.club_screen_board(
  p_club_slug text,
  p_key       text
)
returns table (
  club_name        text,
  primary_color    text,
  tournament_id    uuid,
  name             text,
  status           text,
  clock            text,
  level_idx        int,
  level_started_at timestamptz,
  level_elapsed_ms bigint,
  scheduled_at     timestamptz,
  starting_stack   int,
  late_reg_level   int,
  entries          int,
  players_left     int,
  rebuys           int,
  addons           int,
  prize_pool_cents int,
  chips_in_play    int,
  currency         char(3),
  server_now       timestamptz
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with c as (
    select * from clubs
    where slug = p_club_slug
      and is_active
      -- Geen sleutel ingesteld betekent dicht, niet open voor iedereen.
      and screen_key is not null
      and screen_key = p_key
  ),
  t as (
    select t.*
    from tournaments t
    join c on c.id = t.club_id
    where t.status = 'running'
       or (t.status = 'scheduled'
           and (t.scheduled_at at time zone c.timezone)::date
               = (now() at time zone c.timezone)::date)
    -- Een lopende avond gaat voor op een geplande.
    order by (t.status = 'running') desc, t.scheduled_at
    limit 1
  )
  select
    c.name,
    c.primary_color,
    t.id,
    t.name,
    t.status::text,
    t.clock::text,
    t.level_idx,
    t.level_started_at,
    t.level_elapsed_ms,
    t.scheduled_at,
    t.starting_stack,
    t.late_reg_level,
    (select count(*)::int from tournament_players tp
      where tp.tournament_id = t.id),
    (select count(*)::int from tournament_players tp
      where tp.tournament_id = t.id and tp.status in ('active', 'registered')),
    (select count(*)::int from buyins b
      where b.tournament_id = t.id and not b.is_void and b.kind in ('rebuy', 'reentry')),
    (select count(*)::int from buyins b
      where b.tournament_id = t.id and not b.is_void and b.kind = 'addon'),
    (select coalesce(sum(b.amount_cents), 0)::int from buyins b
      where b.tournament_id = t.id and not b.is_void),
    (select coalesce(sum(b.chips_delta), 0)::int from buyins b
      where b.tournament_id = t.id and not b.is_void),
    c.currency,
    now()
  from t cross join c;
$$;

comment on function public.club_screen_board(text, text) is
  'De klokstand van de avond die nu bezig is bij deze club, voor een zaalscherm met de schermsleutel. Geen namen, geen deelnemerslijst.';

/**
 * De blindstructuur van diezelfde avond.
 *
 * Apart van het bord hierboven omdat ze zelden verandert: het scherm haalt
 * de levels één keer op en daarna alleen nog de stand. Scheelt elke tien
 * seconden een lijst van twintig rijen over de lijn naar een tv die het toch
 * al niet breed heeft.
 */
create or replace function public.club_screen_levels(
  p_club_slug text,
  p_key       text
)
returns table (
  idx         int,
  is_break    boolean,
  label       text,
  small_blind int,
  big_blind   int,
  ante        int,
  duration_s  int
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select l.idx, l.is_break, l.label, l.small_blind, l.big_blind, l.ante, l.duration_s
  from blind_levels l
  where l.structure_id = (
    select t.structure_id
    from public.club_screen_board(p_club_slug, p_key) b
    join tournaments t on t.id = b.tournament_id
  )
  order by l.idx;
$$;

comment on function public.club_screen_levels(text, text) is
  'De blindstructuur van de avond die het zaalscherm toont.';

-- ---------------------------------------------------------------------------
-- 3. Rechten
-- ---------------------------------------------------------------------------
-- De twee schermfuncties staan open voor bezoekers zonder account — dat is de
-- hele bedoeling. Ze geven niets prijs zonder de sleutel, en mét de sleutel
-- geven ze precies wat er in de zaal op de muur hangt.
--
-- Eerst weg bij PUBLIC en dan gericht teruggeven, om dezelfde reden als in
-- 0034: PostgreSQL geeft EXECUTE automatisch aan PUBLIC, en een `revoke ...
-- from anon` alleen verandert dan niets.

do $$
declare
  fn text;
  r  text;
begin
  foreach fn in array array[
    'public.club_screen_board(text, text)',
    'public.club_screen_levels(text, text)'
  ] loop
    execute format('revoke execute on function %s from public', fn);
    foreach r in array array['anon', 'authenticated', 'service_role'] loop
      if exists (select 1 from pg_roles where rolname = r) then
        execute format('grant execute on function %s to %I', fn, r);
      end if;
    end loop;
  end loop;

  -- De sleutel verzetten is géén handeling voor een bezoeker.
  execute 'revoke execute on function public.club_reset_screen_key(uuid) from public';
  foreach r in array array['authenticated', 'service_role'] loop
    if exists (select 1 from pg_roles where rolname = r) then
      execute format('grant execute on function public.club_reset_screen_key(uuid) to %I', r);
    end if;
  end loop;
end $$;
