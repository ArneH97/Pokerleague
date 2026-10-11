-- Pokerleague — een inkoop die niet geboekt raakte alsnog inboeken
--
-- Er lag geld op tafel dat niet in de boeking staat. Dat is geen
-- schoonheidsfoutje: de pot waaruit het prijzengeld berekend wordt klopt
-- niet, het netto van die speler klopt niet, en het geldregister — je
-- verantwoording — mist een regel.
--
-- Dit script boekt die inkoop alsnog, met exact de bedragen die het systeem
-- zelf gebruikt zou hebben, en sluit de avond daarna opnieuw af zodat de
-- uitslag mee bijgewerkt wordt.
--
-- **Draai de delen één voor één.** Deel 1 en 2 lezen alleen. Deel 3 schrijft.
--
-- ---------------------------------------------------------------------------
-- Lees dit vóór deel 3
-- ---------------------------------------------------------------------------
-- Opnieuw afsluiten berekent het prijzengeld opnieuw uit de pot. Is er een
-- vaste prijzenverdeling gezet op dit tornooi (`payout_override`), dan blijven
-- de bedragen exact wat ze waren en verandert er niets aan wat er uitbetaald
-- is. Staat die er niet, dan schuift de ladder mee met de grotere pot — en
-- dan klopt de uitslag ineens niet meer met het geld dat je die avond
-- fysiek uitbetaald hebt.
--
-- Deel 1 zegt je welk van de twee het is. Is er geen vaste verdeling en wil
-- je de uitbetaalde bedragen houden, zet ze dan eerst vast met
-- `prijzengeld_rechtzetten.sql` en draai pas daarna deel 3.

-- ===========================================================================
-- DEEL 1 — hoe staat het ervoor
-- ===========================================================================

with p as (select 'cutoff'::text as slug, date '2026-10-11' as dag)
select
  t.id                                      as tornooi_id,
  t.name                                    as tornooi,
  t.status,
  round(coalesce(t.rebuy_cents, t.buyin_cents) / 100.0, 2)     as rebuy_pot,
  round(coalesce(t.rebuy_fee_cents, t.fee_cents) / 100.0, 2)   as rebuy_rake,
  round(case when t.bounty_mode = 'none' then 0 else t.bounty_cents end / 100.0, 2)
                                                               as rebuy_bounty,
  round((coalesce(t.rebuy_cents, t.buyin_cents)
       + coalesce(t.rebuy_fee_cents, t.fee_cents)
       + case when t.bounty_mode = 'none' then 0 else t.bounty_cents end) / 100.0, 2)
                                                               as rebuy_samen,
  (t.payout_override is not null)           as vaste_prijzenverdeling,
  round((select coalesce(sum(b.amount_cents), 0) from buyins b
         where b.tournament_id = t.id and not b.is_void) / 100.0, 2) as pot_nu
from p
join clubs c       on c.slug = p.slug
join tournaments t on t.club_id = c.id
                  and (t.scheduled_at at time zone c.timezone)::date = p.dag;

-- ===========================================================================
-- DEEL 2 — welke migraties draaien er, en welke niet
-- ===========================================================================
-- Waarom dit hier staat: tot migratie 0060 zat er een slot op `floor_rebuy`
-- dat een inkoop weigerde zodra de laatst doorgegeven fichetelling hoger lag
-- dan de startstapel. Precies het geval bij wie vooraf inschreef en de
-- bonusstapel kreeg. De floor kreeg dan een foutmelding en als die
-- wegklikt werd, stond er niets geboekt.
--
-- Staat `m0060_rebuy_zonder_slot` hieronder op false, dan is dat
-- hoogstwaarschijnlijk wat er gebeurd is — en overkomt het je opnieuw zolang
-- die migratie niet gedraaid is.

select
  not exists (
    select 1 from pg_proc
    where proname = 'floor_rebuy'
      and pg_get_functiondef(oid) like '%> t.starting_stack%'
  )                                                      as m0060_rebuy_zonder_slot,
  exists (select 1 from pg_proc where proname = 'season_recompute_points')
                                                         as m0061_league_punten,
  exists (select 1 from information_schema.columns
          where table_name = 'tournament_players'
            and column_name = 'seat_before_exit')        as m0062_stoel_na_rebuy,
  exists (select 1 from information_schema.columns
          where table_name = 'clubs'
            and column_name = 'standings_seasons_only')  as m0063_buyin_en_seizoen,
  exists (select 1 from pg_proc
          where proname = 'my_results'
            and pg_get_functiondef(oid) like '%bounty_cents%') as m0064_bounty_telt_mee;

