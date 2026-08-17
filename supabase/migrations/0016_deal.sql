-- Pokerleague — de deal aan de finaletafel
--
-- Wat er in een zaal gebeurt: er zitten nog drie of vier mensen, het is laat,
-- de blinds zijn hoog en iemand stelt voor om te verdelen. Dan wil de tafel
-- twee cijfers zien. ICM houdt rekening met de prijzenladder — een grote
-- stapel is niet evenredig meer waard, want je kan maar één keer eerste
-- worden. Chipchop verdeelt gewoon naar rato van de chips. Het verschil
-- tussen die twee is precies waar de discussie over gaat, dus ze horen naast
-- elkaar op het scherm en niet één van de twee "omdat die eerlijker is".
--
-- De berekening zelf staat in de browser (src/lib/tournament/deal.ts, met
-- tests). Wat hier staat is het vastleggen: welk voorstel er op het
-- zaalscherm hangt, en wat er gebeurt als de tafel akkoord gaat. Dat hoort in
-- de database, want het zaalscherm en het floor-scherm zijn twee toestellen
-- die hetzelfde moeten tonen.

-- ---------------------------------------------------------------------------
-- 1. De prijzenladder van een lopend tornooi
-- ---------------------------------------------------------------------------
-- Het floor-scherm moet weten hoeveel er nog te verdelen valt. Dat is niet
-- de hele pot: wie al uitbetaald is aan plaats 5 en 6 telt niet meer mee.
-- Deze functie geeft de volledige ladder; de app pakt daar de bovenste N van,
-- met N het aantal spelers dat nog zit.

create or replace function public.tournament_prizes(p_tournament_id uuid)
returns table (place int, amount_cents int)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- De uitvoerkolommen heten net zo als de kolommen van calc_payouts. Zonder
-- deze regel weet plpgsql niet welke van de twee je bedoelt en weigert hij.
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
-- 2. Een voorstel op tafel leggen
-- ---------------------------------------------------------------------------
-- Hoogstens één openstaand voorstel per tornooi; die regel staat al als
-- unieke index op de tabel. Een nieuw voorstel vervangt dus het vorige in
-- plaats van ernaast te komen — anders hangt er een verouderd bedrag op de
-- muur terwijl de tafel het over iets anders heeft.

create or replace function public.deal_propose(
  p_tournament_id uuid,
  p_method        deal_method,
  p_shares        jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  t      tournaments%rowtype;
  v_id   uuid;
  v_pool int;
  v_sum  int;
begin
  select * into t from tournaments where id = p_tournament_id;
  if not found then
    raise exception 'Tornooi bestaat niet';
  end if;

  if not public.is_service_context()
     and not public.has_club_role(t.club_id, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten om een deal voor te stellen'
      using errcode = 'insufficient_privilege';
  end if;

  if t.status in ('finished', 'cancelled') then
    raise exception 'Dit tornooi is al afgelopen' using errcode = 'check_violation';
  end if;

  if jsonb_typeof(p_shares) <> 'array' or jsonb_array_length(p_shares) < 2 then
    raise exception 'Een deal heeft minstens twee spelers nodig'
      using errcode = 'check_violation';
  end if;

  select coalesce(sum((s->>'agreed_cents')::int), 0) into v_sum
  from jsonb_array_elements(p_shares) s;

  if v_sum <= 0 then
    raise exception 'De bedragen in het voorstel zijn leeg' using errcode = 'check_violation';
  end if;

  v_pool := v_sum;

  -- Het vorige voorstel intrekken in plaats van weggooien: je wil achteraf
  -- kunnen zien dat er twee keer onderhandeld is.
  update tournament_deals
  set status = 'rejected', decided_at = now()
  where tournament_id = p_tournament_id and status = 'proposed';

  insert into tournament_deals (
    club_id, tournament_id, method, status, pool_cents, shares, created_by
  ) values (
    t.club_id, p_tournament_id, p_method, 'proposed', v_pool, p_shares, auth.uid()
  )
  returning id into v_id;

  return v_id;
end;
$$;

-- Voorstel van tafel halen zonder akkoord.
create or replace function public.deal_cancel(p_tournament_id uuid)
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

  update tournament_deals
  set status = 'rejected', decided_at = now()
  where tournament_id = p_tournament_id and status = 'proposed';
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Akkoord: het tornooi eindigt met deze bedragen
-- ---------------------------------------------------------------------------
-- Eerst gewoon afsluiten zoals altijd — dat zet de eindplaatsen op chipcount
-- en berekent punten. Daarna overschrijven we het prijzengeld van wie in de
-- deal zat. De punten blijven wat ze zijn: die horen bij hoe ver je kwam, en
-- niet bij wat je onderhandelde.

create or replace function public.deal_accept(p_tournament_id uuid)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  t        tournaments%rowtype;
  d        tournament_deals%rowtype;
  v_rows   int;
  r        record;
begin
  select * into t from tournaments where id = p_tournament_id;
  if not found then
    raise exception 'Tornooi bestaat niet';
  end if;

  if not public.is_service_context()
     and not public.has_club_role(t.club_id, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten om deze deal te bevestigen'
      using errcode = 'insufficient_privilege';
  end if;

  select * into d from tournament_deals
  where tournament_id = p_tournament_id and status = 'proposed';

  if not found then
    raise exception 'Er ligt geen voorstel op tafel' using errcode = 'check_violation';
  end if;

  update tournament_deals
  set status = 'accepted', decided_at = now()
  where id = d.id;

  v_rows := public.floor_finish_tournament(p_tournament_id);

  -- Prijzengeld overschrijven voor wie meedeed aan de deal.
  for r in
    select (s->>'tournament_player_id')::uuid as tp_id,
           (s->>'agreed_cents')::int          as cents
    from jsonb_array_elements(d.shares) s
  loop
    update tournament_results tr
    set prize_cents = r.cents
    from tournament_players tp
    where tp.id = r.tp_id
      and tr.tournament_id = p_tournament_id
      and tr.player_id = tp.player_id;
  end loop;

  return v_rows;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Het zaalscherm mag het voorstel zien
-- ---------------------------------------------------------------------------
-- Realtime, want floor en beamer zijn twee toestellen die hetzelfde moeten
-- tonen op hetzelfde moment.

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'tournament_deals'
  ) then
    alter publication supabase_realtime add table tournament_deals;
  end if;
end $$;

alter table tournament_deals replica identity full;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function public.tournament_prizes(uuid)                       to authenticated;
    grant execute on function public.deal_propose(uuid, deal_method, jsonb)        to authenticated;
    grant execute on function public.deal_cancel(uuid)                             to authenticated;
    grant execute on function public.deal_accept(uuid)                             to authenticated;
  end if;
end $$;
