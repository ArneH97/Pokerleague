-- Pokerleague — de blindstructuur "WSOP Julien" bij Cutoff
--
-- De ladder uit Juliens schema, van 100/200 tot 100.000/200.000. Dertig
-- speellevels, wat veel meer is dan één avond nodig heeft: de onderste tien
-- zijn er voor het geval dat, niet omdat ze gespeeld worden. Een structuur die
-- op is terwijl er nog twee mensen zitten, is erger dan tien levels die je
-- nooit ziet.
--
-- **De ante is een big blind-ante, op élk level.** In de kolom `ante` staat
-- overal hetzelfde bedrag als de big blind — ook al op level 1. Dat is geen
-- fout maar wat er op het schema staat: alleen de speler op de big blind legt
-- een ante ter grootte van de big blind. De klok toont dat als
-- "100 / 200 (ante 200)".
--
-- **De pauzes staan na level 6, 12 en 18, van 15 minuten.** Dat is wat Julien
-- doorgaf ("Break 15 min à la fin du Niveau 6, 12, 18"). In de tabel zelf
-- vallen de witruimtes ná 6, 18 en 24 — de boodschap is expliciet en die wint,
-- maar het is het nakijken waard voor je hem de eerste keer draait.
--
-- **De duur van een level staat nergens op het schema.** Hier staat 20 minuten,
-- gelijk aan "Blinds Sunday Opening". Wil je 15 of 25, verander dan `c_minuten`
-- hieronder — één getal, de rest volgt.
--
-- Twee keer draaien doet niets dubbel: bestaat de structuur al bij Cutoff, dan
-- worden alleen haar levels vervangen.

do $$
declare
  c_slug    text := 'cutoff';
  c_naam    text := 'WSOP Julien';

  -- De twee knoppen van dit script.
  c_minuten int := 20;   -- duur van een speellevel
  c_pauze   int := 15;   -- duur van een pauze

  v_club    uuid;
  v_struct  uuid;
  v_n       int;
  v_min     int;

  -- De ladder: small blind, big blind. De ante is altijd de big blind, dus die
  -- hoeft er niet bij te staan — hij wordt hieronder afgeleid. Zo kan er ook
  -- geen level tussen sluipen waar ze per ongeluk niet gelijk zijn.
  c_ladder  int[][] := array[
    [   100,    200], [   200,    300], [   200,    400], [   300,    500],
    [   300,    600], [   400,    800], [   500,   1000], [   600,   1200],
    [   800,   1600], [  1000,   2000], [  1000,   2500], [  1500,   3000],
    [  2000,   4000], [  3000,   5000], [  3000,   6000], [  4000,   8000],
    [  5000,  10000], [  6000,  12000], [  8000,  16000], [ 10000,  20000],
    [ 10000,  25000], [ 15000,  30000], [ 20000,  40000], [ 25000,  50000],
    [ 30000,  60000], [ 40000,  80000], [ 50000, 100000], [ 60000, 120000],
    [ 75000, 150000], [100000, 200000]
  ];

  -- Na wélk speellevel er een pauze komt.
  c_pauzes  int[] := array[6, 12, 18];

  v_rijen   jsonb := '[]'::jsonb;
  i         int;
begin
  select id into v_club from clubs where slug = c_slug;
  if v_club is null then
    raise exception 'Geen club met slug %.', c_slug;
  end if;

  for i in 1 .. array_length(c_ladder, 1) loop
    v_rijen := v_rijen || jsonb_build_object(
      'small_blind', c_ladder[i][1],
      'big_blind',   c_ladder[i][2],
      'ante',        c_ladder[i][2],          -- big blind-ante
      'duration_s',  c_minuten * 60);

    if i = any (c_pauzes) then
      v_rijen := v_rijen || jsonb_build_object(
        'is_break',   true,
        'label',      format('Pauze %s min', c_pauze),
        'duration_s', c_pauze * 60);
    end if;
  end loop;

  select id into v_struct
  from blind_structures
  where club_id = v_club and name = c_naam;

  if v_struct is null then
    insert into blind_structures (club_id, name, description)
    values (v_club, c_naam,
            'No-Limit Hold''em · ladder van Julien · 30 levels van '
            || c_minuten || ' minuten · BB-ante op elk level · '
            || 'pauzes van ' || c_pauze || ' min na level 6, 12 en 18')
    returning id into v_struct;
    raise notice 'Structuur "%" aangemaakt bij %.', c_naam, c_slug;
  else
    raise notice 'Structuur "%" bestond al bij %; de levels worden vervangen.', c_naam, c_slug;
  end if;

  v_n := public.replace_blind_levels(v_struct, v_rijen);

  select sum(duration_s) / 60 into v_min from blind_levels where structure_id = v_struct;

  raise notice '% regels: % speellevels en % pauzes, samen % uur %.',
    v_n,
    (select count(*) from blind_levels where structure_id = v_struct and not is_break),
    (select count(*) from blind_levels where structure_id = v_struct and is_break),
    v_min / 60, lpad((v_min % 60)::text, 2, '0');
  raise notice 'Kies hem bij Nieuw tornooi, of via Blindstructuren.';
end $$;

-- Nakijken. Dit hoort exact het schema van Julien te zijn.
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
where c.slug = 'cutoff' and bs.name = 'WSOP Julien'
order by bl.idx;
