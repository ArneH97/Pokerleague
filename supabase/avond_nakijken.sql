-- Pokerleague — wat er die avond werkelijk geboekt is, per speler
--
-- Draai dit als een bedrag niet klopt. Het rekent niets uit wat de app niet
-- ook uitrekent; het zet alleen alle bronnen naast elkaar, zodat je ziet
-- wáár het verschil ontstaat: in wat er geboekt is, of in hoe het opgeteld
-- wordt.
--
-- Alles leest alleen, er verandert niets.
--
-- ---------------------------------------------------------------------------
-- De club en de datum staan in elke query bovenaan in een blokje `p`:
--
--     with p as (select 'cutoff'::text as slug, date '2026-10-11' as dag)
--
-- Wil je een andere avond? Zoek-en-vervang '2026-10-11' door die datum. Het
-- staat vijf keer in dit bestand, één keer per query. Dat is lelijker dan één
-- variabele bovenaan, maar de SQL-editor van Supabase is geen psql en kent
-- `\set` niet — en een script dat niet draait is geen script.
--
-- Je kan de queries los draaien: selecteer er één en voer die uit. In
-- Supabase krijg je anders alleen de uitkomst van de laatste te zien.

-- ===========================================================================
-- 1. Welke avond(en) het gaat
-- ===========================================================================

with p as (select 'cutoff'::text as slug, date '2026-10-11' as dag)
select
  t.id,
  t.name                                  as tornooi,
  t.status,
  to_char(t.scheduled_at at time zone c.timezone, 'dd/mm/yyyy HH24:MI') as gepland,
  round(t.buyin_cents  / 100.0, 2)        as inkoop,
  round(t.fee_cents    / 100.0, 2)        as rake,
  round(t.bounty_cents / 100.0, 2)        as bounty,
  t.bounty_mode,
  s.name                                  as seizoen
from p
join clubs c       on c.slug = p.slug
join tournaments t on t.club_id = c.id
left join seasons s on s.id = t.season_id
where (t.scheduled_at at time zone c.timezone)::date = p.dag;

-- ===========================================================================
-- 2. Elke geboekte inkoop van die avond
-- ===========================================================================
-- Hier zie je of iemands rebuy wel of niet geboekt is, en of er een inkoop
-- teruggedraaid (is_void) werd. Een niet-geboekte rebuy is de meest gewone
-- oorzaak van "mijn netto klopt niet".

with p as (select 'cutoff'::text as slug, date '2026-10-11' as dag)
select
  pl.display_name                     as speler,
  b.kind                              as soort,
  round(b.amount_cents / 100.0, 2)    as pot,
  round(b.fee_cents    / 100.0, 2)    as rake,
  round(b.bounty_cents / 100.0, 2)    as bounty,
  round((b.amount_cents + b.fee_cents + b.bounty_cents) / 100.0, 2) as samen,
  b.is_void                           as teruggedraaid,
  to_char(b.occurred_at at time zone c.timezone, 'HH24:MI') as geboekt_om
from p
join clubs c       on c.slug = p.slug
join tournaments t on t.club_id = c.id
                  and (t.scheduled_at at time zone c.timezone)::date = p.dag
join buyins b      on b.tournament_id = t.id
join players pl    on pl.id = b.player_id
order by pl.display_name, b.occurred_at;

-- ===========================================================================
-- 3. Welke koppen wie pakte, en voor hoeveel
-- ===========================================================================
-- Staat een eliminatie hier niet bij, dan is er bij het uitschakelen geen
-- speler ingevuld die de kop pakte, en komt die bounty bij niemand terecht.

with p as (select 'cutoff'::text as slug, date '2026-10-11' as dag)
select
  jager.display_name                  as pakte_de_kop,
  slachtoffer.display_name            as van,
  round(e.bounty_cents / 100.0, 2)    as bedrag
from p
join clubs c        on c.slug = p.slug
join tournaments t  on t.club_id = c.id
                   and (t.scheduled_at at time zone c.timezone)::date = p.dag
join eliminations e on e.tournament_id = t.id
join tournament_players ts on ts.id = e.tournament_player_id
join players slachtoffer   on slachtoffer.id = ts.player_id
left join tournament_players tj on tj.id = e.eliminated_by_id
left join players jager         on jager.id = tj.player_id
order by jager.display_name nulls first, slachtoffer.display_name;

