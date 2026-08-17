-- Pokerleague — in welke taal krijgt een speler zijn post?
--
-- `players.locale` bestaat sinds het begin en stond bij iedereen op 'nl',
-- want niemand vulde het ooit in. Dat viel niet op zolang er niets verstuurd
-- werd. Nu er wel mail vertrekt, valt het onmiddellijk op: een Waal die aan de
-- deur van een Vlaamse club inschrijft krijgt een Nederlandse uitnodiging.
--
-- Er zijn drie momenten waarop we die taal te weten kunnen komen, en alle
-- drie worden ze hier gebruikt:
--
--   1. Aan de deur. De floor staat met die persoon te praten, dus hij weet het
--      op dat moment beter dan wie ook. Vandaar een keuze in het toevoegscherm,
--      met de taal van de club als vertrekpunt — dat is bij de overgrote
--      meerderheid juist, en dan is het één blik in plaats van één handeling.
--   2. Bij registratie. Wie zich op een Franstalige pagina inschrijft, leest
--      liever Frans. Dat hoeven we niet te vragen; we weten het al.
--   3. Achteraf, door de speler zelf. Dat is de enige van de drie die het
--      zeker weet, en dus degene die wint.
--
-- Die volgorde zit in de regels hieronder verwerkt: de club mag de taal zetten
-- en bijstellen zolang het profiel van de club is — een schaduwprofiel dat
-- niemand opeiste. Zodra iemand zijn account heeft, is het zijn taal en raakt
-- de club er niet meer aan.

-- ---------------------------------------------------------------------------
-- 1. Alleen talen die we ook echt kunnen
-- ---------------------------------------------------------------------------
-- Zonder deze controle staat er ooit 'NL' of 'nl-BE' of 'vlaams' in, en dan
-- valt de mailer stil terug op Nederlands zonder dat iemand begrijpt waarom.

create or replace function public.norm_locale(p text)
returns text
language sql
immutable
as $$
  select case lower(left(coalesce(trim(p), ''), 2))
           when 'nl' then 'nl'
           when 'fr' then 'fr'
           when 'en' then 'en'
           else null
         end
$$;

comment on function public.norm_locale(text) is
  'Herleidt een taalaanduiding tot nl, fr of en, of null als het geen van drie is. Bewust op de eerste twee tekens: nl-BE en fr_BE komen allebei voor en betekenen hetzelfde voor ons.';

-- ---------------------------------------------------------------------------
-- 2. De floor geeft de taal mee
-- ---------------------------------------------------------------------------
-- De oude versie moet eerst weg. Twee overloads waarvan de ene vijf en de
-- andere zes parameters met standaardwaarden heeft, maakt elke aanroep met
-- minder argumenten dubbelzinnig — dan weigert Postgres gewoon. Dezelfde
-- valkuil als in 0010.

drop function if exists public.floor_add_entry(uuid, uuid, text, text, text);

