-- Pokerleague — een lid schrijft zichzelf in vanuit zijn kalender
--
-- De inschrijfpagina is gebouwd voor iemand die van een affiche komt: hij
-- heeft geen account en vult vier velden in. Voor een lid dat al aangemeld is,
-- is dat precies vier velden te veel — het platform weet zijn naam, zijn
-- adres en zijn geboortedatum al. Die moet één knop hebben.
--
-- Vandaar deze twee functies. Ze doen hetzelfde als `rsvp_for_tournament`,
-- maar dan voor wie al binnen is: geen gegevens meer vragen, alleen de
-- inschrijving zetten of intrekken.
--
-- **Waarom niet gewoon een insert vanuit de browser?** De policy
-- `tournament_registrations_self` staat dat toe, maar alleen voor wie al lid
-- is van die club. Een speler die bij Cutoff nog nooit speelde en de avond in
-- zijn kalender ziet staan — omdat hij bij een andere club zit en de avond
-- publiek staat — zou dan botsen op een regel die hij niet kan lezen. Deze
-- functie koppelt hem in dezelfde beweging aan de club, net als aan de deur.

/**
 * Ik kom.
 *
 * Antwoorden, allemaal bedoeld om op het scherm te tonen:
 *
 *   'ok'      — ingeschreven
 *   'already' — stond er al op
 *   'closed'  — de avond is begonnen, afgelast of bestaat niet
 *   'hidden'  — deze avond is niet voor hem zichtbaar
 *   'nobody'  — aangemeld, maar er hangt geen spelersprofiel aan dit account
 */
