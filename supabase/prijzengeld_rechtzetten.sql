-- Pokerleague — het prijzengeld van een afgesloten avond rechtzetten
--
-- De uitslag klopt, de bedragen niet. Dat gebeurt: de winnaar kreeg wat de
-- tweede hoorde te krijgen, of er is bij het uitbetalen een cijfer omgewisseld.
-- Dit zet de bedragen recht zonder aan de uitslag te komen.
--
-- **Wat dit níét verandert: de punten.** Die volgen uit de plaats en het aantal
-- deelnemers, niet uit het geld. Wie eerste werd blijft eerste en houdt zijn
-- punten — alleen het bedrag in de kolom "prijzengeld" verandert.
--
-- **Eén ding om te weten.** Het prijzengeld in de uitslag wordt berekend op het
-- moment dat je de avond afsluit, uit de prijzenverdeling van dat tornooi.
-- Sluit je diezelfde avond ooit opnieuw af, dan rekent hij opnieuw en is deze
-- correctie weg. Bij een afgesloten avond die je met rust laat, blijft ze
-- staan.
--
-- **Draai eerst alleen deel 1.** Dan zie je de huidige uitslag met de namen
-- erbij en kan je nakijken of de plaatsen wel kloppen voor je aan de bedragen
-- komt.

-- ===========================================================================
-- DEEL 1 — hoe staat het er nu bij
-- ===========================================================================

select
  r.position                            as plaats,
  p.display_name                        as speler,
  round(r.prize_cents / 100.0, 2)       as prijzengeld,
  r.points                              as punten,
  r.knockouts,
  t.name                                as tornooi,
  to_char(r.finished_at, 'dd/mm/yyyy')  as afgesloten
from tournament_results r
join tournaments t on t.id = r.tournament_id
join clubs       c on c.id = t.club_id
join players     p on p.id = r.player_id
where c.slug = 'cutoff'
order by r.finished_at, r.position;

-- ===========================================================================
-- DEEL 2 — rechtzetten
-- ===========================================================================

do $$
declare
  -- ------------------------------------------------------------- invullen
  c_slug    text := 'cutoff';
  -- De naam van de avond. Hoofdletters en randspaties doen er niet toe.
  c_tornooi text := 'Sunday Grand Opening';

  -- Wat er per plaats uitbetaald hoorde te worden, in euro.
  -- Vorm: [[plaats, bedrag], [plaats, bedrag], ...]
  c_bedragen numeric[][] := array[
    [1, 200],
    [2, 180]
  ];

  -- Standaard weigert dit script als de som verandert: het prijzengeld is
  -- echt geld dat echt is uitbetaald, en een totaal dat verschuift is meestal
  -- een typefout. Klopt het nieuwe totaal wél, zet dit dan op true.
  c_totaal_mag_wijzigen boolean := false;
  -- -------------------------------------------------------------

  v_club   uuid;
  v_tour   uuid;
  v_naam   text;
  v_voor   bigint;
  v_na     bigint;
  v_n      int := 0;
  v_raak   int;
  i        int;
  v_plaats int;
  v_cent   int;
  r        record;
begin
  select id into v_club from clubs where slug = c_slug;
  if v_club is null then
    raise exception 'Geen club met slug %.', c_slug;
  end if;

  select t.id, t.name into v_tour, v_naam
  from tournaments t
  where t.club_id = v_club and lower(trim(t.name)) = lower(trim(c_tornooi));

  if v_tour is null then
    raise exception 'Geen tornooi bij % met de naam "%". Kijk in deel 1 hoe het écht heet.',
      c_slug, c_tornooi;
  end if;

  if not exists (select 1 from tournament_results where tournament_id = v_tour) then
    raise exception 'Voor "%" staat er nog geen uitslag. Sluit de avond eerst af.', v_naam;
  end if;

  select coalesce(sum(prize_cents), 0) into v_voor
  from tournament_results where tournament_id = v_tour;

  -- Eerst tonen wat er verandert, per regel, mét de naam erbij. Zo zie je
  -- meteen of het bedrag bij de juiste persoon terechtkomt.
  for i in 1 .. array_length(c_bedragen, 1) loop
    v_plaats := c_bedragen[i][1]::int;
    v_cent   := round(c_bedragen[i][2] * 100)::int;

    select p.display_name, r2.prize_cents into r
    from tournament_results r2
    join players p on p.id = r2.player_id
    where r2.tournament_id = v_tour and r2.position = v_plaats;

    if not found then
      raise exception 'Er staat geen speler op plaats % bij "%".', v_plaats, v_naam;
    end if;

    if r.prize_cents = v_cent then
      raise notice 'Plaats % (%): stond al op % euro, blijft.',
        v_plaats, r.display_name, round(v_cent / 100.0, 2);
    else
      raise notice 'Plaats % (%): % euro wordt % euro.',
        v_plaats, r.display_name, round(r.prize_cents / 100.0, 2), round(v_cent / 100.0, 2);
    end if;

    update tournament_results
    set prize_cents = v_cent
    where tournament_id = v_tour and position = v_plaats;
    get diagnostics v_raak = row_count;
    v_n := v_n + v_raak;
  end loop;

  select coalesce(sum(prize_cents), 0) into v_na
  from tournament_results where tournament_id = v_tour;

  if v_na <> v_voor and not c_totaal_mag_wijzigen then
    raise exception 'Het totaal zou van % naar % euro gaan. Klopt dat, zet c_totaal_mag_wijzigen op true; anders staat er een typefout in. Alles teruggedraaid.',
      round(v_voor / 100.0, 2), round(v_na / 100.0, 2);
  end if;

  raise notice 'OK  % regel(s) aangepast. Totaal prijzengeld: % euro.', v_n, round(v_na / 100.0, 2);
  raise notice 'De plaatsen en de punten zijn niet aangeraakt.';
end $$;

-- ===========================================================================
-- DEEL 3 — nakijken, en het klassement zoals de app het rekent
-- ===========================================================================

select
  r.position              as plaats,
  p.display_name          as speler,
  round(r.prize_cents / 100.0, 2) as prijzengeld,
  r.points                as punten
from tournament_results r
join tournaments t on t.id = r.tournament_id
join clubs       c on c.id = t.club_id
join players     p on p.id = r.player_id
where c.slug = 'cutoff' and lower(trim(t.name)) = lower(trim('Sunday Grand Opening'))
order by r.position;

select s.display_name, s.tournaments, s.points, s.best_position, s.cashes,
       round(s.total_prize / 100.0, 2) as prijzengeld
from clubs c
cross join lateral public.club_standings_period(
  c.id,
  coalesce((select min(r.finished_at)::date - 1 from tournament_results r
              join tournaments t on t.id = r.tournament_id
             where t.club_id = c.id), current_date),
  coalesce((select max(r.finished_at)::date + 1 from tournament_results r
              join tournaments t on t.id = r.tournament_id
             where t.club_id = c.id), current_date)
) s
where c.slug = 'cutoff'
order by s.points desc, s.display_name;
