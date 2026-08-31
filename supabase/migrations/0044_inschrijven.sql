-- Pokerleague — vooraf inschrijven voor een avond
--
-- Een club die opent weet niet hoeveel volk er komt. Vijftien of vijftig
-- scheelt tafels, stoelen, kaartdekken, personeel achter de toog en hoeveel
-- chips er geteld moeten worden. Tot nu was het antwoord op die vraag "we
-- zien wel", en dat is precies waar een avond op stukloopt.
--
-- Dit maakt van die vraag een teller.
--
-- **Inschrijven kan zonder account.** Dat is de belangrijkste keuze in dit
-- bestand en ze gaat tegen de rest van het platform in, waar bijna alles een
-- aanmelding vraagt. De reden is de trechter: elke stap tussen "ik kom" en
-- "ingeschreven" kost mensen. Iemand die een affiche ziet, wil op één knop
-- drukken — geen wachtwoord verzinnen, geen bevestigingsmail afwachten in een
-- zaal zonder bereik. Vier velden, klaar. Zijn plaats staat vast en de club
-- weet het aantal, ook als die persoon nooit een account maakt.
--
-- Wat hij daarna krijgt is een uitnodiging om zijn profiel op te eisen, via
-- precies dezelfde weg als iemand die door de floor aan de deur wordt
-- ingeschreven. Doet hij het niet, dan maakt de floor er zondag alsnog een lid
-- van. Er gaat dus niets verloren.
--
-- **Waarom dat verantwoord is.** De functie hieronder is `security definer` en
-- staat open voor iedereen, en dat is normaal gezien een reden om nerveus te
-- worden. Ze doet daarom exact één ding: een naam, een adres en een
-- geboortedatum omzetten in een inschrijving voor één avond die openstaat.
-- Ze leest niets terug, ze raakt geen andere club aan, ze geeft geen rechten,
-- en ze weigert wie te jong is. Het ergste dat iemand met kwade wil kan doen
-- is de lijst vervuilen met verzonnen namen — vervelend, zichtbaar voor de
-- floor, en met een bovengrens.

-- ---------------------------------------------------------------------------
-- 1. Wat een avond aanbiedt aan wie vooraf inschrijft
-- ---------------------------------------------------------------------------
-- Extra chips, en die staan per tornooi. Niet als vaste instelling van de
-- club: dit is een middel voor een openingsavond of een drukke maand, geen
-- eigenschap van de club. Nul betekent geen bonus, en dan verdwijnt hij ook
-- van de inschrijfpagina in plaats van als "+0" te blijven staan.

alter table tournaments
  add column if not exists prereg_bonus_stack int not null default 0;

comment on column tournaments.prereg_bonus_stack is
  'Extra chips aan de deur voor wie vooraf inschreef. Wordt automatisch bij de startstapel geteld; 0 = geen bonus.';

/**
 * De bonus wordt gegeven op het moment dat iemand aan tafel komt.
 *
 * Als trigger en niet in `floor_add_entry`, om twee redenen. Die functie is
 * lang en wordt bij elke inschrijving aan de deur gedraaid; er een regel bij
 * schrijven betekent haar helemaal opnieuw definiëren, en dat is precies hoe
 * je een subtiel verschil introduceert dat niemand terugvindt. En zo geldt de
 * bonus ook als een tweede weg naar de tafel ooit bestaat.
 *
 * `before insert`, dus het staat in de rij zelf. Een `update` erna zou langs
 * `guard_player_chip_update` moeten, en die bewaakt terecht dat niemand zijn
 * eigen stapel bijstelt.
 */
create or replace function public.apply_prereg_bonus()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_bonus int;
begin
  select t.prereg_bonus_stack into v_bonus
  from tournaments t where t.id = new.tournament_id;

  if coalesce(v_bonus, 0) = 0 or new.chip_count is null then
    return new;
  end if;

  -- Alleen wie er op dit moment nog als ingeschreven staat. `floor_add_entry`
  -- zet de inschrijving pas ná deze insert op ingetrokken, dus hier is ze nog
  -- open — en wie zich nooit inschreef, krijgt niets.
  if exists (
    select 1 from tournament_registrations r
    where r.tournament_id = new.tournament_id
      and r.player_id = new.player_id
      and r.cancelled_at is null
  ) then
    new.chip_count := new.chip_count + v_bonus;
  end if;

  return new;