-- ===========================================================================
-- 4. De rekening per speler
-- ===========================================================================
-- `netto` is wat er hoort te staan: prijzengeld plus de opgehaalde bounties,
-- min alles wat hij die avond inlegde.
--
-- `netto_voor_0064` is wat de app toonde vóór migratie 0064: dezelfde som
-- maar zonder de opgehaalde bounties. Verschillen die twee, dan weet je dat
-- dat de oorzaak is.
--
-- Verschilt `inleg` van `inleg_uit_buyins`, dan is er een inkoop geboekt of
-- teruggedraaid ná het afsluiten. De uitslag draagt dan een bedrag van voor
-- die wijziging, en de avond moet opnieuw afgesloten worden.

with p as (select 'cutoff'::text as slug, date '2026-10-11' as dag)
select
  pl.display_name                                    as speler,
  r.position                                         as plaats,
  round(r.prize_cents  / 100.0, 2)                   as prijzengeld,
  r.knockouts                                        as koppen,
  round(r.bounty_cents / 100.0, 2)                   as bounty_gewonnen,
  round((r.prize_cents + r.bounty_cents) / 100.0, 2) as gewonnen,
  round(r.invested_cents / 100.0, 2)                 as inleg,
  round((select coalesce(sum(b.amount_cents + b.fee_cents + b.bounty_cents), 0)
         from buyins b
         where b.tournament_id = r.tournament_id
           and b.player_id = r.player_id
           and not b.is_void) / 100.0, 2)            as inleg_uit_buyins,
  round((r.prize_cents + r.bounty_cents - r.invested_cents) / 100.0, 2) as netto,
  round((r.prize_cents - r.invested_cents) / 100.0, 2) as netto_voor_0064,
  r.points                                           as punten
from p
join clubs c              on c.slug = p.slug
join tournaments t        on t.club_id = c.id
                         and (t.scheduled_at at time zone c.timezone)::date = p.dag
join tournament_results r on r.tournament_id = t.id
join players pl           on pl.id = r.player_id
order by r.position;

-- ===========================================================================
-- 5. En de kas van de avond
-- ===========================================================================
-- Wat er binnenkwam tegenover wat er uitging. De rake hoort bij de club, de
-- rest hoort uitbetaald te zijn.
--
-- Let vooral op `naar_de_bounties` tegenover `uitbetaalde_bounties`. Die twee
-- horen gelijk te zijn. Zijn ze dat niet, dan is er bij het uitschakelen niet
-- telkens ingevuld wie de kop pakte — de floor tikte "uitgeschakeld" zonder
-- speler erbij — en dan staan die bounties bij niemand. Dat is geen rekenfout
-- maar een ontbrekende boeking, recht te zetten door die eliminaties opnieuw
-- in te geven en de avond opnieuw af te sluiten.

with p as (select 'cutoff'::text as slug, date '2026-10-11' as dag),
avond as (
  select t.id
  from p
  join clubs c       on c.slug = p.slug
  join tournaments t on t.club_id = c.id
                    and (t.scheduled_at at time zone c.timezone)::date = p.dag
)
select
  round(coalesce((select sum(b.amount_cents) from buyins b
                  where b.tournament_id in (select id from avond)
                    and not b.is_void), 0) / 100.0, 2)   as naar_de_pot,
  round(coalesce((select sum(b.fee_cents) from buyins b
                  where b.tournament_id in (select id from avond)
                    and not b.is_void), 0) / 100.0, 2)   as rake_voor_de_club,
  round(coalesce((select sum(b.bounty_cents) from buyins b
                  where b.tournament_id in (select id from avond)
                    and not b.is_void), 0) / 100.0, 2)   as naar_de_bounties,
  round(coalesce((select sum(r.prize_cents) from tournament_results r
                  where r.tournament_id in (select id from avond)), 0) / 100.0, 2)
                                                         as uitbetaald_prijzengeld,
  round(coalesce((select sum(r.bounty_cents) from tournament_results r
                  where r.tournament_id in (select id from avond)), 0) / 100.0, 2)
                                                         as uitbetaalde_bounties;
