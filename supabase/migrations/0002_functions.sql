-- ClubStack — functies: autorisatie, compliance, payouts, punten, afronding.

-- ---------------------------------------------------------------------------
-- Autorisatiehelpers
-- ---------------------------------------------------------------------------
-- SECURITY DEFINER met vaste search_path: deze functies worden vanuit RLS-
-- policies op club_members zelf aangeroepen en zouden anders oneindig
-- recursief worden.

create or replace function public.is_club_member(p_club_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from club_members
    where club_id = p_club_id and user_id = auth.uid()
  );
$$;

create or replace function public.has_club_role(p_club_id uuid, p_roles club_role[])
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from club_members
    where club_id = p_club_id
      and user_id = auth.uid()
      and role = any(p_roles)
  );
$$;

-- Draait deze aanroep buiten een gebruikerssessie om? Waar: bij migraties,
-- seeds, serverside code met de secret key, en binnen triggers die als
-- eigenaar draaien. Onwaar voor elke gewone browseraanvraag.
--
-- Nodig omdat de functies hieronder SECURITY DEFINER zijn en dus RLS
-- omzeilen. Zonder deze grens zou elke ingelogde speler ze kunnen aanroepen
-- voor eender welke club.
-- Let op: dit kijkt naar de ROL UIT HET JWT, niet naar current_user. Binnen
-- een SECURITY DEFINER-functie is current_user altijd de eigenaar van die
-- functie, waardoor een controle daarop niets doet — hij zou voor iedereen
-- 'postgres' zien en dus altijd waar zijn.
--
-- Geen JWT betekent geen webverzoek: een migratie, een seed of psql.
create or replace function public.is_service_context()
returns boolean
language plpgsql
stable
as $$
declare
  v_role text;
begin
  begin
    v_role := auth.role();
  exception when others then
    v_role := null;
  end;
  return coalesce(v_role, 'service_role') = 'service_role';
end;
$$;

-- De spelersrij die bij de ingelogde gebruiker hoort (of null voor staf
-- die zelf niet speelt).
create or replace function public.current_player_id()
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select id from players where auth_user_id = auth.uid() limit 1;
$$;

-- Volgt de merge-pointer naar de overlevende spelersrij.
create or replace function public.resolve_player(p_player_id uuid)
returns uuid
language plpgsql
stable
as $$
declare
  v_id    uuid := p_player_id;
  v_next  uuid;
  v_hops  int := 0;
begin
  loop
    select merged_into_id into v_next from players where id = v_id;
    exit when v_next is null or v_hops > 10;
    v_id := v_next;
    v_hops := v_hops + 1;
  end loop;
  return v_id;
end;
$$;

-- Staat de ingelogde gebruiker als speler op de ledenlijst van deze club?
create or replace function public.is_club_player(p_club_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from club_players cp
    join players p on p.id = cp.player_id
    where cp.club_id = p_club_id and p.auth_user_id = auth.uid()
  );
$$;

-- Deelt de ingelogde gebruiker een club met deze speler?
create or replace function public.shares_club_with(p_player_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from club_players a
    join club_players b on b.club_id = a.club_id
    join players me on me.id = a.player_id
    where me.auth_user_id = auth.uid()
      and b.player_id = p_player_id
  );
$$;

-- Mag de ingelogde gebruiker dit tornooi zien?
create or replace function public.can_view_tournament(p_tournament_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from tournaments t
    where t.id = p_tournament_id
      and (
        public.is_club_member(t.club_id)
        or (t.player_visibility = 'public')
        or (t.player_visibility = 'members' and public.is_club_player(t.club_id))
      )
  );
$$;

-- ---------------------------------------------------------------------------
-- Compliance: gedoogbeleid Kansspelcommissie
-- ---------------------------------------------------------------------------

-- Welke dag is het nú bij deze club?
--
-- Niet overslaan: een pokeravond loopt door na middernacht, en de server
-- draait op UTC. Om 00:30 in Brussel is het in UTC nog de vorige dag. Wie
-- hier `current_date` gebruikt, telt de daglimiet tegen de verkeerde dag en
-- laat precies op het gevaarlijkste moment te veel door.
create or replace function public.club_today(p_club_id uuid default null)
returns date
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select (now() at time zone coalesce(
    (select c.timezone from clubs c where c.id = p_club_id),
    'Europe/Brussels'
  ))::date;
$$;

