-- Pokerleague — de prijzenverdeling die de floor zelf vastlegt
--
-- Tot nu toe kwam de verdeling volledig uit het sjabloon van de club: zoveel
-- deelnemers, dus deze percentages. Dat werkt voor een vaste clubavond en
-- breekt zodra er iets afgesproken wordt aan tafel. En er wordt van alles
-- afgesproken.
--
-- Twee dingen die op elke avond terugkomen:
--
-- 1. Hoeveel plaatsen betaald worden. Met 30 inschrijvingen wil de floor
--    kunnen zeggen "we betalen er zes" en dat meteen op het bord zetten. Dat
--    kan pas als de pot vaststaat, dus pas nadat de late reg en de rebuys
--    gesloten zijn — daarvoor verandert het bedrag nog bij elke inkoop.
--
-- 2. De bubbel. De tafel beslist geregeld dat wie net naast het geld valt
--    zijn inleg terugkrijgt. Dat is geen extra pot maar een plaats erbij, van
--    de bovenkant afgehaald.
--
-- Vandaar payout_override: een lijst bedragen in cent, plaats 1 tot N, die
-- het sjabloon overschrijft zodra ze gezet is. Bewust bedragen en geen
-- percentages — wat op het bord staat is wat er uitbetaald wordt, en daar
-- mag geen herberekening meer tussen zitten.

alter table tournaments
  add column if not exists paid_places     int,
  add column if not exists payout_override jsonb;

comment on column tournaments.payout_override is
  'Lijst bedragen in cent voor plaats 1..N, vastgelegd door de floor. Leeg = het sjabloon van de club bepaalt de verdeling.';
comment on column tournaments.paid_places is
  'Hoeveel plaatsen er betaald worden. Alleen ter informatie: payout_override is de waarheid.';

-- ---------------------------------------------------------------------------
-- 1. Een voorstel voor N plaatsen
-- ---------------------------------------------------------------------------
-- De curve is 1/plaats^0.9, genormaliseerd. Dat ligt dicht bij wat clubs met
-- de hand kiezen — 50/30/20 bij drie plaatsen, 32/17/12/9/8/6/6/5/5 bij negen
-- — en het blijft werken bij tien of twintig plaatsen, waar een vaste tabel
-- ophoudt. De floor mag elk bedrag daarna nog aanpassen; dit is een
-- vertrekpunt en geen wet.

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

  select greatest(coalesce(pt.rounding, 500), 1) into v_round
  from tournaments tt
  left join payout_templates pt on pt.id = tt.payout_template_id
  where tt.id = p_tournament_id;
  v_round := coalesce(v_round, 500);

  -- Nooit meer betaalde plaatsen dan er spelers waren.
  v_n := greatest(1, least(coalesce(p_places, 1), greatest(v_entries, 1)));

  -- De bubbel gaat van de pot af vóór de percentages, niet erna. Anders
  -- klopt de som niet meer met wat er op het bord staat.
  v_left := greatest(0, v_pot - greatest(coalesce(p_bubble_cents, 0), 0));

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
  -- Het afrondingsrestant naar plaats 1, zodat de som exact klopt.
  v_amounts[1] := v_amounts[1] + (v_left - v_sum);

  for i in 1 .. v_n loop
    place := i;
    amount_cents := v_amounts[i];
    return next;
  end loop;

  -- De bubbel als plaats N+1.
  if coalesce(p_bubble_cents, 0) > 0 and v_entries > v_n then
    place := v_n + 1;
    amount_cents := p_bubble_cents;
    return next;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Vastleggen
-- ---------------------------------------------------------------------------

create or replace function public.set_payouts(
  p_tournament_id uuid,
  p_amounts       int[]
)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  t     tournaments%rowtype;
  v_pot int;
  v_sum int;
