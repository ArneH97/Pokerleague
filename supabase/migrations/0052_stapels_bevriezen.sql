-- Pokerleague — de ingave van spelers bevriezen, en zien wie wat intikte
--
-- Aan het einde van de avond komt het moment waarop de chipcounts ineens
-- zwaar wegen: daar hangt een deal aan, of de bepaling van wie er in het geld
-- valt. Op dat moment wil de floor rondgaan, de stapels tellen en ze zelf
-- invullen — en wil hij niet dat er ondertussen nog iemand op zijn gsm een
-- getal verzet. Vandaar een grendel.
--
-- **De grendel geldt alleen voor spelers.** De floor blijft invullen, want dat
-- is precies wat hij aan het doen is. Het is geen slot op de tabel maar een
-- slot op één weg ernaartoe.
--
-- **En hij staat op de avond, niet op de speler.** Bevriezen is een moment in
-- het verloop van het tornooi ("we gaan tellen"), geen eigenschap van iemand.
-- We bewaren het tijdstip en niet enkel ja/nee, zodat het scherm kan zeggen
-- sinds wanneer — en zodat je achteraf ziet dat er geteld is vóór de deal.
--
-- **Wat er al werd bijgehouden.** Elke wijziging van een chipcount stempelt al
-- wie hem zette (`floor` of `player`) en wanneer. Dat stond nergens op het
-- scherm. Het hoort er wel: een stapel die de speler zelf twintig minuten
-- geleden intikte, is iets anders dan eentje die de floor net geteld heeft, en
-- dat verschil bepaalt of je gaat rondlopen of niet.

alter table tournaments
  add column if not exists counts_frozen_at timestamptz;

comment on column public.tournaments.counts_frozen_at is
  'Sinds wanneer spelers hun eigen chipcount niet meer mogen wijzigen. Leeg = ingave staat open. De floor blijft altijd invullen.';

-- ---------------------------------------------------------------------------
-- 1. De bewaking van de chipcount kent de grendel
-- ---------------------------------------------------------------------------

create or replace function public.guard_player_chip_update()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_is_staff boolean;
  v_is_self  boolean;
  v_frozen   timestamptz;
begin
  if public.is_service_context() then
    return new;
  end if;

  v_is_staff := public.has_club_role(new.club_id, array['owner','admin','floor']::club_role[]);
  if v_is_staff then
    if new.chip_count is distinct from old.chip_count then
      new.chip_count_updated_at := now();
      new.chip_count_by := 'floor';
    end if;
    return new;
  end if;

  select exists (
    select 1 from players p
    where p.id = new.player_id and p.auth_user_id = auth.uid()
  ) into v_is_self;

  if not v_is_self then
    raise exception 'Geen rechten om deze deelnemer bij te werken'
      using errcode = 'insufficient_privilege';
  end if;

  if old.status <> 'active' then
    raise exception 'Je kan geen stack meer ingeven: je bent niet meer actief in dit tornooi'
      using errcode = 'check_violation';
  end if;

  -- De grendel. Alleen voor de speler zelf; de floor is hierboven al langs.
  select t.counts_frozen_at into v_frozen
  from tournaments t where t.id = new.tournament_id;

  if v_frozen is not null and new.chip_count is distinct from old.chip_count then
    raise exception 'De floor is de stapels aan het tellen. Je kan je aantal nu niet wijzigen.'
      using errcode = 'check_violation';
  end if;

  -- Alles behalve het chipaantal moet gelijk blijven.
  if (new.status, new.table_no, new.seat_no, new.finish_position,
      new.reentries_used, new.rebuys_used, new.addons_used, new.bounties_won,
      new.player_id, new.tournament_id, new.club_id)
     is distinct from
     (old.status, old.table_no, old.seat_no, old.finish_position,
      old.reentries_used, old.rebuys_used, old.addons_used, old.bounties_won,
      old.player_id, old.tournament_id, old.club_id)
  then
    raise exception 'Je kan alleen je eigen chipaantal aanpassen'
      using errcode = 'insufficient_privilege';
  end if;

  if new.chip_count is not null and (new.chip_count < 0 or new.chip_count > 1000000000) then
    raise exception 'Onmogelijk chipaantal' using errcode = 'check_violation';
  end if;

  new.chip_count_updated_at := now();
  new.chip_count_by := 'player';
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. De knop
-- ---------------------------------------------------------------------------