-- Totale inzet van een speler op één kalenderdag. Standaard over alle clubs
-- heen: de daglimiet volgt de speler, niet de club. Geef p_club_id mee voor
-- de clubgebonden variant (wat een club effectief kan controleren).
--
-- p_day is de LOKALE dag van de club, niet de serverdatum. Gebruik
-- public.club_today(club_id) om hem te bepalen.
create or replace function public.player_daily_spend_cents(
  p_player_id uuid,
  p_day       date,
  p_club_id   uuid default null
)
returns int
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  -- Financiële gegevens: alleen staf van de bevraagde club, of serverside.
  if not public.is_service_context()
     and not (p_club_id is not null
              and public.has_club_role(p_club_id, array['owner','admin','floor']::club_role[]))
  then
    raise exception 'Geen rechten om de daginzet van deze speler op te vragen'
      using errcode = 'insufficient_privilege';
  end if;

  return public.daily_spend_unchecked(p_player_id, p_day, p_club_id);
end;
$$;

-- Interne variant zonder controle, voor de compliance-trigger — die draait
-- midden in een verzoek van een floormedewerker en heeft het totaal over
-- alle clubs heen nodig.
--
-- De echte beveiliging zit niet in een rolcontrole maar in de REVOKE
-- hieronder: anon en authenticated mogen deze functie simpelweg niet
-- aanroepen. Dat is niet te omzeilen met een geknutseld JWT.
create or replace function public.daily_spend_unchecked(
  p_player_id uuid,
  p_day       date,
  p_club_id   uuid default null
)
returns int
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(sum(b.amount_cents + b.fee_cents + b.bounty_cents), 0)::int
  from buyins b
  join clubs c on c.id = b.club_id
  where b.player_id = p_player_id
    and not b.is_void
    and (p_club_id is null or b.club_id = p_club_id)
    and (b.occurred_at at time zone c.timezone)::date = p_day;
$$;

revoke all on function public.daily_spend_unchecked(uuid, date, uuid) from public;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    revoke all on function public.daily_spend_unchecked(uuid, date, uuid) from anon;
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    revoke all on function public.daily_spend_unchecked(uuid, date, uuid) from authenticated;
  end if;
end $$;

-- Bewaakt de daglimiet en het maximum aantal re-entries bij het inboeken.
-- Gedrag hangt af van clubs.compliance->>'enforce': off | warn | block.
create or replace function public.enforce_compliance_on_buyin()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_comp      jsonb;
  v_tz        text;
  v_day       date;
  v_spent     int;
  v_new_total int;
  v_max_day   int;
  v_mode      text;
  v_max_re    int;
  v_used      int;
begin
  select c.compliance, c.timezone into v_comp, v_tz
  from clubs c where c.id = new.club_id;

  v_mode := coalesce(v_comp->>'enforce', 'warn');
  if v_mode = 'off' then
    return new;
  end if;

  v_day     := (new.occurred_at at time zone v_tz)::date;
  v_max_day := coalesce((v_comp->>'max_daily_cents')::int, 10000);
  v_max_re  := coalesce((v_comp->>'max_reentries')::int, 1);

  -- Bewust de ongecontroleerde variant: deze trigger draait tijdens een
  -- verzoek van een floormedewerker en moet het totaal over alle clubs zien.
  v_spent     := public.daily_spend_unchecked(new.player_id, v_day);
  v_new_total := v_spent + new.amount_cents + new.fee_cents + new.bounty_cents;

  if v_new_total > v_max_day then
    if v_mode = 'block' then
      raise exception
        'Daglimiet overschreden: speler zou op % cent uitkomen, limiet is % cent.',
        v_new_total, v_max_day
        using errcode = 'check_violation';
    else
      raise warning 'Daglimiet overschreden: % van % cent.', v_new_total, v_max_day;
    end if;
  end if;

  if new.kind in ('reentry', 'rebuy') then
    select case when new.kind = 'reentry' then reentries_used else rebuys_used end
    into v_used
    from tournament_players where id = new.tournament_player_id;

    if coalesce(v_used, 0) + 1 > v_max_re then
      if v_mode = 'block' then
        raise exception 'Maximaal % re-entry/rebuy per tornooi toegestaan.', v_max_re
          using errcode = 'check_violation';
      else
        raise warning 'Re-entrylimiet overschreden.';
      end if;
    end if;
  end if;

  return new;
end;
$$;

create trigger buyins_compliance
  before insert on buyins
  for each row execute function public.enforce_compliance_on_buyin();