create or replace function public.rsvp_as_me(p_tournament_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  t        tournaments;
  v_player uuid;
begin
  v_player := public.current_player_id();
  if v_player is null then
    return jsonb_build_object('status', 'nobody');
  end if;
  v_player := public.resolve_player(v_player);

  select * into t from tournaments where id = p_tournament_id;
  if not found or t.status <> 'scheduled' or t.scheduled_at <= now() then
    return jsonb_build_object('status', 'closed');
  end if;

  -- Dezelfde zichtbaarheidsregel als overal: publiek, of voor leden bij een
  -- club waar hij bij hoort, of hij is staf.
  if not (t.player_visibility = 'public'
          or (t.player_visibility = 'members' and public.is_club_player(t.club_id))
          or public.is_club_member(t.club_id)) then
    return jsonb_build_object('status', 'hidden');
  end if;

  -- Nog geen lid van deze club? Dan wordt hij het nu. Hetzelfde als wanneer
  -- de floor hem aan de deur intikt.
  insert into club_players (club_id, player_id, joined_on)
  values (t.club_id, v_player, current_date)
  on conflict (club_id, player_id) do nothing;

  if exists (
    select 1 from tournament_registrations r
    where r.tournament_id = t.id and r.player_id = v_player and r.cancelled_at is null
  ) then
    return jsonb_build_object('status', 'already');
  end if;

  insert into tournament_registrations (club_id, tournament_id, player_id)
  values (t.club_id, t.id, v_player)
  on conflict (tournament_id, player_id) do update set cancelled_at = null;

  return jsonb_build_object('status', 'ok');
end;
$$;

comment on function public.rsvp_as_me(uuid) is
  'Een aangemeld lid schrijft zichzelf in voor een avond. Koppelt hem zo nodig aan de club, net als aan de deur.';

/**
 * Toch niet.
 *
 * Zelf afzeggen mag altijd. Dat is geen beleefdheid maar rekenwerk: een lijst
 * waar mensen op blijven staan omdat ze er niet af kunnen, is precies zo
 * onbruikbaar als geen lijst.
 */
create or replace function public.cancel_my_rsvp(p_tournament_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_player uuid;
  v_n      int;
begin
  v_player := public.current_player_id();
  if v_player is null then
    return false;
  end if;
  v_player := public.resolve_player(v_player);

  update tournament_registrations
  set cancelled_at = now()
  where tournament_id = p_tournament_id
    and player_id = v_player
    and cancelled_at is null;

  get diagnostics v_n = row_count;
  return v_n > 0;
end;
$$;

comment on function public.cancel_my_rsvp(uuid) is
  'Een lid trekt zijn eigen inschrijving in. Alleen zijn eigen; de rij blijft bestaan zodat opnieuw inschrijven gewoon werkt.';

-- ---------------------------------------------------------------------------
-- De kalender weet nu of je ingeschreven staat
-- ---------------------------------------------------------------------------
-- Zonder dit staat er op elke avond dezelfde knop, ook op de avond waar je je
-- gisteren al voor opgaf. Eén extra kolom is genoeg om het verschil tussen
-- "ik kom" en "je komt" te tonen.

drop function if exists public.my_calendar(int);

create or replace function public.my_calendar(p_days int default 120)
returns table (
  tournament_id  uuid,
  name           text,
  scheduled_at   timestamptz,
  status         text,
  club_slug      text,
  club_name      text,
  logo_url       text,
  primary_color  text,
  currency       char(3),
  timezone       text,
  buyin_cents    int,
  fee_cents      int,
  bonus_stack    int,
  entries        int,
  registered     int,
  i_play         boolean,
  i_rsvp         boolean,
  can_rsvp       boolean
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with me as (
    select id from players
    where auth_user_id = auth.uid() and merged_into_id is null
  ),
  mijn_clubs as (
    select cp.club_id from club_players cp where cp.player_id = (select id from me)
  )
  select
    t.id,
    t.name,
    t.scheduled_at,
    t.status::text,
    c.slug,
    c.name,
    c.logo_url,
    c.primary_color,
    c.currency,
    c.timezone,
    t.buyin_cents,
    t.fee_cents,
    t.prereg_bonus_stack,
    (select count(*)::int from tournament_players x where x.tournament_id = t.id),
    (select count(*)::int from tournament_registrations r
      where r.tournament_id = t.id and r.cancelled_at is null),
    exists (
      select 1 from tournament_players x
      where x.tournament_id = t.id and x.player_id = (select id from me)
    ),
    exists (
      select 1 from tournament_registrations r
      where r.tournament_id = t.id and r.player_id = (select id from me)
        and r.cancelled_at is null
    ),
    -- Inschrijven kan zolang de avond gepland is en nog moet beginnen. Zit je
    -- al aan tafel, dan is de vraag niet meer aan de orde.
    (t.status = 'scheduled' and t.scheduled_at > now()
     and not exists (select 1 from tournament_players x
                     where x.tournament_id = t.id and x.player_id = (select id from me)))
  from tournaments t
  join clubs c on c.id = t.club_id
  where t.club_id in (select club_id from mijn_clubs)
    and t.status in ('scheduled', 'running', 'paused')
    and (t.player_visibility = 'public'
         or (t.player_visibility = 'members' and public.is_club_player(t.club_id))
         or public.is_club_member(t.club_id))
    and t.scheduled_at >= now() - interval '12 hours'
    and t.scheduled_at <= now() + (greatest(p_days, 1) || ' days')::interval
  order by t.scheduled_at
$$;

comment on function public.my_calendar(int) is
  'De komende avonden bij alle clubs van de aangemelde speler, met de prijs, de bonuschips en of hij al ingeschreven staat.';

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    revoke all on function public.my_calendar(int) from public;
    revoke all on function public.rsvp_as_me(uuid) from public;
    revoke all on function public.cancel_my_rsvp(uuid) from public;

    grant execute on function public.my_calendar(int)      to authenticated, service_role;
    grant execute on function public.rsvp_as_me(uuid)      to authenticated, service_role;
    grant execute on function public.cancel_my_rsvp(uuid)  to authenticated, service_role;
  end if;
end $$;