create or replace function public.floor_add_entry(
  p_tournament_id   uuid,
  p_player_id       uuid    default null,
  p_new_name        text    default null,
  p_email           text    default null,
  p_no_email_reason text    default null,
  p_locale          text    default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  t        tournaments%rowtype;
  v_player uuid;
  v_tp     uuid;
  v_email  text := nullif(lower(trim(coalesce(p_email, ''))), '');
  v_reason text := nullif(trim(coalesce(p_no_email_reason, '')), '');
  v_name   text := nullif(trim(coalesce(p_new_name, '')), '');
  v_locale text := public.norm_locale(p_locale);
begin
  select * into t from tournaments where id = p_tournament_id;
  if not found then
    raise exception 'Tornooi bestaat niet';
  end if;

  if not public.is_service_context()
     and not public.has_club_role(t.club_id, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten om spelers toe te voegen'
      using errcode = 'insufficient_privilege';
  end if;

  if t.status in ('finished', 'cancelled') then
    raise exception 'Dit tornooi is afgelopen' using errcode = 'check_violation';
  end if;

  if p_player_id is not null then
    -- Bestaand lid: het mailadres staat al in zijn profiel, daar raken we
    -- hier niet aan.
    v_player := public.resolve_player(p_player_id);
  else
    if v_name is null then
      raise exception 'Geef een naam op' using errcode = 'check_violation';
    end if;

    -- Zonder mailadres én zonder reden gaat het niet door. Dat is de hele
    -- afspraak: overslaan mag, maar niet stilzwijgend.
    if v_email is null and v_reason is null then
      raise exception 'Geef een mailadres op, of een reden waarom er geen is'
        using errcode = 'check_violation';
    end if;

    if v_email is not null then
      -- Losse controle, bewust ruim: een adres afkeuren dat wél bestaat is
      -- erger dan er eentje doorlaten dat straks bounct.
      if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[a-z]{2,}$' then
        raise exception 'Dat lijkt geen geldig mailadres' using errcode = 'check_violation';
      end if;

      -- Hier gebeurt het echte werk: bestaat deze speler al ergens op het
      -- platform, dan pikken we hém op in plaats van een tweede profiel te
      -- maken. Ook als hij bij een andere club zit — dat is precies waarom
      -- de spelers platformbreed staan en niet per club.
      select id into v_player
      from players
      where lower(email) = v_email and merged_into_id is null;
    end if;

    if v_player is null then
      insert into players (display_name, email, link_state, no_email_reason, locale)
      values (
        v_name,
        v_email,
        (case when v_email is null then 'shadow' else 'invited' end)::player_link_state,
        case when v_email is null then v_reason end,
        -- Niets opgegeven? Dan de taal van de club. Dat is bij de overgrote
        -- meerderheid juist, en beter dan de kolomstandaard 'nl' — die zou
        -- bij een Waalse club systematisch verkeerd zijn.
        coalesce(v_locale, (select c.locale from clubs c where c.id = t.club_id), 'nl')
      )
      returning id into v_player;

      -- Uitnodiging in de wachtrij. Hij vult zelf gebruikersnaam,
      -- geboortedatum, gemeente en zijn toestemming voor de klassementen aan.
      if v_email is not null then
        insert into player_invites (club_id, player_id, email, token, expires_at)
        values (t.club_id, v_player, v_email, public.new_invite_token(),
                now() + interval '30 days');
      end if;
    end if;
  end if;

  -- Bijstellen mag zolang het profiel niet van de speler zelf is. Tikte de
  -- floor vorige maand Nederlands in voor iemand die Frans spreekt, dan is dit
  -- het moment waarop dat rechtgezet wordt — de floor staat nu met hem te
  -- praten. Heeft die persoon intussen een account, dan is het zijn instelling
  -- en blijven we eraf.
  if v_locale is not null and v_player is not null then
    update players
    set locale = v_locale
    where id = v_player
      and auth_user_id is null
      and locale is distinct from v_locale;
  end if;

  insert into club_players (club_id, player_id, joined_on)
  values (t.club_id, v_player, current_date)
  on conflict (club_id, player_id) do nothing;

  -- Al ingeschreven? Dan niets dubbel boeken, gewoon teruggeven.
  select id into v_tp from tournament_players
  where tournament_id = p_tournament_id and player_id = v_player;

  if v_tp is not null then
    return v_tp;
  end if;

  insert into tournament_players (
    club_id, tournament_id, player_id, status, chip_count
  ) values (
    t.club_id, p_tournament_id, v_player, 'active', t.starting_stack
  )
  returning id into v_tp;

  insert into buyins (
    club_id, tournament_id, tournament_player_id, player_id,
    kind, amount_cents, fee_cents, bounty_cents, recorded_by
  ) values (
    t.club_id, p_tournament_id, v_tp, v_player,
    'buyin', t.buyin_cents, t.fee_cents,
    case when t.bounty_mode = 'none' then 0 else t.bounty_cents end,
    auth.uid()
  );

  -- Een inschrijving vooraf is nu een deelname geworden.
  update tournament_registrations
  set cancelled_at = coalesce(cancelled_at, now())
  where tournament_id = p_tournament_id and player_id = v_player and cancelled_at is null;

  return v_tp;
end;
$$;

comment on function public.floor_add_entry(uuid, uuid, text, text, text, text) is
  'Schrijft iemand in aan de deur. Maakt zo nodig het spelersprofiel aan, zet een uitnodiging klaar, koppelt aan de club en boekt de inkoop. De taal is optioneel en valt terug op die van de club; ze wordt alleen bijgewerkt zolang het profiel nog niemands account is.';

-- ---------------------------------------------------------------------------
-- 3. Wie zich registreert, doet dat in zijn eigen taal
-- ---------------------------------------------------------------------------
-- De taal van de pagina waarop iemand het formulier invult is een sterkere
-- aanwijzing dan wat de floor ooit gokte. Vandaar dat ze hier wint van een
-- bestaande waarde — maar alleen op het moment van opeisen, en alleen als ze
-- effectief meegegeven is.

create or replace function public.claim_my_player(
  p_first_name text default null,
  p_last_name  text default null,
  p_username   text default null,
  p_listing    boolean default null,
  p_locale     text default null
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

  -- Twee talen, met opzet uit elkaar gehouden.
  --
  -- `v_arg_locale` is wat de aanroeper nu meegeeft. `v_new_locale` mag daar
  -- de taal uit het token bij nemen — die zette het registratieformulier daar
  -- ooit in.
  --
  -- Dat onderscheid is nodig omdat de spelerspagina deze functie bij elk
  -- bezoek aanroept, zonder argumenten. Zou ook dan de taal uit het token
  -- gelden, dan draait die elke keer terug wat de speler intussen zelf
  -- instelde: hij zet zijn profiel op Frans, klikt naar zijn resultaten, en
  -- staat weer op Nederlands. De metadata telt dus alleen op het moment dat
  -- het profiel voor het eerst aan een account gekoppeld wordt; daarna is een
  -- expliciet argument de enige manier.
  v_arg_locale text := public.norm_locale(p_locale);
  v_new_locale text := coalesce(public.norm_locale(p_locale),
                                public.norm_locale(v_meta->>'locale'));
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
        locale       = coalesce(v_arg_locale, locale),
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
        locale         = coalesce(v_new_locale, locale),
        public_listing = v_list
    where id = v_id;
    return v_id;
  end if;

  insert into players (
    display_name, first_name, last_name, username, email,
    auth_user_id, link_state, public_listing, locale
  ) values (
    coalesce(v_full, split_part(v_email, '@', 1)),
    v_first, v_last, v_user, v_email, v_uid, 'claimed', v_list,
    coalesce(v_new_locale, 'nl')
  )
  returning id into v_id;

  return v_id;
end;
$$;

-- De oude vier-parameterversie zou naast deze blijven bestaan en elke aanroep
-- met minder dan vijf argumenten dubbelzinnig maken.
drop function if exists public.claim_my_player(text, text, text, boolean);

-- ---------------------------------------------------------------------------
-- 4. En de speler beslist zelf
-- ---------------------------------------------------------------------------
-- Hier hoeft niets te gebeuren, en dat is het vermelden waard. `locale` staat
-- gewoon op `players`, en `players_self_update` laat een speler zijn eigen rij
-- bijwerken zonder een lijst toegestane kolommen. Het scherm op /ik krijgt er
-- dus een keuzelijst bij en dat is genoeg — geen nieuwe policy, geen functie.
--
-- Wel even nagekeken dat er geen trigger tussen zit die kolommen afschermt:
-- `players_listing_consent` uit 0007 houdt alleen bij wanneer iemand zijn
-- toestemming voor publieke ranglijsten wijzigde, en raakt de rest niet aan.
comment on column players.locale is
  'De taal waarin deze speler post krijgt. Gezet door de floor aan de deur, of door de speler zelf bij registratie en op zijn profielpagina. Zolang het profiel niemands account is mag de club bijstellen; daarna is het van de speler.';

-- ---------------------------------------------------------------------------
-- 5. Rechten
-- ---------------------------------------------------------------------------

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function public.floor_add_entry(uuid, uuid, text, text, text, text) to authenticated;
    grant execute on function public.claim_my_player(text, text, text, boolean, text) to authenticated;
    grant execute on function public.norm_locale(text) to authenticated;
  end if;
  if exists (select 1 from pg_roles where rolname = 'anon') then
    grant execute on function public.norm_locale(text) to anon;
  end if;
end $$;
