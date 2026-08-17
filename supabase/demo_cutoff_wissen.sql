-- Pokerleague — de demodata van Cutoff weer weghalen
--
-- Draai dit vóór 6 september, of zodra de demo gedaan is. Alles wat
-- demo_cutoff.sql maakte is gemarkeerd: spelers op @demo.pokerleague.be en
-- tornooien die met "Demo " beginnen. Echte spelers en echte avonden blijven
-- staan.
--
-- De volgorde is niet vrijblijvend. Eerst de tornooien: daar hangen via
-- cascade de deelnames, inkopen, uitschakelingen en uitslagen aan vast. Pas
-- daarna de spelers, want tournament_results verwijst met on delete restrict
-- naar players — dat is met opzet zo, zodat je nooit per ongeluk een speler
-- wist waar nog een uitslag aan hangt.

do $$
declare
  v_club uuid;
  v_t    int;
  v_p    int;
begin
  select id into v_club from clubs where slug = 'cutoff';
  if v_club is null then
    raise notice 'Club cutoff bestaat niet, er valt niets op te ruimen.';
    return;
  end if;

  delete from tournaments
  where club_id = v_club and name like 'Demo %';
  get diagnostics v_t = row_count;

  delete from players
  where email like '%@demo.pokerleague.be';
  get diagnostics v_p = row_count;

  raise notice 'Demodata gewist: % tornooien, % spelers.', v_t, v_p;
end $$;

-- Controle: alles hoort nu op nul te staan.
select
  (select count(*) from players where email like '%@demo.pokerleague.be') as demospelers,
  (select count(*) from tournaments where name like 'Demo %')             as demotornooien;
