-- Pokerleague — de early bird aan de deur, en een inschrijving die je intrekt
--
-- Twee dingen die aan de floor door elkaar lopen en die allebei een slot
-- misten.
--
-- **1. De voorinschrijfbonus hing vast aan het formulier.** Wie via de affiche
-- inschreef kreeg zijn extra chips automatisch (migratie 0044, als trigger).
-- Maar aan de deur gebeurt het anders: iemand mailt dat hij komt, iemand zegt
-- het tegen de uitbater, iemand stond vorige week al op de lijst en viel er bij
-- het verzetten van de avond af. Dan staat de floor met een man voor zich die
-- de bonus hoort te krijgen en geen enkele manier om hem te geven — behalve
-- met de hand chips bijtikken, wat de boekhouding van "chips in spel" stilletjes
-- laat scheeflopen.
--
-- Vandaar een schakelaar, in beide richtingen. Hij boekt de bonus op dezelfde
-- drie plaatsen als de trigger: de stapel van de speler, het aantal chips dat
-- zijn inkoop op tafel legde, en een teller die zegt hoeveel bonus hij
-- werkelijk kreeg. Die laatste is nieuw en is de kern: zonder vastlegging wéét
-- je achteraf niet of de bonus er al in zit, en dan geeft twee keer drukken
-- twee keer chips.
--
-- **2. Een inschrijving intrekken kon geld van iemand anders afpakken.**
-- `floor_remove_entry` haalt een deelname helemaal weg; dat is de knop voor de
-- verkeerde man. Maar op een bountyavond hangt aan een uitschakeling het geld
-- van wie hem eruit speelde. Verdwijnt de uitgeschakelde speler, dan verdwijnt
-- die uitschakeling mee en staat de ander met een bounty die niemand meer kan
-- verantwoorden — zonder melding, want de tellers werden netjes herrekend.
--
-- Vanaf nu weigert hij dat, met de uitweg erbij: draai eerst de uitschakeling
-- terug. Precies in dat ene geval, want het gewone geval — iemand die per
-- ongeluk op "uitschakelen" belandde terwijl niemand zijn kop opeiste — moet
-- blijven werken.

-- ---------------------------------------------------------------------------
-- 1. Hoeveel bonus deze speler werkelijk kreeg
-- ---------------------------------------------------------------------------
-- Niet afleidbaar uit `prereg_bonus_stack`: dat is wat de avond vandaag
-- aanbiedt, en dat mag halverwege de avond veranderen. Wat deze speler kreeg,
-- hoort bij deze speler.

alter table tournament_players
  add column if not exists prereg_bonus int not null default 0;

comment on column public.tournament_players.prereg_bonus is
  'Hoeveel bonuschips deze deelname kreeg voor een voorinschrijving. Gezet door de trigger bij het inschrijven, of door floor_set_prereg_bonus. 0 = geen bonus gekregen.';

-- ---------------------------------------------------------------------------
-- 2. De trigger legt vast wat hij gaf
-- ---------------------------------------------------------------------------
-- Dezelfde regels als in 0044; er komt één regel bij. De rest staat er woord
-- voor woord zoals het was, zodat de twee versies naast elkaar te vergelijken
-- zijn.

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

  if exists (
    select 1 from tournament_registrations r
    where r.tournament_id = new.tournament_id
      and r.player_id = new.player_id
      and r.cancelled_at is null
  ) then
    new.chip_count   := new.chip_count + v_bonus;
    -- Nieuw: wat gegeven is, staat erbij. Anders kan de floor achteraf niet
    -- zien of de bonus er al in zit, en de schakelaar hieronder ook niet.
    new.prereg_bonus := v_bonus;
  end if;

  return new;
end;
$$;

-- Wat er al in de databank staat: wie met méér dan de startstapel begon en
-- vooraf inschreef, kreeg de bonus. Zo klopt de schakelaar ook voor de avond
-- van vandaag, die al bezig kan zijn.
update tournament_players tp
set prereg_bonus = t.prereg_bonus_stack
from tournaments t
where t.id = tp.tournament_id
  and tp.prereg_bonus = 0
  and coalesce(t.prereg_bonus_stack, 0) > 0
  and exists (
    select 1 from buyins b
    where b.tournament_player_id = tp.id
      and b.kind = 'buyin'
      and not b.is_void
      and b.chips_delta >= t.starting_stack + t.prereg_bonus_stack
  );

