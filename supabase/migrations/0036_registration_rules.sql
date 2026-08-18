-- Pokerleague — wat we bij registratie vragen, en waarom het hier afgedwongen wordt
--
-- Drie dingen komen erbij: een gebruikersnaam, een geboortedatum, en
-- toestemming om de cijfers te gebruiken. Alle drie worden ze hier bewaakt en
-- niet alleen in het formulier — een formulier is een suggestie, een
-- databaseregel is een afspraak.
--
-- **Leeftijd.** Poker is 18+ in België. Er stond al een controle op het moment
-- dat iemand aan tafel komt (`enforce_min_age`, migratie 0005), en die blijft:
-- daar hangt het gedoogbeleid van de club aan. Wat ontbrak is de grens één
-- laag hoger — je kan vandaag een account maken met eender welke
-- geboortedatum. Dat hoort niet te kunnen.
--
-- Wees wel eerlijk over wat dit is. Een zelf ingetikte datum bewijst niets. De
-- club controleert nog altijd een identiteitskaart aan de deur, en dat blijft
-- de echte controle. Wat deze regel doet is voorkomen dat wij een account
-- aanmaken voor iemand die zelf zegt dat hij vijftien is — dat is geen
-- verificatie maar het is wel het minimum.
--
-- **Toestemming.** Apart van `public_listing`, en dat onderscheid is de moeite.
-- `public_listing` gaat over of jouw naam in een openbare ranglijst mag staan.
-- Dit gaat over of je cijfers meetellen in de overzichten van je club en van
-- het platform. Twee verschillende vragen met twee verschillende antwoorden:
-- iemand kan best willen dat zijn club ziet hoeveel hij speelt zonder dat zijn
-- naam ergens publiek komt.

-- ---------------------------------------------------------------------------
-- 1. De toestemming
-- ---------------------------------------------------------------------------
-- Een tijdstip en geen vinkje. Bij toestemming is *wanneer* onderdeel van het
-- antwoord: je moet later kunnen aantonen dat ze gegeven is, en op welk moment
-- — anders is het geen toestemming maar een aanname.

alter table players
  add column if not exists stats_consent_at timestamptz;

comment on column players.stats_consent_at is
  'Wanneer deze speler toestemming gaf om zijn resultaten te laten meetellen in de overzichten van zijn clubs en van PokerLeague. Leeg = geen toestemming. Bewust een tijdstip: bij toestemming hoort te kloppen wanneer ze gegeven is. Staat los van public_listing, dat over publieke naamsvermelding gaat.';

-- ---------------------------------------------------------------------------
-- 2. Achttien
-- ---------------------------------------------------------------------------
-- Als trigger en niet als CHECK: een check-constraint mag geen `now()`
-- bevatten, want die moet bij elke herwaardering hetzelfde antwoord geven.
-- Leeftijd verandert nu net wél met de tijd.
--
-- Alleen voor profielen die aan een account hangen. Een schaduwprofiel dat de
-- floor aan de deur aanmaakt heeft vaak geen geboortedatum, en waar hij er wel
-- een heeft, doet `enforce_min_age` zijn werk bij het inschrijven.

create or replace function public.enforce_adult_account()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_age int;
begin
  if new.auth_user_id is null or new.birthdate is null then
    return new;
  end if;

  v_age := public.age_on(new.birthdate, current_date);

  if v_age < 18 then
    raise exception 'Je moet 18 jaar zijn om een account te maken.'
      using errcode = 'check_violation';
  end if;

  -- Een datum in de toekomst of uit de negentiende eeuw is geen leeftijd maar
  -- een typfout. Die tegenhouden scheelt later een onverklaarbaar profiel.
  if new.birthdate > current_date or v_age > 120 then
    raise exception 'Die geboortedatum klopt niet.'
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

drop trigger if exists players_adult_account on players;
create trigger players_adult_account
  before insert or update of birthdate, auth_user_id on players
  for each row execute function public.enforce_adult_account();

-- ---------------------------------------------------------------------------
-- 3. Is deze gebruikersnaam nog vrij?
-- ---------------------------------------------------------------------------
-- Zonder dit ziet iemand pas ná het invullen van het hele formulier dat zijn
-- naam bezet is, en dan is hij zijn wachtwoord kwijt en moet hij opnieuw.
--
-- Dat dit verklapt welke namen bestaan is inherent aan unieke gebruikersnamen:
-- wie het wil weten, probeert het gewoon bij het registreren. Vandaar dat de
-- functie alleen ja of nee teruggeeft en niets anders — geen speler, geen id,
-- geen aantal.

create or replace function public.username_available(p_username text)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    case
      when coalesce(trim(p_username), '') !~ '^[a-zA-Z0-9._-]{3,24}$' then false
      else not exists (
        select 1 from players
        where lower(username) = lower(trim(p_username))
          and merged_into_id is null
      )
    end
$$;

comment on function public.username_available(text) is
  'Geeft alleen waar of onwaar terug. Een gebruikersnaam die niet aan de vorm voldoet telt als niet beschikbaar, zodat het scherm één antwoord heeft in plaats van twee.';

-- ---------------------------------------------------------------------------
-- 4. Opeisen met de nieuwe velden erbij
-- ---------------------------------------------------------------------------
-- Zelfde opbouw als in 0030, met geboortedatum en toestemming erbij. Ze reizen
-- ook mee in de metadata van het token, want tussen het formulier en het
-- opeisen zit een bevestigingsmail — tegen die tijd is het formulier weg.

drop function if exists public.claim_my_player(text, text, text, boolean, text);