create or replace function public.floor_freeze_counts(
  p_tournament_id uuid,
  p_frozen        boolean
)
returns timestamptz
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  t      tournaments%rowtype;
  v_when timestamptz;
begin
  select * into t from tournaments where id = p_tournament_id;
  if not found then
    raise exception 'Tornooi bestaat niet';
  end if;

  if not public.is_service_context()
     and not public.has_club_role(t.club_id, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten' using errcode = 'insufficient_privilege';
  end if;

  -- Nog eens bevriezen terwijl het al vast staat, laat het tijdstip staan:
  -- anders verspringt "sinds 14 minuten" naar "sinds nu" omdat iemand twee
  -- keer klikte.
  v_when := case
              when not p_frozen then null
              else coalesce(t.counts_frozen_at, now())
            end;

  update tournaments set counts_frozen_at = v_when where id = p_tournament_id;
  return v_when;
end;
$$;

comment on function public.floor_freeze_counts(uuid, boolean) is
  'Zet de ingave van chipcounts door spelers op slot, of geeft ze weer vrij. De floor kan altijd invullen. Geeft het tijdstip terug waarop de grendel dichtging.';

-- ---------------------------------------------------------------------------
-- 3. De spelerskant weet het ook
-- ---------------------------------------------------------------------------
-- Zonder dit staat er op de gsm van de speler een invulveld dat bij het
-- opslaan een foutmelding geeft. Beter is een veld dat op slot staat met de
-- reden erbij.

drop function if exists public.my_live_tournaments();

create or replace function public.my_live_tournaments()
returns table (
  tournament_id        uuid,
  tournament_player_id uuid,
  name                 text,
  club_slug            text,
  club_name            text,
  logo_url             text,
  primary_color        text,
  currency             char(3),
  status               text,
  clock                text,
  level_idx            int,
  my_chips             int,
  my_chips_by          text,
  my_chips_at          timestamptz,
  counts_frozen        boolean,
  players_left         int,
  entries              int,
  avg_stack            int,
  prize_pool_cents     bigint
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
  mijn as (
    select tp.*
    from tournament_players tp
    join tournaments t on t.id = tp.tournament_id
    where tp.player_id = (select id from me)
      and t.status in ('running', 'paused')
      and tp.status in ('active', 'registered')
  )
  select
    t.id,
    m.id,
    t.name,
    c.slug,
    c.name,
    c.logo_url,
    c.primary_color,
    c.currency,
    t.status::text,
    t.clock::text,
    t.level_idx,
    m.chip_count,
    m.chip_count_by::text,
    m.chip_count_updated_at,
    t.counts_frozen_at is not null,
    (select count(*)::int from tournament_players x
      where x.tournament_id = t.id and x.status in ('active','registered')),
    (select count(*)::int from tournament_players x where x.tournament_id = t.id),
    (public.chips_in_play(t.id) / greatest(1, (
       select count(*)::int from tournament_players x
       where x.tournament_id = t.id and x.status in ('active','registered'))))::int,
    (select coalesce(sum(b.amount_cents), 0) from buyins b
      where b.tournament_id = t.id and not b.is_void)
  from mijn m
  join tournaments t on t.id = m.tournament_id
  join clubs c       on c.id = t.club_id
  order by t.scheduled_at desc;
$$;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function public.floor_freeze_counts(uuid, boolean) to authenticated;
    grant execute on function public.my_live_tournaments() to authenticated;
  end if;
end $$;
