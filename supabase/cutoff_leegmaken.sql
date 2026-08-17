-- Pokerleague — Cutoff helemaal leegmaken voor de opening
--
-- Haalt alle tornooien, uitslagen, klassementen en leden van Cutoff weg, zodat
-- je op 6 september met een schone lei begint. Demodata én wat je zelf al
-- ingetikt hebt tijdens het testen — dit maakt geen onderscheid, dat is het
-- punt.
--
-- Wat BLIJFT staan, en dat is met opzet:
--
--   * de club zelf, met logo, kleuren, adres en instellingen
--   * de staf (club_members) — anders sluit je jezelf buiten
--   * de blindstructuren, de prijzenverdelingen en het puntensysteem
--   * de seizoenen
--
-- Dat is precies de configuratie die je niet opnieuw wil intikken. Weg gaat
-- alles wat een avond of een speler is.
--
-- De volgorde is niet vrijblijvend. Eerst de tornooien: daar hangen via
-- cascade de deelnames, inkopen, uitschakelingen, deals en uitslagen aan.
-- Pas daarna de spelers, want tournament_results verwijst met on delete
-- restrict naar players — met opzet, zodat je nooit een speler wist waar nog
-- een uitslag aan hangt.
--
-- Spelers die óók bij een andere club spelen blijven bestaan; alleen hun
-- lidmaatschap bij Cutoff verdwijnt. Vandaag is Cutoff de enige club, dus in
-- de praktijk gaat iedereen weg — maar de regel hoort te kloppen voor later.

do $$
declare
  v_club uuid;
  v_tour int; v_link int; v_inv int; v_pl int;
begin
  select id into v_club from clubs where slug = 'cutoff';
  if v_club is null then
    raise exception 'Club cutoff bestaat niet.';
  end if;

  -- 1. De avonden. Cascade ruimt deelnames, geld, knock-outs en uitslagen op.
  delete from tournaments where club_id = v_club;
  get diagnostics v_tour = row_count;

  -- 2. Openstaande uitnodigingen die nooit vertrokken zijn.
  delete from player_invites where club_id = v_club;
  get diagnostics v_inv = row_count;

  -- 3. Het ledenbestand van deze club.
  delete from club_players where club_id = v_club;
  get diagnostics v_link = row_count;

  -- 4. Spelers die nergens meer bij horen. Wie nog bij een andere club lid is
  --    of nog ergens een uitslag heeft staan, blijft.
  delete from players p
  where not exists (select 1 from club_players cp where cp.player_id = p.id)
    and not exists (select 1 from tournament_results r where r.player_id = p.id)
    and not exists (select 1 from tournament_players tp where tp.player_id = p.id);
  get diagnostics v_pl = row_count;

  raise notice 'Cutoff leeggemaakt: % tornooien, % leden, % uitnodigingen, % spelersprofielen.',
    v_tour, v_link, v_inv, v_pl;
end $$;

-- Controle. Alles hoort op nul te staan behalve de configuratie.
select
  (select count(*) from tournaments t  join clubs c on c.id = t.club_id  where c.slug = 'cutoff') as tornooien,
  (select count(*) from club_players cp join clubs c on c.id = cp.club_id where c.slug = 'cutoff') as leden,
  (select count(*) from tournament_results r join clubs c on c.id = r.club_id where c.slug = 'cutoff') as uitslagen,
  (select count(*) from club_members m  join clubs c on c.id = m.club_id  where c.slug = 'cutoff') as staf_blijft,
  (select count(*) from blind_structures s join clubs c on c.id = s.club_id where c.slug = 'cutoff') as structuren_blijven,
  (select count(*) from seasons se join clubs c on c.id = se.club_id where c.slug = 'cutoff') as seizoenen_blijven;