-- Houdt de tellers op tournament_players synchroon met het geldregister.
create or replace function public.sync_entry_counters()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_tp uuid := coalesce(new.tournament_player_id, old.tournament_player_id);
begin
  update tournament_players tp set
    reentries_used = (select count(*) from buyins b
                      where b.tournament_player_id = v_tp and b.kind = 'reentry' and not b.is_void),
    rebuys_used    = (select count(*) from buyins b
                      where b.tournament_player_id = v_tp and b.kind = 'rebuy'   and not b.is_void),
    addons_used    = (select count(*) from buyins b
                      where b.tournament_player_id = v_tp and b.kind = 'addon'   and not b.is_void)
  where tp.id = v_tp;
  return null;
end;
$$;

create trigger buyins_sync_counters
  after insert or update or delete on buyins
  for each row execute function public.sync_entry_counters();

-- ---------------------------------------------------------------------------
-- Prijzengeld
-- ---------------------------------------------------------------------------

-- Verdeelt de prijzenpot volgens het sjabloon. Afronding gaat naar beneden op
-- een veelvoud van p_rounding; wat overblijft gaat naar plaats 1, zodat de som
-- exact de pot is.
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
  v_round   int := greatest(coalesce(p_rounding, 1), 1);
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
  -- Nooit meer betaalde plaatsen dan deelnemers.
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

  -- Afrondingsrestant naar plaats 1, zodat de som exact de pot is.
  v_amounts[1] := v_amounts[1] + (p_prizepool_cents - v_sum);

  for v_i in 1 .. array_length(v_amounts, 1) loop
    place := v_i;
    amount_cents := v_amounts[v_i];
    return next;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- Seizoenspunten
-- ---------------------------------------------------------------------------
-- Elke club rekent anders. Vandaar een handvol benoemde methodes met
-- parameters in plaats van een vrij in te voeren formule — dat laatste is
-- een injectierisico en niemand onderhoudt het.

create or replace function public.calc_points(
  p_method      ranking_method,
  p_params      jsonb,
  p_position    int,
  p_entries     int,
  p_knockouts   int default 0,
  p_buyin_cents int default 0,
  p_bonus_ko    numeric default 0,
  p_bonus_entry numeric default 0
)
returns numeric
language plpgsql
immutable
as $$
declare
  v_pts   numeric := 0;
  v_tbl   jsonb;
  v_mult  numeric;
  v_base  numeric;
  v_dec   numeric;
  v_floor numeric;
begin
  if p_position is null or p_position < 1 or p_entries is null or p_entries < 1 then
    return 0;
  end if;

  case p_method
    when 'fixed_table' then
      v_tbl := coalesce(p_params->'table', '[]'::jsonb);
      if p_position <= jsonb_array_length(v_tbl) then
        v_pts := (v_tbl->>(p_position - 1))::numeric;
      else
        v_pts := coalesce((p_params->>'tail')::numeric, 0);
      end if;

    when 'linear' then
      v_base  := coalesce((p_params->>'base')::numeric, 100);
      v_dec   := coalesce((p_params->>'decrement')::numeric, 5);
      v_floor := coalesce((p_params->>'floor')::numeric, 1);
      v_pts   := greatest(v_base - (p_position - 1) * v_dec, v_floor);

    when 'sqrt_ratio' then
      v_mult := coalesce((p_params->>'multiplier')::numeric, 10);
      v_pts  := v_mult * sqrt(p_entries::numeric) / sqrt(p_position::numeric);

    when 'pokerstars' then
      v_mult := coalesce((p_params->>'multiplier')::numeric, 10);
      v_pts  := v_mult
                * (sqrt(p_entries::numeric) / sqrt(p_position::numeric))
                * log(10, 1 + (p_buyin_cents::numeric / 100.0));
  end case;

  v_pts := v_pts + (coalesce(p_knockouts, 0) * coalesce(p_bonus_ko, 0)) + coalesce(p_bonus_entry, 0);
  return round(greatest(v_pts, 0), 2);
end;
$$;

-- ---------------------------------------------------------------------------
-- Tornooi afsluiten
-- ---------------------------------------------------------------------------
-- Berekent pot, prijzen en punten en schrijft tournament_results weg.
-- Idempotent: opnieuw draaien overschrijft het vorige resultaat.

create or replace function public.finalize_tournament(p_tournament_id uuid)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  t             tournaments%rowtype;
  v_prizepool   int;
  v_entries     int;
  v_tiers       jsonb;
  v_rounding    int;
  v_rc          ranking_configs%rowtype;
  v_written     int := 0;
  r             record;
  v_prize       int;
