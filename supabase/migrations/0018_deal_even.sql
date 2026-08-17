-- Pokerleague — even split erbij, en de prijzenladder mag op het bord
--
-- Twee kleine dingen die uit het gebruik komen.
--
-- 1. Een tafel spreekt geregeld gewoon af om gelijk te delen. Dat is geen
--    variant van chipchop maar een eigen keuze, en de floor moet ze alle drie
--    naast elkaar kunnen tonen: ICM, chipchop en even split. Vandaar twee
--    extra waarden bij deal_method — 'even' voor die verdeling zelf, en 'all'
--    voor "zet alle drie op het scherm en laat de tafel kiezen".
--
-- 2. De prijzenladder was afgeschermd tot de staf. Dat klopt niet met wat er
--    in een zaal gebeurt: die ladder hangt op het bord zodra de inkopen
--    dicht zijn, iedereen mag hem zien. Wie het tornooi mag bekijken mag ook
--    weten wat er te winnen valt.

alter type deal_method add value if not exists 'even';
alter type deal_method add value if not exists 'all';

-- ---------------------------------------------------------------------------
-- De ladder is niet geheim
-- ---------------------------------------------------------------------------

create or replace function public.tournament_prizes(p_tournament_id uuid)
returns table (place int, amount_cents int)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
#variable_conflict use_column
declare
  t           tournaments%rowtype;
  v_prizepool int;
  v_entries   int;
  v_tiers     jsonb;
  v_rounding  int;
begin
  select * into t from tournaments where id = p_tournament_id;
  if not found then
    return;
  end if;

  -- Iedereen die het tornooi mag zien mag de prijzenladder zien. Hij hangt
  -- toch op de muur.
  if not public.is_service_context()
     and not public.can_view_tournament(p_tournament_id) then
    raise exception 'Geen rechten' using errcode = 'insufficient_privilege';
  end if;

  if t.payout_override is not null then
    return query
    select (ord)::int, (value::text)::int
    from jsonb_array_elements(t.payout_override) with ordinality as e(value, ord)
    order by ord;
    return;
  end if;

  select count(distinct player_id) into v_entries
  from tournament_players where tournament_id = p_tournament_id;

  select coalesce(sum(amount_cents), 0) into v_prizepool
  from buyins where tournament_id = p_tournament_id and not is_void;

  select coalesce(pt.tiers, '[{"min_entries":1,"percentages":[100]}]'::jsonb),
         coalesce(pt.rounding, 500)
  into v_tiers, v_rounding
  from tournaments tt
  left join payout_templates pt on pt.id = tt.payout_template_id
  where tt.id = p_tournament_id;

  return query
  select cp.place, cp.amount_cents
  from public.calc_payouts(v_prizepool, v_entries, v_tiers, v_rounding) cp
  order by cp.place;
end;
$$;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    grant execute on function public.tournament_prizes(uuid) to anon;
  end if;
end $$;