end;
$$;

drop trigger if exists tournament_players_prereg_bonus on tournament_players;
create trigger tournament_players_prereg_bonus
  before insert on tournament_players
  for each row execute function public.apply_prereg_bonus();

-- ---------------------------------------------------------------------------
-- 2. Wat er op de inschrijfpagina staat
-- ---------------------------------------------------------------------------
-- Leesbaar voor iedereen, ook zonder account — anders kan de affiche nergens
-- naartoe wijzen. Wat hier uitkomt staat sowieso op een affiche aan de deur:
-- welke avond, hoe laat, wat het kost, waar. Geen namen, geen deelnemerslijst,
-- geen bedragen die al binnen zijn.

drop function if exists public.tournament_signup_card(text, uuid);

create or replace function public.tournament_signup_card(
  p_club_slug     text,
  p_tournament_id uuid default null
)
returns table (
  tournament_id  uuid,
  name           text,
  scheduled_at   timestamptz,
  status         text,
  buyin_cents    int,
  fee_cents      int,
  starting_stack int,
  bonus_stack    int,
  registered     int,
  is_open        boolean,
  club_slug      text,
  club_name      text,
  city           text,
  address_line   text,
  maps_url       text,
  logo_url       text,
  primary_color  text,
  currency       char(3),
  timezone       text,
  locale         text
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with c as (
    select * from clubs where slug = p_club_slug and is_active
  ),
  t as (
    select t.*
    from tournaments t
    join c on c.id = t.club_id
    where (p_tournament_id is null or t.id = p_tournament_id)
      and t.status = 'scheduled'
      -- Zonder id: de eerstvolgende. Zo kan er één kort adres op de affiche
      -- staan dat volgende maand vanzelf naar de volgende avond wijst.
      and (p_tournament_id is not null or t.scheduled_at > now())
    order by t.scheduled_at
    limit 1
  )
  select
    t.id, t.name, t.scheduled_at, t.status::text,
    t.buyin_cents, t.fee_cents, t.starting_stack, t.prereg_bonus_stack,
    (select count(*)::int from tournament_registrations r
      where r.tournament_id = t.id and r.cancelled_at is null),
    -- Open tot het tornooi begint. Daarna is inschrijven zinloos: dan sta je
    -- aan de deur en doet de floor het.
    (t.status = 'scheduled' and t.scheduled_at > now()),
    c.slug, c.name, c.city, c.address_line, c.maps_url, c.logo_url,
    c.primary_color, c.currency, c.timezone, c.locale
  from t cross join c;
$$;

comment on function public.tournament_signup_card(text, uuid) is
  'De gegevens van één aankomende avond voor de publieke inschrijfpagina. Zonder tornooi-id: de eerstvolgende geplande avond van de club.';

-- ---------------------------------------------------------------------------
-- 3. Inschrijven
-- ---------------------------------------------------------------------------

/**
 * Zet iemand op de lijst voor een avond.
 *
 * Antwoorden, en ze zijn allemaal bedoeld om op het scherm te tonen:
 *
 *   'ok'         — ingeschreven
 *   'already'    — dit adres stond er al op; geen fout, gewoon geruststellen
 *   'closed'     — de avond is begonnen, afgelast of bestaat niet meer
 *   'too_young'  — jonger dan de club toelaat
 *   'bad_email'  — het adres kan niet kloppen
 *   'bad_name'   — geen naam ingevuld
 *   'full'       — de bovengrens is bereikt (zie hieronder)
 *
 * Een fout gooien zou hier verkeerd zijn: dit is een formulier voor iemand die
 * op een affiche een QR-code scande, en die verdient een zin en geen
 * foutmelding uit de database.
 */
create or replace function public.rsvp_for_tournament(
  p_tournament_id uuid,
  p_first_name    text,
  p_last_name     text,
  p_email         text,
  p_birthdate     date
)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  -- Een noodrem, geen zaalcapaciteit. Wie er honderden verzint, loopt hier
  -- tegenaan voordat de tabel vol staat.
  c_max_rsvp constant int := 500;

  t          tournaments;
  v_email    text := lower(nullif(trim(p_email), ''));
  v_first    text := nullif(trim(p_first_name), '');
  v_last     text := nullif(trim(p_last_name), '');
  v_naam     text;
  v_min_age  int;
  v_player   uuid;
  v_n        int;
begin
  select * into t from tournaments where id = p_tournament_id;
  if not found or t.status <> 'scheduled' or t.scheduled_at <= now() then
    return 'closed';
  end if;

  if v_first is null and v_last is null then
    return 'bad_name';
  end if;
  v_naam := trim(coalesce(v_first, '') || ' ' || coalesce(v_last, ''));

  if v_email is null
     or v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[a-z]{2,}$' then
    return 'bad_email';
  end if;

  -- Leeftijd. Dezelfde grens als aan de deur, en om dezelfde reden: poker is
  -- 18+ in België en dat controleer je vóór iemand op de lijst staat, niet
  -- op de avond zelf wanneer hij er al is.
  v_min_age := coalesce((select (c.compliance ->> 'min_age')::int
                         from clubs c where c.id = t.club_id), 18);
  if p_birthdate is null
     or public.age_on(p_birthdate, public.club_today(t.club_id)) < v_min_age then
    return 'too_young';
  end if;

  select count(*) into v_n
  from tournament_registrations r
  where r.tournament_id = t.id and r.cancelled_at is null;
  if v_n >= c_max_rsvp then
    return 'full';
  end if;

  -- Bestaat deze persoon al ergens op het platform, dan pikken we hém op.
  -- Hetzelfde principe als aan de deur: één mens, één profiel, over alle
  -- clubs heen.
  select id into v_player
  from players
  where lower(email) = v_email and merged_into_id is null;

  if v_player is null then
    insert into players (display_name, first_name, last_name, email, birthdate,
                         link_state, locale)
    values (v_naam, v_first, v_last, v_email, p_birthdate, 'invited',
            coalesce((select c.locale from clubs c where c.id = t.club_id), 'nl'))
    returning id into v_player;
  else
    -- Wat we niet weten vullen we aan; wat er staat laten we staan. Iemand
    -- die zijn profiel zelf beheert, hoort niet overschreven te worden door
    -- een formulier.
    update players
    set first_name = coalesce(first_name, v_first),
        last_name  = coalesce(last_name,  v_last),
        birthdate  = coalesce(birthdate,  p_birthdate)
    where id = v_player;
  end if;

  insert into club_players (club_id, player_id, joined_on)
  values (t.club_id, v_player, current_date)
  on conflict (club_id, player_id) do nothing;

  -- De uitnodiging om zijn profiel op te eisen. Beslist zelf of het nodig is:
  -- wie al een account heeft krijgt niets.
  perform public.queue_invite(t.club_id, v_player);

  -- Stond hij er al op, dan is dat geen fout maar een geruststelling. Deze
  -- vraag komt vóór de insert en niet erna: binnen één transactie staat
  -- `now()` stil, dus "is deze rij net gemaakt of stond ze er al" is achteraf
  -- niet meer aan de tijd af te lezen.
  if exists (
    select 1 from tournament_registrations r
    where r.tournament_id = t.id and r.player_id = v_player
      and r.cancelled_at is null
  ) then
    return 'already';
  end if;

  -- `do update` en niet `do nothing`: wie zich eerder uitschreef en nu terug
  -- inschrijft, hoort gewoon weer op de lijst te staan.
  insert into tournament_registrations (club_id, tournament_id, player_id)
  values (t.club_id, t.id, v_player)
  on conflict (tournament_id, player_id) do update
    set cancelled_at = null;

  return 'ok';
end;
$$;

comment on function public.rsvp_for_tournament(uuid, text, text, text, date) is
  'Schrijft iemand vooraf in voor een avond, zonder dat hij een account nodig heeft. Maakt of hergebruikt het spelersprofiel, koppelt aan de club en zet een uitnodiging klaar.';

-- ---------------------------------------------------------------------------
-- 4. Wat de floor ziet
-- ---------------------------------------------------------------------------

drop function if exists public.tournament_rsvp_list(uuid);

create or replace function public.tournament_rsvp_list(p_tournament_id uuid)
returns table (
  player_id    uuid,
  display_name text,
  email        text,
  has_account  boolean,
  at_table     boolean,
  signed_up_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_club uuid;
begin
  select club_id into v_club from tournaments where id = p_tournament_id;
  if v_club is null then
    return;
  end if;

  if not public.is_service_context()
     and not public.has_club_role(v_club, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten op de inschrijvingen van deze club'
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select
    p.id,
    p.display_name,
    p.email,
    p.auth_user_id is not null,
    exists (select 1 from tournament_players tp
            where tp.tournament_id = p_tournament_id and tp.player_id = p.id),
    r.created_at
  from tournament_registrations r
  join players p on p.id = r.player_id
  where r.tournament_id = p_tournament_id and r.cancelled_at is null
  order by r.created_at;
end;
$$;

comment on function public.tournament_rsvp_list(uuid) is
  'Wie zich vooraf inschreef voor deze avond, en of hij al aan tafel zit.';

-- ---------------------------------------------------------------------------
-- 5. Een tijdzonefout in de omzetberekening
-- ---------------------------------------------------------------------------
-- Niet van dit onderwerp, wel gevonden terwijl dit erbij kwam, en het hoort
-- niet te blijven staan.
--
-- `billing_months` rekende met `current_date`, en dat is de datum van de
-- server — UTC. De maandreeks op het beheerdashboard bucket wél in Brussel.
-- Tussen middernacht en twee uur 's nachts op de eerste van de maand zijn dat
-- twee verschillende maanden, en dan telt het ene cijfer een maand meer dan
-- het andere. Twee getallen op hetzelfde scherm die elkaar tegenspreken, twee
-- uur per maand.
--
-- Het hele product is Belgisch en elke club staat op Europe/Brussels, dus
-- rekent dit voortaan ook in Brussel. `immutable` kan dan niet meer — een
-- functie die `now()` leest is per definitie `stable`.

drop function if exists public.billing_months(date, date);

create or replace function public.billing_months(p_start date, p_end date)
returns int
language sql
stable
as $$
  select greatest(
    0,
    (date_part('year',  age(date_trunc('month',
        coalesce(p_end, (now() at time zone 'Europe/Brussels')::date))::date,
                            date_trunc('month', p_start)::date)) * 12
   + date_part('month', age(date_trunc('month',
        coalesce(p_end, (now() at time zone 'Europe/Brussels')::date))::date,
                            date_trunc('month', p_start)::date)))::int + 1
  );
$$;

comment on function public.billing_months(date, date) is
  'Hoeveel maanden er tot vandaag gefactureerd zijn, gerekend in Brusselse tijd. De maand van instap telt mee.';

-- ---------------------------------------------------------------------------
-- 6. Rechten
-- ---------------------------------------------------------------------------
-- De eerste twee staan open voor bezoekers zonder account — dat is de hele
-- bedoeling van een affiche met een QR-code. De derde niet.

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    revoke all on function public.tournament_signup_card(text, uuid) from public;
    revoke all on function public.rsvp_for_tournament(uuid, text, text, text, date) from public;
    revoke all on function public.tournament_rsvp_list(uuid) from public;

    grant execute on function public.tournament_signup_card(text, uuid)
      to anon, authenticated, service_role;
    grant execute on function public.rsvp_for_tournament(uuid, text, text, text, date)
      to anon, authenticated, service_role;
    grant execute on function public.tournament_rsvp_list(uuid)
      to authenticated, service_role;
  end if;
end $$;