begin
  select * into t from tournaments where id = p_tournament_id;
  if not found then
    raise exception 'Tornooi % bestaat niet', p_tournament_id;
  end if;

  -- Deze functie schrijft resultaten weg en omzeilt RLS. Zonder deze check
  -- zou elke ingelogde gebruiker het tornooi van een willekeurige club
  -- kunnen afsluiten.
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

  -- Alleen amount_cents vormt de pot; fee is clubinkomst, bounty wordt
  -- rechtstreeks aan de knock-outs uitbetaald.
  select coalesce(sum(amount_cents), 0) into v_prizepool
  from buyins where tournament_id = p_tournament_id and not is_void;

  select coalesce(pt.tiers, '[{"min_entries":1,"percentages":[100]}]'::jsonb),
         coalesce(pt.rounding, 500)
  into v_tiers, v_rounding
  from tournaments tt
  left join payout_templates pt on pt.id = tt.payout_template_id
  where tt.id = p_tournament_id;

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
    select coalesce(cp.amount_cents, 0) into v_prize
    from public.calc_payouts(v_prizepool, v_entries, v_tiers, v_rounding) cp
    where cp.place = r.finish_position;

    insert into tournament_results (
      club_id, tournament_id, season_id, player_id, position, entries_total,
      prize_cents, bounty_cents, invested_cents, knockouts, points, finished_at
    ) values (
      t.club_id, p_tournament_id, t.season_id, r.player_id, r.finish_position, v_entries,
      coalesce(v_prize, 0), r.bounty_won, r.invested, r.knockouts,
      case when v_rc.id is null then 0
           else public.calc_points(v_rc.method, v_rc.params, r.finish_position, v_entries,
                                   r.knockouts, t.buyin_cents, v_rc.bonus_per_ko, v_rc.bonus_entry)
      end,
      coalesce(t.ended_at, now())
    );
    v_written := v_written + 1;
  end loop;

  update tournaments
  set status = 'finished',
      clock = 'stopped',
      ended_at = coalesce(ended_at, now())
  where id = p_tournament_id;

  return v_written;
end;
$$;

-- ---------------------------------------------------------------------------
-- Seizoensklassement
-- ---------------------------------------------------------------------------
-- count_best_n wordt hier toegepast: veel clubs laten alleen de beste N
-- resultaten meetellen.

create or replace function public.season_standings(p_season_id uuid)
returns table (
  player_id      uuid,
  display_name   text,
  tournaments    int,
  counted        int,
  points         numeric,
  best_position  int,
  cashes         int,
  total_prize    int,
  knockouts      int
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_best_n int;
  v_min    int;
  v_club   uuid;
begin
  select s.club_id, rc.count_best_n, rc.min_tournaments
  into v_club, v_best_n, v_min
  from seasons s
  left join ranking_configs rc on rc.id = s.ranking_config_id
  where s.id = p_season_id;

  if v_club is null then
    return;
  end if;

  -- Klassement is voor staf en leden van de club. Een publieke ranking over
  -- clubs heen komt later en krijgt een eigen, expliciet publieke functie.
  if not public.is_service_context()
     and not public.is_club_member(v_club)
     and not public.is_club_player(v_club)
  then
    raise exception 'Geen rechten op het klassement van deze club'
      using errcode = 'insufficient_privilege';
  end if;

  return query
  with ranked as (
    select r.*,
           row_number() over (partition by r.player_id order by r.points desc) as rn
    from tournament_results r
    where r.season_id = p_season_id
  ),
  agg as (
    select ranked.player_id,
           count(*)::int                                                as tournaments,
           count(*) filter (where v_best_n is null or rn <= v_best_n)::int as counted,
           sum(ranked.points) filter (where v_best_n is null or rn <= v_best_n) as points,
           min(ranked.position)::int                                    as best_position,
           count(*) filter (where ranked.prize_cents > 0)::int          as cashes,
           sum(ranked.prize_cents + ranked.bounty_cents)::int           as total_prize,
           sum(ranked.knockouts)::int                                   as knockouts
    from ranked
    group by ranked.player_id
  )
  select a.player_id, p.display_name, a.tournaments, a.counted,
         round(coalesce(a.points, 0), 2), a.best_position, a.cashes,
         a.total_prize, a.knockouts
  from agg a
  join players p on p.id = a.player_id
  where a.tournaments >= coalesce(v_min, 0)
  order by 5 desc, a.best_position asc;
end;
$$;
