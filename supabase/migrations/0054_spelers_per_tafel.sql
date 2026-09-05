-- Pokerleague — hoeveel spelers er per tafel zitten
--
-- Een tornooi is 9-max of 8-max of 6-max, en dat is geen detail: het bepaalt
-- hoeveel tafels je moet openen, wanneer je er een breekt, en hoe het spel
-- speelt. Tot nu stond het nergens. De tabel `tournament_tables` kende al een
-- `seats` per tafel, maar er was geen afspraak op het niveau van de avond
-- waar die tafels hun aantal vandaan halen.
--
-- Vandaar één veld op het tornooi. De tafels die er straks bij komen erven
-- het; wie één tafel afwijkend wil zetten, kan dat daar nog altijd.
--
-- **Waarom negen als standaard.** Dat is de volle ring waar de meeste clubs
-- mee draaien, en het is de veiligste kant om op te vergissen: te ruim zetten
-- geeft een tafel met een lege stoel, te krap zetten geeft een speler die
-- nergens kan zitten.
--
-- **En waarom er een grens op staat.** Twee is heads-up, tien is de breedste
-- tafel die in een zaal past. Daarbuiten is het een tikfout, en een tikfout in
-- dit veld merk je pas als er tien man rond een tafel voor acht staat.
--
-- ---------------------------------------------------------------------------
-- Tussendoor: de lijst met bij te stellen velden verhuist naar een functie
-- ---------------------------------------------------------------------------
-- `update_tournament` (0049) draagt die lijst als constante in zijn body. Elk
-- nieuw veld betekent dus de hele functie opnieuw uitschrijven — honderd
-- regels overtypen om er één woord bij te zetten, en dat gaat een keer mis.
-- De lijst staat nu apart; een volgend veld is voortaan één regel.

alter table tournaments
  add column if not exists seats_per_table int not null default 9;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'tournaments_seats_per_table_check'
  ) then
    alter table tournaments
      add constraint tournaments_seats_per_table_check
      check (seats_per_table between 2 and 10);
  end if;
end $$;

comment on column public.tournaments.seats_per_table is
  'Hoeveel spelers er maximaal aan één tafel zitten: 9 voor een volle ring, 8 voor 8-max, 6 voor short-handed. Tafels die voor dit tornooi worden geopend, erven dit aantal.';

-- ---------------------------------------------------------------------------
-- 1. Wat een mens aan een bestaand tornooi mag bijstellen
-- ---------------------------------------------------------------------------

create or replace function public.tournament_editable_fields()
returns text[]
language sql
immutable
as $$
  select array[
    'name', 'notes', 'scheduled_at', 'player_visibility',
    'season_id', 'structure_id', 'payout_template_id',
    'buyin_cents', 'fee_cents', 'rebuy_cents', 'rebuy_fee_cents',
    'addon_cents', 'addon_fee_cents', 'addon_stack',
    'bounty_mode', 'bounty_cents',
    'starting_stack', 'max_reentries', 'late_reg_level',
    'prereg_bonus_stack', 'seats_per_table'
  ];
$$;

comment on function public.tournament_editable_fields() is
  'De velden die het bewerkscherm van een tornooi mag wijzigen. Staat apart zodat er een veld bij kan zonder update_tournament opnieuw uit te schrijven.';