create or replace function public.claim_my_player(
  p_first_name text default null,
  p_last_name  text default null,
  p_username   text default null,
  p_listing    boolean default null,
  p_locale     text default null,
  p_birthdate  date default null,
  p_consent    boolean default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid    uuid  := auth.uid();
  v_email  text  := public.auth_email();
  v_meta   jsonb := public.auth_meta();
  v_id     uuid;
  v_first  text    := coalesce(nullif(trim(p_first_name), ''), nullif(trim(v_meta->>'first_name'), ''));
  v_last   text    := coalesce(nullif(trim(p_last_name),  ''), nullif(trim(v_meta->>'last_name'),  ''));
  v_user   text    := coalesce(nullif(trim(p_username),   ''), nullif(trim(v_meta->>'username'),   ''));
  v_list   boolean := coalesce(p_listing, (v_meta->>'public_listing')::boolean, false);
  v_full   text    := nullif(trim(coalesce(v_first, '') || ' ' || coalesce(v_last, '')), '');

  -- Zie 0030 voor waarom argument en metadata uit elkaar gehouden worden: de
  -- spelerspagina roept deze functie bij elk bezoek argumentloos aan, en dan
  -- mag de metadata niet terugdraaien wat iemand intussen zelf instelde.
  v_arg_locale text := public.norm_locale(p_locale);
  v_new_locale text := coalesce(public.norm_locale(p_locale),
                                public.norm_locale(v_meta->>'locale'));

  v_birth   date    := coalesce(p_birthdate, nullif(v_meta->>'birthdate', '')::date);
  v_consent boolean := coalesce(p_consent, (v_meta->>'stats_consent')::boolean, false);
  v_when    timestamptz := case when v_consent then now() else null end;
begin
  if v_uid is null then
    raise exception 'Niet aangemeld' using errcode = 'insufficient_privilege';
  end if;
  if v_email is null then
    raise exception 'Dit account heeft geen mailadres' using errcode = 'check_violation';
  end if;

  -- Vóór het schrijven, zodat de melding over de leeftijd gaat en niet over
  -- een trigger die halverwege afgaat.
  if v_birth is not null and public.age_on(v_birth, current_date) < 18 then
    raise exception 'Je moet 18 jaar zijn om een account te maken.'
      using errcode = 'check_violation';
  end if;

  select id into v_id
  from players
  where auth_user_id = v_uid and merged_into_id is null;

  if found then
    update players
    set first_name       = coalesce(first_name, v_first),
        last_name        = coalesce(last_name,  v_last),
        username         = coalesce(username,   v_user),
        locale           = coalesce(v_arg_locale, locale),
        birthdate        = coalesce(birthdate, v_birth),
        -- Toestemming intrekken doet hij op zijn profiel, niet hier: een
        -- argumentloze aanroep bij elk bezoek mag ze niet wissen.
        stats_consent_at = coalesce(stats_consent_at, v_when),
        display_name     = case
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
    set auth_user_id     = v_uid,
        link_state       = 'claimed',
        first_name       = coalesce(v_first, first_name),
        last_name        = coalesce(v_last,  last_name),
        username         = coalesce(username, v_user),
        display_name     = coalesce(v_full, display_name),
        locale           = coalesce(v_new_locale, locale),
        birthdate        = coalesce(v_birth, birthdate),
        stats_consent_at = coalesce(stats_consent_at, v_when),
        public_listing   = v_list
    where id = v_id;
    return v_id;
  end if;

  insert into players (
    display_name, first_name, last_name, username, email,
    auth_user_id, link_state, public_listing, locale, birthdate, stats_consent_at
  ) values (
    coalesce(v_full, v_user, split_part(v_email, '@', 1)),
    v_first, v_last, v_user, v_email, v_uid, 'claimed', v_list,
    coalesce(v_new_locale, 'nl'), v_birth, v_when
  )
  returning id into v_id;

  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. En het scherm moet weten wat er nog ontbreekt
-- ---------------------------------------------------------------------------
-- Bestaande accounts hebben geen geboortedatum en geen toestemming. Die vraagt
-- het welkomstscherm alsnog; daarvoor moet het weten wat er mist.

drop function if exists public.my_player();

create or replace function public.my_player()
returns table (
  id               uuid,
  display_name     text,
  first_name       text,
  last_name        text,
  username         text,
  email            text,
  locale           text,
  birthdate        date,
  stats_consent_at timestamptz,
  public_listing   boolean,
  public_profile   boolean,
  onboarded_at     timestamptz,
  clubs_count      int,
  results_count    int
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    p.id, p.display_name, p.first_name, p.last_name, p.username, p.email,
    p.locale, p.birthdate, p.stats_consent_at,
    p.public_listing, p.public_profile, p.onboarded_at,
    (select count(*)::int from club_players cp where cp.player_id = p.id),
    (select count(*)::int from tournament_results r where r.player_id = p.id)
  from players p
  where p.auth_user_id = auth.uid() and p.merged_into_id is null
$$;

-- ---------------------------------------------------------------------------
-- 6. Rechten
-- ---------------------------------------------------------------------------

do $$
declare r text;
begin
  foreach r in array array['anon', 'authenticated'] loop
    if exists (select 1 from pg_roles where rolname = r) then
      execute format('grant execute on function public.username_available(text) to %I', r);
    end if;
  end loop;

  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function public.claim_my_player(text, text, text, boolean, text, date, boolean)
      to authenticated;
    grant execute on function public.my_player() to authenticated;
  end if;
end $$;
