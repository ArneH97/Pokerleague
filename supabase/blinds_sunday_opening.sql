-- Pokerleague — de blindstructuur van de openingsavond bij Cutoff
--
-- Zet de structuur uit het PDF in de database als sjabloon van de club, onder
-- de naam "Blinds Sunday Opening". Daarna kan je hem kiezen bij het aanmaken
-- van een tornooi en volgt de zaalklok hem vanzelf.
--
-- Vierentwintig levels van 20 minuten met zes pauzes ertussen. Level 23 en 24
-- zijn reservelevels: normaal is de winnaar gekend in level 21 tot 23, maar
-- een structuur die op is terwijl er nog gespeeld wordt, is erger dan twee
-- levels die je nooit nodig hebt.
--
-- **De ante is een big blind-ante.** Vanaf level 3 staat er in de kolom `ante`
-- hetzelfde bedrag als de big blind. Dat is geen fout: bij deze vorm betaalt
-- alleen de speler op de big blind een ante ter grootte van de big blind, en
-- de klok toont dat als "300 / 600 (ante 600)". Het scheelt tijd aan tafel
-- tegenover een ante die iedereen apart moet leggen.
--
-- De pauzes dragen hun opdracht in hun naam. Dat is met opzet: de floor leest
-- op de zaalklok wát er tijdens die pauze moet gebeuren — welke fiches eruit
-- gaan, wanneer de rebuys stoppen — in plaats van het uit een papier te moeten
-- halen dat op dat moment onder een asbak ligt.
--
-- Twee keer draaien doet niets dubbel: bestaat de structuur al bij Cutoff,
-- dan worden alleen haar levels vervangen.

do $$
declare
  c_slug   text := 'cutoff';
  c_naam   text := 'Blinds Sunday Opening';

  v_club   uuid;
  v_struct uuid;
  v_n      int;
  v_min    int;
begin
  select id into v_club from clubs where slug = c_slug;
  if v_club is null then
    raise exception 'Geen club met slug %.', c_slug;
  end if;

  select id into v_struct
  from blind_structures
  where club_id = v_club and name = c_naam;

  if v_struct is null then
    insert into blind_structures (club_id, name, description)
    values (v_club, c_naam,
            'No-Limit Hold''em · 40.000 startstack · levels van 20 minuten · '
            || 'BB-ante vanaf level 3 · één rebuy tot en met level 10 · ± 8 uur')
    returning id into v_struct;
    raise notice 'Structuur "%" aangemaakt bij %.', c_naam, c_slug;
  else
    raise notice 'Structuur "%" bestond al bij %; de levels worden vervangen.', c_naam, c_slug;
  end if;

  v_n := public.replace_blind_levels(v_struct, $j$[
    {"small_blind":    100, "big_blind":    200, "ante":     0, "duration_s": 1200},
    {"small_blind":    200, "big_blind":    400, "ante":     0, "duration_s": 1200},
    {"small_blind":    300, "big_blind":    600, "ante":   600, "duration_s": 1200},
    {"small_blind":    400, "big_blind":    800, "ante":   800, "duration_s": 1200},
    {"is_break": true, "label": "Pauze", "duration_s": 600},

    {"small_blind":    500, "big_blind":   1000, "ante":  1000, "duration_s": 1200},
    {"small_blind":    600, "big_blind":   1200, "ante":  1200, "duration_s": 1200},
    {"small_blind":    800, "big_blind":   1600, "ante":  1600, "duration_s": 1200},
    {"small_blind":   1000, "big_blind":   2000, "ante":  2000, "duration_s": 1200},
    {"is_break": true, "label": "Pauze", "duration_s": 600},

    {"small_blind":   1200, "big_blind":   2400, "ante":  2400, "duration_s": 1200},
    {"small_blind":   1500, "big_blind":   3000, "ante":  3000, "duration_s": 1200},
    {"is_break": true, "label": "Rebuys stoppen · color-up 100", "duration_s": 900},

    {"small_blind":   2000, "big_blind":   4000, "ante":  4000, "duration_s": 1200},
    {"small_blind":   2500, "big_blind":   5000, "ante":  5000, "duration_s": 1200},
    {"small_blind":   3000, "big_blind":   6000, "ante":  6000, "duration_s": 1200},
    {"small_blind":   4000, "big_blind":   8000, "ante":  8000, "duration_s": 1200},
    {"is_break": true, "label": "Pauze · color-up 500", "duration_s": 600},

    {"small_blind":   5000, "big_blind":  10000, "ante": 10000, "duration_s": 1200},
    {"small_blind":   6000, "big_blind":  12000, "ante": 12000, "duration_s": 1200},
    {"small_blind":   8000, "big_blind":  16000, "ante": 16000, "duration_s": 1200},
    {"small_blind":  10000, "big_blind":  20000, "ante": 20000, "duration_s": 1200},
    {"is_break": true, "label": "Pauze · 25.000-fiches erin", "duration_s": 600},

    {"small_blind":  12000, "big_blind":  24000, "ante": 24000, "duration_s": 1200},
    {"small_blind":  15000, "big_blind":  30000, "ante": 30000, "duration_s": 1200},
    {"small_blind":  20000, "big_blind":  40000, "ante": 40000, "duration_s": 1200},
    {"small_blind":  25000, "big_blind":  50000, "ante": 50000, "duration_s": 1200},
    {"is_break": true, "label": "Pauze · color-up 1.000", "duration_s": 600},

    {"small_blind":  30000, "big_blind":  60000, "ante": 60000, "duration_s": 1200},
    {"small_blind":  40000, "big_blind":  80000, "ante": 80000, "duration_s": 1200}
  ]$j$::jsonb);

  select sum(duration_s) / 60 into v_min from blind_levels where structure_id = v_struct;

  raise notice '% regels: % speellevels en % pauzes, samen % uur %.',
    v_n,
    (select count(*) from blind_levels where structure_id = v_struct and not is_break),
    (select count(*) from blind_levels where structure_id = v_struct and is_break),
    v_min / 60, lpad((v_min % 60)::text, 2, '0');
  raise notice 'Kies hem bij Nieuw tornooi, of via Blindstructuren.';
end $$;

-- Nakijken. Dit hoort exact het schema uit het PDF te zijn.
select
  case when bl.is_break then '—' else
    (row_number() over (order by bl.idx) - sum(case when bl.is_break then 1 else 0 end)
      over (order by bl.idx rows between unbounded preceding and current row))::text
  end as level,
  case when bl.is_break then coalesce(bl.label, 'Pauze')
       else to_char(bl.small_blind, 'FM999G999') || ' / ' || to_char(bl.big_blind, 'FM999G999') end as blinds,
  case when bl.is_break or bl.ante = 0 then '' else to_char(bl.ante, 'FM999G999') end as bb_ante,
  bl.duration_s / 60 as minuten
from blind_levels bl
join blind_structures bs on bs.id = bl.structure_id
join clubs c on c.id = bs.club_id
where c.slug = 'cutoff' and bs.name = 'Blinds Sunday Opening'
order by bl.idx;
