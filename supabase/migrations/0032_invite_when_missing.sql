-- Pokerleague — een uitnodiging hoort bij het lidmaatschap, niet bij het profiel
--
-- Het gat, in één zin: `floor_add_entry` zette alleen een uitnodiging klaar
-- wanneer het *spelersprofiel* nieuw was. Maar een uitnodiging gaat niet over
-- het profiel, ze gaat over deze club die deze persoon vraagt zijn account af
-- te maken. Dat zijn twee verschillende dingen, en overal waar ze uit elkaar
-- lopen viel er iemand tussen:
--
--   * Iemand speelt al bij club A en komt voor het eerst bij club B. Zijn
--     profiel bestaat, dus club B zet niets klaar. Heeft hij bij A nooit op
--     zijn uitnodiging geklikt, dan krijgt hij nu van niemand meer iets. Hoe
--     meer clubs op het platform, hoe vaker dit gebeurt — precies omgekeerd
--     aan wat je wil.
--   * Een club maakt zijn ledenbestand leeg en begint opnieuw. De profielen
--     die elders nog gebruikt worden blijven staan, dus bij het opnieuw
--     intikken komt er geen uitnodiging meer.
--   * De uitnodiging verliep na dertig dagen. Er komt nooit een nieuwe, ook
--     al staat die persoon elke week aan tafel.
--
-- De regel hoort te zijn wat je zou zeggen als je het uitlegt: *heeft deze
-- persoon een mailadres, nog geen account, en van deze club nog geen
-- openstaande uitnodiging — dan zetten we er een klaar.* Niets over of het
-- profiel nieuw is.
--
-- Het omgekeerde is even belangrijk. Twee keer dezelfde mail sturen is erger
-- dan geen mail: dan is het niet meer "je club vraagt iets" maar "die site
-- blijft maar mailen". Vandaar dat de functie hieronder eerst kijkt en pas
-- daarna schrijft, en dat een reeds verstuurde uitnodiging die nog geldig is
-- gewoon blijft staan.

-- ---------------------------------------------------------------------------
-- 1. Eén plek waar beslist wordt of er een uitnodiging bij moet
-- ---------------------------------------------------------------------------

create or replace function public.queue_invite(
  p_club_id   uuid,
  p_player_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_email text;
  v_acct  uuid;
  v_id    uuid;
begin
  select lower(trim(p.email)), p.auth_user_id
  into v_email, v_acct
  from players p
  where p.id = p_player_id and p.merged_into_id is null;

  -- Geen adres om naartoe te sturen, of hij heeft zijn account al.
  if v_email is null or v_email = '' or v_acct is not null then
    return null;
  end if;

  -- Staat er al iets open dat nog geldig is, dan is dat genoeg. Ook als het
  -- al verstuurd is: dan ligt de mail in zijn bus en is een tweede geen
  -- herinnering maar overlast.
  if exists (
    select 1 from player_invites i
    where i.club_id = p_club_id
      and i.player_id = p_player_id
      and i.accepted_at is null
      and i.expires_at > now()
      and i.attempts < 3
  ) then
    return null;
  end if;

  insert into player_invites (club_id, player_id, email, token, expires_at)
  values (p_club_id, p_player_id, v_email, public.new_invite_token(),
          now() + interval '30 days')
  returning id into v_id;

  return v_id;
end;
$$;

comment on function public.queue_invite(uuid, uuid) is
  'Zet een uitnodiging klaar voor deze speler bij deze club, tenzij dat niet hoort: geen mailadres, al een account, of er staat er al een open die nog geldig is. Bewust idempotent — hem tienmaal aanroepen levert één uitnodiging op.';

-- ---------------------------------------------------------------------------
-- 2. De deur roept hem aan, voor iedereen
-- ---------------------------------------------------------------------------
-- De rest van floor_add_entry blijft ongewijzigd. De insert van de
-- uitnodiging verhuist uit de "nieuw profiel"-tak naar één aanroep verderop,
-- op de plek waar vaststaat wie er aan tafel komt — ongeacht via welke weg.

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

  -- En hier de uitnodiging, buiten elke tak. Wie aan tafel komt, een adres
  -- heeft en nog geen account, hoort er een te krijgen — of zijn profiel nu
  -- vanavond ontstond of vijf jaar geleden bij een andere club. De functie
  -- beslist zelf of het nodig is.
  perform public.queue_invite(t.club_id, v_player);

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

-- ---------------------------------------------------------------------------
-- 3. Iedereen die er nu al tussen viel
-- ---------------------------------------------------------------------------
-- Elk clublid met een mailadres en zonder account krijgt alsnog zijn
-- uitnodiging in de wachtrij. `queue_invite` slaat over wie er al een heeft,
-- dus dit mag zonder gevaar twee keer draaien.

do $$
declare
  r record;
  v_n int := 0;
begin
  for r in
    select cp.club_id, cp.player_id
    from club_players cp
    join players p on p.id = cp.player_id
    where p.auth_user_id is null
      and p.email is not null
      and p.merged_into_id is null
  loop
    if public.queue_invite(r.club_id, r.player_id) is not null then
      v_n := v_n + 1;
    end if;
  end loop;

  raise notice 'Uitnodigingen alsnog in de wachtrij gezet: %', v_n;
end $$;

-- ---------------------------------------------------------------------------
-- 4. Rechten
-- ---------------------------------------------------------------------------
-- `queue_invite` wordt alleen van binnenuit aangeroepen. Geen grant: dan kan
-- niemand hem los gebruiken om ongevraagd post te laten vertrekken.

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function public.floor_add_entry(uuid, uuid, text, text, text, text) to authenticated;
  end if;
end $$;
