-- Pokerleague — de uitbetaallijst
--
-- Om één uur 's nachts staat er een rij aan de kassa en moet de floor uit het
-- hoofd weten wie wat krijgt. Dat is precies het moment waarop er fouten
-- gemaakt worden, en een fout met geld herstel je de week erna niet meer.
--
-- Twee momenten waarop het misgaat en die dit oplost:
--
--   * De bubbel spat. Speler acht valt af terwijl plaats acht betaald wordt,
--     en niemand die op dat moment naar de prijzenladder kijkt. De floor moet
--     bij het uitschakelen meteen zien: deze man krijgt zestig euro.
--   * Na een deal. De bedragen die de tafel afsprak staan in het voorstel,
--     maar dat voorstel verdwijnt van het scherm zodra het aanvaard is. Dan
--     ligt er geld op tafel en is er geen lijst met namen erbij.
--
-- Vandaar één functie die op elk moment vertelt wie er geld krijgt, met de
-- naam erbij, en een vinkje per speler zodat de floor kan afstrepen. Dat
-- vinkje staat in de database en niet in het scherm: aan de kassa staat vaak
-- een andere telefoon dan aan tafel, en een lijst die je halverwege kwijt
-- bent is erger dan geen lijst.

-- ---------------------------------------------------------------------------
-- 1. Afstrepen
-- ---------------------------------------------------------------------------

alter table tournament_players add column if not exists paid_at timestamptz;
alter table tournament_players add column if not exists
  paid_by uuid references auth.users(id) on delete set null;

create or replace function public.floor_mark_paid(
  p_tournament_player_id uuid,
  p_paid                 boolean default true
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  tp tournament_players%rowtype;
begin
  select * into tp from tournament_players where id = p_tournament_player_id;
  if not found then
    raise exception 'Deelnemer bestaat niet';
  end if;

  if not public.is_service_context()
     and not public.has_club_role(tp.club_id, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten' using errcode = 'insufficient_privilege';
  end if;

  update tournament_players
  set paid_at = case when p_paid then now() else null end,
      paid_by = case when p_paid then auth.uid() else null end
  where id = p_tournament_player_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Wie krijgt wat
-- ---------------------------------------------------------------------------
-- Eén bron voor de hele avond, en bewust in deze volgorde:
--
--   1. Is het tornooi afgesloten, dan staat de waarheid in tournament_results.
--      Daar heeft deal_accept de afgesproken bedragen al in gezet, dus een
--      deal komt hier vanzelf goed uit — en de lijst kan niet afwijken van
--      wat er op de uitslagpagina staat.
--   2. Loopt het nog, dan is het de prijzenladder op de eindplaats. Dat is
--      wat iemand die net afvalt mag meenemen.
--
-- Nog aan tafel en dus nog niets verdiend? Die staat er niet in. Deze lijst
-- gaat over geld dat nú uitbetaald kan worden.

create or replace function public.tournament_payouts(p_tournament_id uuid)
returns table (
  tournament_player_id uuid,
  player_name          text,
  place                int,
  amount_cents         int,
  paid_at              timestamptz
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
#variable_conflict use_column
declare
  t          tournaments%rowtype;
  v_finished boolean;
begin
  select * into t from tournaments where id = p_tournament_id;
  if not found then
    return;
  end if;

  -- Alleen staf. Dit is de kassalijst, geen publieke informatie.
  if not public.is_service_context()
     and not public.has_club_role(t.club_id, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten' using errcode = 'insufficient_privilege';
  end if;

  select exists (select 1 from tournament_results r where r.tournament_id = p_tournament_id)
  into v_finished;

  if v_finished then
    return query
    select tp.id, p.display_name, r.position, r.prize_cents, tp.paid_at
    from tournament_results r
    join tournament_players tp
      on tp.tournament_id = r.tournament_id and tp.player_id = r.player_id
    join players p on p.id = r.player_id
    where r.tournament_id = p_tournament_id
      and r.prize_cents > 0
    order by r.position;
    return;
  end if;

  return query
  select tp.id, p.display_name, tp.finish_position, pr.amount_cents, tp.paid_at
  from tournament_players tp
  join players p on p.id = tp.player_id
  join public.tournament_prizes(p_tournament_id) pr on pr.place = tp.finish_position
  where tp.tournament_id = p_tournament_id
    and tp.finish_position is not null
    and pr.amount_cents > 0
  order by tp.finish_position;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Rechten
-- ---------------------------------------------------------------------------

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function public.floor_mark_paid(uuid, boolean)  to authenticated;
    grant execute on function public.tournament_payouts(uuid)        to authenticated;
  end if;
end $$;
