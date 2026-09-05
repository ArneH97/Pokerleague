-- Pokerleague — een andere blindstructuur op een bestaand tornooi zetten
--
-- In het scherm kan dit vandaag niet: je kiest de structuur bij het aanmaken
-- van een avond, en daarna is er geen bewerkscherm. Dit bestand doet het dus
-- rechtstreeks.
--
-- **Wat er precies gebeurt.** Een tornooi bewaart alleen een verwijzing naar
-- de structuur; de klok leest de levels elke keer opnieuw op. Deze verwijzing
-- verzetten is dus genoeg — er wordt niets gekopieerd en er is niets dat
-- achteraf nog bijgewerkt moet worden.
--
-- **Waarom het weigert zodra de klok gelopen heeft.** Een tornooi onthoudt op
-- welk levelnummer het staat, niet welke blinds daarbij horen. Verwissel je de
-- structuur halverwege, dan blijft dat nummer staan en springt de zaal naar
-- level 7 van de nieuwe structuur — met andere blinds dan wat er op tafel
-- ligt. Vandaar: alleen op een avond die nog moet beginnen.

do $$
declare
  -- Het tornooi, uit de adresbalk van het floor- of tornooischerm.
  c_tornooi   uuid := '38fd3ff1-f0ac-4df9-b5e0-84ff435ce608';
  -- De structuur die erop moet, op naam.
  c_structuur text := 'Blinds Sunday Opening';

  t        tournaments%rowtype;
  v_str    uuid;
  v_oud    text;
  v_levels int;
  v_duur   int;
begin
  select * into t from tournaments where id = c_tornooi;
  if not found then
    raise exception 'Er bestaat geen tornooi met id %.', c_tornooi;
  end if;

  -- De structuur moet van deze club zijn, of van niemand (een structuur zonder
  -- club is een sjabloon van het platform). Een structuur van een ándere club
  -- op je avond zetten hoort niet te kunnen.
  select id into v_str
  from blind_structures
  where lower(btrim(name)) = lower(btrim(c_structuur))
    and (club_id = t.club_id or club_id is null)
  order by (club_id is null)          -- de eigen structuur gaat voor
  limit 1;

  if v_str is null then
    raise exception 'Geen structuur met de naam "%" bij deze club. Wat er wél staat: %',
      c_structuur,
      (select string_agg(name, ' · ' order by name) from blind_structures
        where club_id = t.club_id or club_id is null);
  end if;

  if t.status not in ('draft', 'scheduled') then
    raise exception 'Dit tornooi staat op "%" en is dus al begonnen of afgelopen. De structuur wisselen zou de zaal naar een ander level sturen dan wat er op tafel ligt. Er is niets gewijzigd.', t.status;
  end if;

  if t.level_idx > 0 or t.started_at is not null then
    raise exception 'De klok van dit tornooi heeft al gelopen (level %). Er is niets gewijzigd.', t.level_idx + 1;
  end if;

  select name into v_oud from blind_structures where id = t.structure_id;

  update tournaments set structure_id = v_str where id = c_tornooi;

  select count(*), coalesce(sum(duration_s), 0) into v_levels, v_duur
  from blind_levels where structure_id = v_str;

  raise notice 'Avond: %', t.name;
  raise notice 'Structuur: %  ->  %', coalesce(v_oud, '(geen)'), c_structuur;
  raise notice '% niveaus, samen % uur % minuten.',
    v_levels, v_duur / 3600, (v_duur % 3600) / 60;
end $$;

-- Controle: de eerste niveaus zoals de zaalklok ze straks toont.
select
  l.idx + 1                        as nr,
  case when l.is_break then 'PAUZE' else 'spel' end as soort,
  l.small_blind, l.big_blind, l.ante,
  l.duration_s / 60                as minuten,
  l.label
from tournaments t
join blind_levels l on l.structure_id = t.structure_id
where t.id = '38fd3ff1-f0ac-4df9-b5e0-84ff435ce608'
order by l.idx
limit 8;