create or replace function public.update_tournament(
  p_tournament_id uuid,
  p_patch         jsonb
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  t         tournaments%rowtype;
  v_new     tournaments%rowtype;
  v_sleutel text;
  v_klok    boolean;

  c_toegestaan constant text[] := public.tournament_editable_fields();
  -- Hiervan blijft er ná afloop nog iets over: een verkeerd gespelde naam mag
  -- je altijd rechtzetten.
  c_na_afloop constant text[] := array['name', 'notes', 'player_visibility'];
begin
  select * into t from tournaments where id = p_tournament_id;
  if not found then
    raise exception 'Tornooi bestaat niet';
  end if;

  if not public.is_service_context()
     and not public.has_club_role(t.club_id, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten om dit tornooi te wijzigen'
      using errcode = 'insufficient_privilege';
  end if;

  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then
    raise exception 'Geef een object mee met de velden die moeten wijzigen'
      using errcode = 'check_violation';
  end if;

  for v_sleutel in select jsonb_object_keys(p_patch) loop
    if not (v_sleutel = any(c_toegestaan)) then
      raise exception 'Het veld "%" kan hier niet gewijzigd worden.', v_sleutel
        using errcode = 'check_violation';
    end if;
    if t.status in ('finished', 'cancelled') and not (v_sleutel = any(c_na_afloop)) then
      raise exception 'Deze avond is afgelopen. Alleen de naam en de zichtbaarheid kunnen nog wijzigen, "%" niet.', v_sleutel
        using errcode = 'check_violation';
    end if;
  end loop;

  v_new := jsonb_populate_record(t, p_patch);

  v_klok := t.started_at is not null or t.level_idx > 0;
  if v_new.structure_id is distinct from t.structure_id and v_klok then
    raise exception 'De klok van deze avond heeft al gelopen. De blindstructuur wisselen zou de zaal naar een ander level sturen dan wat er op tafel ligt.'
      using errcode = 'check_violation';
  end if;

  if v_new.starting_stack <= 0 then
    raise exception 'De startstapel moet groter zijn dan nul' using errcode = 'check_violation';
  end if;

  if v_new.seats_per_table < 2 or v_new.seats_per_table > 10 then
    raise exception 'Een tafel heeft plaats voor 2 tot 10 spelers' using errcode = 'check_violation';
  end if;

  if least(
       v_new.buyin_cents, v_new.fee_cents, v_new.bounty_cents,
       coalesce(v_new.rebuy_cents, 0), coalesce(v_new.rebuy_fee_cents, 0),
       coalesce(v_new.addon_cents, 0), coalesce(v_new.addon_fee_cents, 0),
       v_new.prereg_bonus_stack, v_new.max_reentries
     ) < 0 then
    raise exception 'Bedragen en aantallen kunnen niet negatief zijn' using errcode = 'check_violation';
  end if;

  update tournaments set
    name               = v_new.name,
    notes              = v_new.notes,
    scheduled_at       = v_new.scheduled_at,
    player_visibility  = v_new.player_visibility,
    season_id          = v_new.season_id,
    structure_id       = v_new.structure_id,
    payout_template_id = v_new.payout_template_id,
    buyin_cents        = v_new.buyin_cents,
    fee_cents          = v_new.fee_cents,
    rebuy_cents        = v_new.rebuy_cents,
    rebuy_fee_cents    = v_new.rebuy_fee_cents,
    addon_cents        = v_new.addon_cents,
    addon_fee_cents    = v_new.addon_fee_cents,
    addon_stack        = v_new.addon_stack,
    bounty_mode        = v_new.bounty_mode,
    bounty_cents       = v_new.bounty_cents,
    starting_stack     = v_new.starting_stack,
    max_reentries      = v_new.max_reentries,
    late_reg_level     = v_new.late_reg_level,
    prereg_bonus_stack = v_new.prereg_bonus_stack,
    seats_per_table    = v_new.seats_per_table
  where id = p_tournament_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Een tafel erft het aantal van de avond
-- ---------------------------------------------------------------------------
-- Zodat de indeling die hierna komt niet elke keer opnieuw hoeft te bedenken
-- hoeveel stoelen er aan een tafel staan. Wie een tafel bewust anders zet —
-- een finaletafel voor tien — geeft `seats` gewoon mee; dan blijft die staan.

create or replace function public.default_table_seats()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.seats is null then
    select t.seats_per_table into new.seats
    from tournaments t where t.id = new.tournament_id;
  end if;
  return new;
end;
$$;

alter table tournament_tables alter column seats drop not null;
alter table tournament_tables alter column seats drop default;

drop trigger if exists tournament_tables_default_seats on tournament_tables;
create trigger tournament_tables_default_seats
  before insert on tournament_tables
  for each row execute function public.default_table_seats();

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function public.update_tournament(uuid, jsonb) to authenticated;
    grant execute on function public.tournament_editable_fields() to authenticated;
  end if;
end $$;