-- ---------------------------------------------------------------------------
-- 3. De schakelaar
-- ---------------------------------------------------------------------------

/**
 * De voorinschrijfbonus aan- of uitzetten voor één deelname.
 *
 * Drie plaatsen, in deze volgorde, en alle drie zijn nodig:
 *
 *   * de stapel van de speler — dat is wat er op tafel ligt;
 *   * `chips_delta` van zijn eerste inkoop — dat is waar "chips in spel"
 *     vandaan komt (zie 0051). Alleen de stapel bijstellen laat de gemiddelde
 *     stapel op het zaalscherm achter op de werkelijkheid;
 *   * `prereg_bonus` — zodat twee keer drukken niet twee keer chips geeft.
 *
 * Weigert op een afgelopen avond, op een speler die er al uit ligt, en op een
 * avond zonder bonus. Dat laatste is geen formaliteit: nul chips bijtellen en
 * "gedaan" antwoorden zou de floor laten denken dat er iets gebeurd is.
 */
create or replace function public.floor_set_prereg_bonus(
  p_tournament_player_id uuid,
  p_on                   boolean
)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  tp      tournament_players%rowtype;
  t       tournaments%rowtype;
  v_buyin uuid;
  v_delta int;
begin
  select * into tp from tournament_players where id = p_tournament_player_id;
  if not found then
    raise exception 'Deelnemer bestaat niet';
  end if;

  if not public.is_service_context()
     and not public.has_club_role(tp.club_id, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten' using errcode = 'insufficient_privilege';
  end if;

  select * into t from tournaments where id = tp.tournament_id;

  if t.status in ('finished', 'cancelled') then
    raise exception 'Dit tornooi is afgelopen.' using errcode = 'check_violation';
  end if;

  if tp.status not in ('active', 'registered') then
    raise exception 'Deze speler ligt eruit. Draai eerst de uitschakeling terug.'
      using errcode = 'check_violation';
  end if;

  if coalesce(t.prereg_bonus_stack, 0) = 0 then
    raise exception 'Deze avond geeft geen bonus voor voorinschrijven.'
      using errcode = 'check_violation';
  end if;

  -- Al goed? Dan is er niets te doen, en dat is geen fout. Twee toestellen die
  -- tegelijk op hetzelfde vinkje drukken horen niet in een melding te eindigen.
  if p_on and tp.prereg_bonus > 0 then
    return tp.prereg_bonus;
  end if;
  if not p_on and tp.prereg_bonus = 0 then
    return 0;
  end if;

  v_delta := case when p_on then t.prereg_bonus_stack else -tp.prereg_bonus end;

  -- De eerste inkoop van deze deelname. `order by` en niet `limit 1` op goed
  -- geluk: bij een re-entry staan er meerdere, en de bonus hoort bij de
  -- eerste.
  select b.id into v_buyin
  from buyins b
  where b.tournament_player_id = tp.id
    and b.kind = 'buyin'
    and not b.is_void
  order by b.occurred_at
  limit 1;

  update tournament_players
  set chip_count   = greatest(0, coalesce(chip_count, t.starting_stack) + v_delta),
      prereg_bonus = case when p_on then t.prereg_bonus_stack else 0 end
  where id = tp.id;

  if v_buyin is not null then
    update buyins
    set chips_delta = greatest(0, coalesce(chips_delta, 0) + v_delta)
    where id = v_buyin;
  end if;

  return case when p_on then t.prereg_bonus_stack else 0 end;
end;
$$;

comment on function public.floor_set_prereg_bonus(uuid, boolean) is
  'Zet de bonus voor voorinschrijven aan of uit voor één deelname. Boekt de chips op de stapel én op de inkoop, zodat "chips in spel" blijft kloppen. Geeft terug hoeveel bonus de speler nu heeft.';

-- ---------------------------------------------------------------------------
-- 4. Een deelname weghalen mag geen bounty van iemand anders opeten
-- ---------------------------------------------------------------------------
-- Woord voor woord de functie uit 0048, met één slot erbij. Opnieuw volledig
-- en niet met een losse trigger: deze functie is de enige plek waar een
-- deelname verdwijnt, en wie hier leest hoort alle vier de redenen bij elkaar
-- te zien staan.

create or replace function public.floor_remove_entry(p_tournament_player_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  tp        tournament_players%rowtype;
  t         tournaments%rowtype;
  v_extra   int;
  v_door    text;
begin
  select * into tp from tournament_players where id = p_tournament_player_id;
  if not found then
    raise exception 'Deelnemer bestaat niet';
  end if;

  if not public.is_service_context()
     and not public.has_club_role(tp.club_id, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten' using errcode = 'insufficient_privilege';
  end if;

  select * into t from tournaments where id = tp.tournament_id;

  if t.status in ('finished', 'cancelled') then
    raise exception 'Dit tornooi is afgelopen. Een deelname weghalen zou de uitslag veranderen.'
      using errcode = 'check_violation';
  end if;

  select count(*) into v_extra
  from buyins
  where tournament_player_id = tp.id
    and not is_void
    and kind <> 'buyin';

  if v_extra > 0 then
    raise exception 'Er staan nog % extra inkopen op deze speler. Draai die eerst terug.', v_extra
      using errcode = 'check_violation';
  end if;

  if exists (
    select 1 from tournament_deals d
    where d.tournament_id = tp.tournament_id and d.status = 'proposed'
  ) then
    raise exception 'Er ligt een dealvoorstel op tafel. Beslis daar eerst over.'
      using errcode = 'check_violation';
  end if;

  -- Nieuw. Iemand heeft de kop van deze speler opgeëist, en daar hangt op een
  -- bountyavond geld aan. Zijn deelname laten verdwijnen zou die uitschakeling
  -- meenemen en de ander zijn bounty afpakken zonder dat iemand het ziet.
  --
  -- Alleen bij een bounty, en alleen als er werkelijk iemand aangewezen is:
  -- een avond zonder bounty heeft dit probleem niet, en wie eruit ging zonder
  -- dat er een naam bij stond ook niet.
  if t.bounty_mode <> 'none' then
    select p.display_name into v_door
    from eliminations e
    join tournament_players x on x.id = e.eliminated_by_id
    join players p on p.id = x.player_id
    where e.tournament_player_id = tp.id
    limit 1;

    if v_door is not null then
      raise exception '% kreeg de bounty van deze speler. Draai eerst de uitschakeling terug.', v_door
        using errcode = 'check_violation';
    end if;
  end if;

  perform 1 from tournaments where id = tp.tournament_id for update;

  update tournament_registrations
  set cancelled_at = null
  where tournament_id = tp.tournament_id
    and player_id = tp.player_id
    and cancelled_at is not null
    and cancelled_at >= tp.registered_at;

  delete from tournament_players where id = tp.id;

  perform public.renumber_finish_positions(tp.tournament_id);

  update tournament_players x
  set bounties_won = (
    select count(*) from eliminations e where e.eliminated_by_id = x.id
  )
  where x.tournament_id = tp.tournament_id
    and x.bounties_won is distinct from (
      select count(*) from eliminations e where e.eliminated_by_id = x.id
    );
end;
$$;

comment on function public.floor_remove_entry(uuid) is
  'Haalt een deelname helemaal weg, inclusief de eerste inkoop. Voor iemand die per ongeluk werd toegevoegd of toch niet meespeelt. Weigert op een afgelopen tornooi, bij extra inkopen, bij een openstaand dealvoorstel en wanneer iemand anders zijn bounty kreeg.';

-- ---------------------------------------------------------------------------
-- 5. Rechten
-- ---------------------------------------------------------------------------

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    revoke all on function public.floor_set_prereg_bonus(uuid, boolean) from public;
    grant execute on function public.floor_set_prereg_bonus(uuid, boolean)
      to authenticated, service_role;
  end if;
end $$;
