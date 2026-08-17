-- Pokerleague — prijzengeld altijd in hele euro's
--
-- Aan de kassa liggen geen centen. Een uitslag met € 43,33 erop kost meer
-- discussie dan het bedrag waard is, en iemand moet uiteindelijk beslissen
-- of hij 43 of 44 euro uitbetaalt — dat is precies de beslissing die de
-- software hoort te nemen, en niet de floor om half één 's nachts.
--
-- Vandaar een ondergrens op de afronding: wat een club ook instelt, er wordt
-- nooit fijner dan per euro verdeeld. Een club die op vijf euro afrondt houdt
-- gewoon zijn vijf euro.
--
-- Het afrondingsrestant gaat naar plaats 1, zoals altijd, zodat de som van de
-- uitbetalingen exact de pot blijft. Is de pot zelf geen rond bedrag — een
-- buy-in van € 2,50 bijvoorbeeld — dan komen die laatste centen bij de
-- winnaar terecht. Ze kunnen nergens anders heen zonder dat de kas niet meer
-- klopt.

-- ---------------------------------------------------------------------------
-- 1. De ladder uit het sjabloon
-- ---------------------------------------------------------------------------

create or replace function public.calc_payouts(
  p_prizepool_cents int,
  p_entries         int,
  p_tiers           jsonb,
  p_rounding        int default 500
)
returns table (place int, amount_cents int)
language plpgsql
immutable
as $$
declare
  v_tier    jsonb;
  v_pcts    jsonb;
  v_amounts int[] := array[]::int[];
  v_i       int;
  v_n       int;
  v_sum     int := 0;
  -- Nooit fijner dan per euro, wat er ook ingesteld staat.
  v_round   int := greatest(coalesce(p_rounding, 100), 100);
begin
  if p_prizepool_cents is null or p_prizepool_cents <= 0
     or p_entries is null or p_entries <= 0 then
    return;
  end if;

  select t into v_tier
  from jsonb_array_elements(coalesce(p_tiers, '[]'::jsonb)) t
  where p_entries >= coalesce((t->>'min_entries')::int, 0)
    and p_entries <= coalesce((t->>'max_entries')::int, 2147483647)
  order by coalesce((t->>'min_entries')::int, 0) desc
  limit 1;

  v_pcts := coalesce(v_tier->'percentages', '[]'::jsonb);
  v_n := least(coalesce(jsonb_array_length(v_pcts), 0), p_entries);

  if v_n = 0 then
    place := 1;
    amount_cents := p_prizepool_cents;
    return next;
    return;
  end if;

  for v_i in 0 .. v_n - 1 loop
    v_amounts := v_amounts ||
      (floor(p_prizepool_cents * (v_pcts->>v_i)::numeric / 100.0 / v_round) * v_round)::int;
  end loop;

  select coalesce(sum(x), 0)::int into v_sum from unnest(v_amounts) x;
  v_amounts[1] := v_amounts[1] + (p_prizepool_cents - v_sum);

  for v_i in 1 .. array_length(v_amounts, 1) loop
    place := v_i;
    amount_cents := v_amounts[v_i];
    return next;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Het voorstel dat de floor krijgt
-- ---------------------------------------------------------------------------

create or replace function public.suggest_payouts(
  p_tournament_id uuid,
  p_places        int,
  p_bubble_cents  int default 0
)
returns table (place int, amount_cents int)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
#variable_conflict use_column
declare
  t         tournaments%rowtype;
  v_pot     int;
  v_round   int;
  v_entries int;
  v_left    int;
  v_n       int;
  v_w       numeric[] := array[]::numeric[];
  v_tot     numeric := 0;
  v_amounts int[] := array[]::int[];
  v_sum     int := 0;
  i         int;
begin
  select * into t from tournaments where id = p_tournament_id;
  if not found then
    return;
  end if;

  if not public.is_service_context()
     and not public.has_club_role(t.club_id, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten' using errcode = 'insufficient_privilege';
  end if;

  select count(distinct player_id) into v_entries
  from tournament_players where tournament_id = p_tournament_id;

  select coalesce(sum(amount_cents), 0) into v_pot
  from buyins where tournament_id = p_tournament_id and not is_void;

  select coalesce(pt.rounding, 100) into v_round
  from tournaments tt
  left join payout_templates pt on pt.id = tt.payout_template_id
  where tt.id = p_tournament_id;
  -- Ook hier: hele euro's is het minimum.
  v_round := greatest(coalesce(v_round, 100), 100);

  v_n := greatest(1, least(coalesce(p_places, 1), greatest(v_entries, 1)));

  -- De bubbel gaat er in hele euro's af, anders sleept het restje door in
  -- alle andere bedragen.
  v_left := greatest(0, v_pot - (floor(greatest(coalesce(p_bubble_cents, 0), 0) / 100.0) * 100)::int);

  if v_pot <= 0 then
    return;
  end if;

  for i in 1 .. v_n loop
    v_w := v_w || (1.0 / power(i::numeric, 0.9));
  end loop;
  select coalesce(sum(x), 0) into v_tot from unnest(v_w) x;

  for i in 1 .. v_n loop
    v_amounts := v_amounts || (floor(v_left * v_w[i] / v_tot / v_round) * v_round)::int;
  end loop;

  select coalesce(sum(x), 0)::int into v_sum from unnest(v_amounts) x;
  v_amounts[1] := v_amounts[1] + (v_left - v_sum);

  for i in 1 .. v_n loop
    place := i;
    amount_cents := v_amounts[i];
    return next;
  end loop;

  if coalesce(p_bubble_cents, 0) > 0 and v_entries > v_n then
    place := v_n + 1;
    amount_cents := (floor(p_bubble_cents / 100.0) * 100)::int;
    return next;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Bestaande clubsjablonen die fijner dan een euro afronden rechttrekken
-- ---------------------------------------------------------------------------

update payout_templates
set rounding = greatest(coalesce(rounding, 100), 100)
where coalesce(rounding, 0) < 100;