-- ===========================================================================
-- DEEL 3 — de inkoop inboeken en de avond opnieuw afsluiten
-- ===========================================================================
-- Vul hieronder de naam van de speler en het soort inkoop in. 'rebuy' is een
-- herinkoop terwijl je nog meedeed, 'reentry' is opnieuw instappen nadat je
-- uitgeschakeld was. Voor het geld maakt het niets uit; voor de leesbaarheid
-- van het register wel.
--
-- Het tijdstip wordt dat van zijn eerste inkoop plus een uur. Een boeking
-- zonder geloofwaardig tijdstip maakt het register onbetrouwbaar; liever een
-- benadering die duidelijk een benadering is dan "nu", drie dagen later.

do $$
declare
  c_slug    text := 'cutoff';
  c_dag     date := date '2026-10-11';
  c_speler  text := 'Arne Halsberghe';   -- exact zoals in de uitslag
  c_soort   text := 'rebuy';             -- 'rebuy' of 'reentry'
  c_sluiten boolean := true;             -- avond opnieuw afsluiten na het boeken

  v_tour   uuid;
  v_tp     uuid;
  v_speler uuid;
  v_club   uuid;
  t        tournaments%rowtype;
  v_pot    int;
  v_fee    int;
  v_bounty int;
  v_toen   timestamptz;
  v_n      int;
begin
  select t2.id, t2.club_id into v_tour, v_club
  from clubs c
  join tournaments t2 on t2.club_id = c.id
  where c.slug = c_slug
    and (t2.scheduled_at at time zone c.timezone)::date = c_dag;

  if v_tour is null then
    raise exception 'Geen tornooi van % bij %', c_dag, c_slug;
  end if;
  select * into t from tournaments where id = v_tour;

  select tp.id, tp.player_id into v_tp, v_speler
  from tournament_players tp
  join players p on p.id = tp.player_id
  where tp.tournament_id = v_tour and p.display_name = c_speler;

  if v_tp is null then
    raise exception 'Geen speler "%" in dat tornooi. Let op de schrijfwijze.', c_speler;
  end if;

  -- Exact wat floor_rebuy gerekend zou hebben.
  v_pot    := coalesce(t.rebuy_cents, t.buyin_cents);
  v_fee    := coalesce(t.rebuy_fee_cents, t.fee_cents);
  v_bounty := case when t.bounty_mode = 'none' then 0 else t.bounty_cents end;

  select min(b.occurred_at) + interval '1 hour' into v_toen
  from buyins b where b.tournament_player_id = v_tp;
  v_toen := coalesce(v_toen, t.scheduled_at + interval '1 hour');

  insert into buyins (
    club_id, tournament_id, tournament_player_id, player_id,
    kind, amount_cents, fee_cents, bounty_cents, occurred_at
  ) values (
    v_club, v_tour, v_tp, v_speler,
    c_soort::buyin_kind, v_pot, v_fee, v_bounty, v_toen
  );

  raise notice 'OK  % geboekt voor %: € % pot, € % rake, € % bounty (om %).',
    c_soort, c_speler,
    round(v_pot / 100.0, 2), round(v_fee / 100.0, 2), round(v_bounty / 100.0, 2),
    to_char(v_toen at time zone coalesce(
      (select timezone from clubs where id = v_club), 'Europe/Brussels'), 'HH24:MI');

  if c_sluiten then
    v_n := public.floor_finish_tournament(v_tour);
    raise notice 'OK  de avond is opnieuw afgesloten, % uitslagregel(s) herrekend.', v_n;
  else
    raise notice 'LET OP  de uitslag is níét bijgewerkt. Sluit de avond opnieuw af '
                 'of draai dit script met c_sluiten op true.';
  end if;
end $$;

-- ===========================================================================
-- DEEL 4 — nakijken
-- ===========================================================================

with p as (select 'cutoff'::text as slug, date '2026-10-11' as dag)
select
  pl.display_name                                    as speler,
  r.position                                         as plaats,
  round(r.prize_cents  / 100.0, 2)                   as prijzengeld,
  round(r.bounty_cents / 100.0, 2)                   as bounty_gewonnen,
  round(r.invested_cents / 100.0, 2)                 as inleg,
  round((r.prize_cents + r.bounty_cents - r.invested_cents) / 100.0, 2) as netto,
  r.points                                           as punten
from p
join clubs c              on c.slug = p.slug
join tournaments t        on t.club_id = c.id
                         and (t.scheduled_at at time zone c.timezone)::date = p.dag
join tournament_results r on r.tournament_id = t.id
join players pl           on pl.id = r.player_id
order by r.position;
