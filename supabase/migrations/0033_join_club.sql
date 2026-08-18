-- Pokerleague — je bij een club aansluiten zonder er geweest te zijn
--
-- Tot nu kon je maar op één manier lid worden van een club: aan de deur, door
-- de floor. Dat klopt voor wie er staat, maar het sluit de weg af die je juist
-- wil hebben — iemand die de clubpagina vindt, ziet dat er zondag gespeeld
-- wordt, en zich alvast wil aansluiten.
--
-- **Wat "lid" hier betekent, en wat niet.** Dit is een koppeling op het
-- platform: deze club verschijnt op je profiel, hun klassement telt voor jou,
-- en de floor vindt je terug zonder je naam opnieuw in te tikken. Het is geen
-- toelating en geen leeftijdscontrole. Die blijven waar ze horen: aan de deur,
-- waar er een identiteitskaart tegenover kan staan. Vandaar `self_joined`
-- hieronder — de club hoort te kunnen zien wie er nog nooit geweest is.
--
-- **En waarom een club dit mag uitzetten.** Een besloten club die op
-- uitnodiging werkt heeft niets aan een knop waarmee vreemden zich in het
-- ledenbestand zetten. Standaard staat het aan, want de meeste clubs willen
-- spelers; wie dat niet wil zet het uit.

-- ---------------------------------------------------------------------------
-- 1. Twee velden
-- ---------------------------------------------------------------------------

alter table clubs
  add column if not exists open_signup boolean not null default true;

comment on column clubs.open_signup is
  'Mag iemand zich via de clubpagina zelf aansluiten? Standaard ja. Een club die op uitnodiging werkt zet dit uit; dan blijft de deur de enige weg naar het ledenbestand.';

alter table club_players
  add column if not exists self_joined boolean not null default false;

comment on column club_players.self_joined is
  'Deze speler heeft zichzelf online aangesloten en is hier nog nooit door de floor ingeschreven. Belangrijk aan de deur: zijn leeftijd en identiteit zijn niet gecontroleerd.';

-- ---------------------------------------------------------------------------
-- 2. Aansluiten
-- ---------------------------------------------------------------------------
-- Security definer, want `club_players` mag alleen door staf beschreven
-- worden en dat blijft zo. De uitzondering staat hier, in één functie, met de
-- voorwaarden erin — en niet als een extra policy die op elke andere
-- schrijfactie ook van toepassing zou zijn.

create or replace function public.join_club(p_club_slug text)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_club   uuid;
  v_open   boolean;
  v_player uuid;
begin
  if auth.uid() is null then
    raise exception 'Niet aangemeld' using errcode = 'insufficient_privilege';
  end if;

  select id, open_signup into v_club, v_open
  from clubs
  where slug = p_club_slug and is_active;

  if v_club is null then
    return 'unknown';
  end if;
  if not v_open then
    return 'closed';
  end if;

  -- Zijn profiel ophalen, en aanmaken als het er nog niet is. Iemand kan zich
  -- registreren en meteen doorklikken naar een club zonder ooit op zijn eigen
  -- pagina geweest te zijn; dan bestaat de spelersrij nog niet.
  select id into v_player
  from players
  where auth_user_id = auth.uid() and merged_into_id is null;

  if v_player is null then
    v_player := public.claim_my_player();
  end if;

  if exists (select 1 from club_players where club_id = v_club and player_id = v_player) then
    return 'already';
  end if;

  insert into club_players (club_id, player_id, joined_on, self_joined)
  values (v_club, v_player, current_date, true);

  -- Hij hoort hier al op het platform, dus een uitnodigingsmail zou raar zijn.
  -- Voor de zekerheid toch: queue_invite slaat zelf over wie een account heeft.
  perform public.queue_invite(v_club, v_player);

  return 'joined';
end;
$$;

comment on function public.join_club(text) is
  'Sluit de aangemelde speler aan bij een club. Geeft joined, already, closed of unknown terug. Zet self_joined, zodat de floor ziet dat deze persoon hier nog nooit aan de deur stond.';

-- ---------------------------------------------------------------------------
-- 3. Waar kan ik me nog aansluiten?
-- ---------------------------------------------------------------------------
-- Voor het scherm meteen na het aansluiten. Alleen actieve clubs die
-- openstaan, en niet die waar hij al bij hoort — een lijst met vinkjes waarvan
-- de helft al aangevinkt en vastgezet is, leest als werk in plaats van als
-- aanbod.

create or replace function public.clubs_open_to_join()
returns table (
  slug      text,
  name      text,
  city      text,
  logo_url  text,
  intro     text,
  members   int
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with me as (
    select id from players
    where auth_user_id = auth.uid() and merged_into_id is null
  )
  select
    c.slug, c.name, c.city, c.logo_url, c.intro,
    (select count(*)::int from club_players cp where cp.club_id = c.id)
  from clubs c
  where c.is_active
    and c.open_signup
    and not exists (
      select 1 from club_players cp
      where cp.club_id = c.id and cp.player_id = (select id from me)
    )
  order by c.name
$$;

comment on function public.clubs_open_to_join() is
  'De clubs waar de aangemelde speler zich nog bij kan aansluiten. Toont alleen wat al publiek is over een club.';

-- ---------------------------------------------------------------------------
-- 4. Rechten
-- ---------------------------------------------------------------------------

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function public.join_club(text)          to authenticated;
    grant execute on function public.clubs_open_to_join()     to authenticated;
  end if;
end $$;
