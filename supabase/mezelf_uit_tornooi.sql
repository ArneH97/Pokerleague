-- Pokerleague — één deelname uit één tornooi halen
--
-- Voor de situatie van 1 september: per ongeluk jezelf aan het Grand Opening
-- Event toegevoegd, daarna op "Uitschakelen" geklikt omdat dat de enige knop
-- was die op weghalen leek, en nu sta je als winnaar op de uitbetaallijst.
--
-- Draai dit **nadat** `0048_speler_verwijderen.sql` erdoor is. Deze functie
-- bestaat pas vanaf die migratie.
--
-- Er zit geen proefdraaistand op. Hij toont eerst wie hij gaat weghalen, doet
-- het dan, en stopt met een foutmelding als er niemand gevonden wordt — dan is
-- er niets gebeurd.

do $$
declare
  -- Het tornooi uit de adresbalk van het floorscherm:
  -- .../c/cutoff/floor/38fd3ff1-f0ac-4df9-b5e0-84ff435ce608
  c_tornooi uuid := '38fd3ff1-f0ac-4df9-b5e0-84ff435ce608';
  -- Wie eruit moet. Op mailadres, want dat is de enige sleutel die niet
  -- toevallig bij twee mensen hetzelfde is.
  c_mail    text := 'arne@halcoservices.be';

  r      record;
  v_naam text;
  v_n    int := 0;
begin
  if not exists (select 1 from tournaments where id = c_tornooi) then
    raise exception 'Er bestaat geen tornooi met id %. Kijk de id in de adresbalk na.', c_tornooi;
  end if;

  for r in
    select tp.id, p.display_name, tp.status, tp.finish_position
    from tournament_players tp
    join players p on p.id = tp.player_id
    where tp.tournament_id = c_tornooi
      and lower(p.email) = lower(c_mail)
  loop
    raise notice 'Weghalen: % (status %, plaats %)', r.display_name, r.status, r.finish_position;
    v_naam := r.display_name;
    perform public.floor_remove_entry(r.id);
    v_n := v_n + 1;
  end loop;

  if v_n = 0 then
    raise exception 'Geen deelname van % in dit tornooi. Er is niets gewijzigd.', c_mail;
  end if;

  raise notice '% deelname(s) weggehaald. % blijft gewoon lid van de club.', v_n, v_naam;
end $$;

-- Controle achteraf: dit hoort nu leeg te zijn, of alleen de mensen te tonen
-- die er wél in horen.
select p.display_name, tp.status, tp.finish_position, tp.paid_at
from tournament_players tp
join players p on p.id = tp.player_id
where tp.tournament_id = '38fd3ff1-f0ac-4df9-b5e0-84ff435ce608'
order by p.display_name;
