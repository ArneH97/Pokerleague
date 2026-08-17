-- Pokerleague — het mailadres als sleutel bij een nieuwe speler aan de deur
--
-- Waarom het mailadres en niet de naam: er zitten in België meer dan genoeg
-- mensen met dezelfde naam, en dezelfde man speelt volgend jaar misschien ook
-- bij een tweede club. Op naam matchen levert dan ofwel twee profielen voor
-- één speler, ofwel twee spelers samengeplakt tot één. Op het mailadres kan
-- geen van beide: er staat een unieke index op lower(email) over het hele
-- platform, niet per club.
--
-- Waarom er tóch een uitweg is: aan de deur staan er drie mensen tegelijk
-- iets te vragen. Wie een speler niet ingeschreven krijgt omdat die zijn
-- adres niet uit het hoofd kent, typt binnen de kortste keren jan@jan.be in.
-- Een vervuilde sleutel is erger dan een ontbrekende. Vandaar: verplicht,
-- tenzij de floor uitdrukkelijk zegt waarom niet — en dat leggen we vast.

-- ---------------------------------------------------------------------------
-- 1. Waarom er geen mailadres is
-- ---------------------------------------------------------------------------

alter table players
  add column if not exists no_email_reason text;

comment on column players.no_email_reason is
  'Ingevuld wanneer de floor een speler zonder mailadres toevoegde. Zo zie je achteraf wie je nog moet aanvullen én waarom het toen niet lukte.';

-- ---------------------------------------------------------------------------
-- 2. De uitnodiging komt in een wachtrij, ze vertrekt niet meteen
-- ---------------------------------------------------------------------------
-- Mail versturen vanuit deze functie zou betekenen dat de floor aan de deur
-- staat te wachten op een externe dienst. Dat mag nooit. Er komt een rij bij,
-- en iets anders leegt die rij.

alter table player_invites
  add column if not exists sent_at    timestamptz,
  add column if not exists last_error text;

comment on column player_invites.sent_at is
  'Leeg = staat nog in de wachtrij. De verzender vult dit in zodra de mail buiten is.';

create index if not exists player_invites_pending
  on player_invites (created_at) where sent_at is null and accepted_at is null;

-- Een token van 64 tekens, zonder pgcrypto: twee uuid''s aan elkaar volstaan
-- ruimschoots en gen_random_uuid() zit sinds PG13 in de kern.
create or replace function public.new_invite_token()
returns text
language sql
volatile
as $$
  select replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '')
$$;

-- ---------------------------------------------------------------------------
-- 3. Speler toevoegen, nu met mailadres
-- ---------------------------------------------------------------------------
-- De oude versie moet eerst weg. Twee functies met dezelfde naam waarvan de
-- ene drie en de andere vijf parameters met standaardwaarden heeft, maakt elke
-- aanroep met drie argumenten dubbelzinnig — Postgres weigert dan gewoon.

drop function if exists public.floor_add_entry(uuid, uuid, text);

create or replace function public.floor_add_entry(
  p_tournament_id   uuid,
  p_player_id       uuid    default null,
  p_new_name        text    default null,
  p_email           text    default null,
  p_no_email_reason text    default null
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
      insert into players (display_name, email, link_state, no_email_reason)
      values (
        v_name,
        v_email,
        (case when v_email is null then 'shadow' else 'invited' end)::player_link_state,
        case when v_email is null then v_reason end
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

-- ---------------------------------------------------------------------------
-- 4. Het mailadres achteraf alsnog invullen
-- ---------------------------------------------------------------------------
-- Wie aan de deur werd toegevoegd zonder adres, vul je later aan vanuit het
-- ledenbestand. Loopt via een functie en niet via een gewone update, omdat
-- er twee dingen tegelijk moeten gebeuren: het adres vastleggen én de
-- uitnodiging alsnog in de wachtrij zetten. En omdat het adres van iemand
-- anders kan blijken te zijn.

create or replace function public.set_player_email(
  p_player_id uuid,
  p_email     text,
  p_club_id   uuid
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_email    text := nullif(lower(trim(coalesce(p_email, ''))), '');
  v_existing uuid;
  v_player   uuid := public.resolve_player(p_player_id);
begin
  if not public.is_service_context()
     and not public.has_club_role(p_club_id, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten' using errcode = 'insufficient_privilege';
  end if;

  if v_email is null or v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[a-z]{2,}$' then
    raise exception 'Dat lijkt geen geldig mailadres' using errcode = 'check_violation';
  end if;

  -- Hoort dit adres al bij iemand anders, dan is dit dezelfde persoon en
  -- geven we die terug. Samenvoegen doen we hier niet automatisch: dat is
  -- een beslissing met gevolgen voor iemands historie.
  select id into v_existing from players
  where lower(email) = v_email and merged_into_id is null and id <> v_player;

  if v_existing is not null then
    return v_existing;
  end if;

  update players
  set email           = v_email,
      no_email_reason = null,
      link_state      = case when link_state = 'shadow' then 'invited' else link_state end
  where id = v_player;

  insert into player_invites (club_id, player_id, email, token, expires_at)
  values (p_club_id, v_player, v_email, public.new_invite_token(), now() + interval '30 days');

  return v_player;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Wie moet je nog aanvullen
-- ---------------------------------------------------------------------------

create or replace view public.club_players_without_email
with (security_invoker = true) as
select
  cp.club_id,
  p.id            as player_id,
  p.display_name,
  p.no_email_reason,
  cp.joined_on,
  (select count(*) from tournament_players tp
    where tp.player_id = p.id and tp.club_id = cp.club_id) as entries
from club_players cp
join players p on p.id = cp.player_id
where p.email is null
  and p.merged_into_id is null;

comment on view public.club_players_without_email is
  'Spelers die aan de deur werden toegevoegd zonder mailadres. security_invoker staat AAN: je ziet dus alleen de clubs waar je zelf rechten op hebt.';

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant select on public.club_players_without_email to authenticated;
  end if;
end $$;