begin
  select * into t from tournaments where id = p_tournament_id;
  if not found then
    raise exception 'Tornooi bestaat niet';
  end if;

  if not public.is_service_context()
     and not public.has_club_role(t.club_id, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten om de prijzenverdeling te zetten'
      using errcode = 'insufficient_privilege';
  end if;

  if p_amounts is null or array_length(p_amounts, 1) is null then
    raise exception 'Geen bedragen opgegeven' using errcode = 'check_violation';
  end if;

  select coalesce(sum(amount_cents), 0) into v_pot
  from buyins where tournament_id = p_tournament_id and not is_void;

  select coalesce(sum(x), 0)::int into v_sum from unnest(p_amounts) x;

  -- De som moet exact de pot zijn. Dit is het bedrag dat aan het eind van de
  -- avond over tafel gaat; een verschil van vijf euro is geen afronding maar
  -- iemand die te weinig krijgt.
  if v_sum <> v_pot then
    raise exception 'De verdeling telt op tot % cent, de pot is % cent', v_sum, v_pot
      using errcode = 'check_violation';
  end if;

  if exists (select 1 from unnest(p_amounts) x where x < 0) then
    raise exception 'Een bedrag kan niet negatief zijn' using errcode = 'check_violation';
  end if;

  update tournaments
  set payout_override = to_jsonb(p_amounts),
      paid_places     = array_length(p_amounts, 1)
  where id = p_tournament_id;

  return array_length(p_amounts, 1);
end;
$$;

-- Terug naar het sjabloon van de club.
create or replace function public.clear_payouts(p_tournament_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  t tournaments%rowtype;
begin
  select * into t from tournaments where id = p_tournament_id;
  if not found then
    return;
  end if;

  if not public.is_service_context()
     and not public.has_club_role(t.club_id, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten' using errcode = 'insufficient_privilege';
  end if;

  update tournaments set payout_override = null, paid_places = null
  where id = p_tournament_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. De ladder: eerst de override, anders het sjabloon
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

  if not public.is_service_context()
     and not public.has_club_role(t.club_id, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten' using errcode = 'insufficient_privilege';
  end if;

  -- Heeft de floor de verdeling vastgelegd, dan is dát de ladder. Geen
  -- herberekening meer: wat op het bord hing is wat er uitbetaald wordt.
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

-- ---------------------------------------------------------------------------
-- 4. Afsluiten volgt dezelfde ladder
-- ---------------------------------------------------------------------------
-- finalize_tournament rekende zelf met calc_payouts. Nu gaat het via
-- tournament_prizes, zodat er maar één plek is waar bepaald wordt wie wat
-- krijgt — en de floor op het bord ziet wat er straks uitbetaald wordt.

create or replace function public.finalize_tournament(p_tournament_id uuid)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  t             tournaments%rowtype;
  v_entries     int;
  v_rc          ranking_configs%rowtype;
  v_written     int := 0;
  r             record;
  v_prize       int;
begin
  select * into t from tournaments where id = p_tournament_id;
  if not found then
    raise exception 'Tornooi % bestaat niet', p_tournament_id;
  end if;

  if not public.is_service_context()
     and not public.has_club_role(t.club_id, array['owner','admin','floor']::club_role[])
  then
    raise exception 'Geen rechten om dit tornooi af te sluiten'
      using errcode = 'insufficient_privilege';
  end if;

  select count(distinct player_id) into v_entries
  from tournament_players where tournament_id = p_tournament_id;

  if v_entries = 0 then
    return 0;
  end if;

  select rc.* into v_rc
  from seasons s
  join ranking_configs rc on rc.id = s.ranking_config_id
  where s.id = t.season_id;

  delete from tournament_results where tournament_id = p_tournament_id;

  for r in
    select tp.player_id,
           tp.finish_position,
           coalesce((select count(*) from eliminations e
                     where e.eliminated_by_id = tp.id), 0)::int as knockouts,
           coalesce((select sum(b.amount_cents + b.fee_cents + b.bounty_cents)
                     from buyins b
                     where b.tournament_player_id = tp.id and not b.is_void), 0)::int as invested,
           coalesce((select sum(e.bounty_cents) from eliminations e
                     where e.eliminated_by_id = tp.id), 0)::int as bounty_won
    from tournament_players tp
    where tp.tournament_id = p_tournament_id
      and tp.finish_position is not null
  loop
    select coalesce(tp2.amount_cents, 0) into v_prize
    from public.tournament_prizes(p_tournament_id) tp2
    where tp2.place = r.finish_position;

    insert into tournament_results (
      club_id, tournament_id, season_id, player_id, position, entries_total,
      prize_cents, bounty_cents, invested_cents, knockouts, points, finished_at
    ) values (
      t.club_id, p_tournament_id, t.season_id, r.player_id, r.finish_position, v_entries,
      coalesce(v_prize, 0), r.bounty_won, r.invested, r.knockouts,
      public.calc_points(
        coalesce(v_rc.method, 'sqrt_ratio'),
        coalesce(v_rc.params, '{}'::jsonb),
        r.finish_position,
        v_entries,
        r.knockouts,
        t.buyin_cents,
        coalesce(v_rc.bonus_per_ko, 0),
        coalesce(v_rc.bonus_entry, 0)
      ),
      now()
    );
    v_written := v_written + 1;
  end loop;

  update tournaments set status = 'finished', ended_at = coalesce(ended_at, now())
  where id = p_tournament_id;

  return v_written;
end;
$$;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function public.suggest_payouts(uuid, int, int) to authenticated;
    grant execute on function public.set_payouts(uuid, int[])        to authenticated;
    grant execute on function public.clear_payouts(uuid)             to authenticated;
  end if;
end $$;
