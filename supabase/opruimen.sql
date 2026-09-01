-- ===========================================================================
--  P O K E R L E A G U E   —   S C H O N E   L E I
-- ===========================================================================
--
--  LET OP: dit bestand doet standaard NIETS.
--
--  Draai het één keer zoals het is: je krijgt te zien wát er zou verdwijnen,
--  en er wordt niets aangeraakt. Wil je het echt, zet dan hieronder
--
--      c_echt_doen boolean := false;   →   c_echt_doen boolean := true;
--
--  en draai het opnieuw. Onderaan staat een tabel die in één woord zegt of
--  het gelukt is.
--
-- ---------------------------------------------------------------------------
--  WAT ER GEBEURT
--
--  1. Aalst Poker Club verdwijnt volledig: de club, haar avonden, leden,
--     structuren, seizoenen, medewerkers en facturatieregel.
--
--  2. Cutoff wordt leeggemaakt: alle tornooien, uitslagen, inkopen,
--     inschrijvingen, leden, uitnodigingen en aanvragen.
--
--  3. Spelersprofielen die daarna nergens meer bij horen, gaan weg.
--
--  WAT BLIJFT STAAN
--
--    * Cutoff zelf, met logo, kleuren, adres, speeldag en instellingen
--    * jouw toegang en die van de andere medewerkers van Cutoff
--    * de blindstructuren, de uitbetalingsschema's, het puntensysteem
--      en het seizoen — de configuratie die je niet opnieuw wil intikken
--    * elk account in Supabase Auth. Daar raakt dit bestand niet aan.
--
--  Het openingstornooi maak je hierna opnieuw aan. Dat is bewust: een avond
--  waar tijdens het testen al inschrijvingen en inkopen aan hingen, begint
--  nooit helemaal schoon.
--
--  NA DIT SCRIPT staan er nog twee dingen open die niet in de database zitten:
--  `aalst.pokerleague.be` in Vercel → Settings → Domains, en het CNAME-record
--  `aalst` bij EasyHost. Allebei verwijderen.
-- ===========================================================================

do $$
declare
  ---------------------------------------------------------------------------
  c_echt_doen boolean := false;   -- << ZET DIT OP true OM ECHT OP TE RUIMEN
  ---------------------------------------------------------------------------

  c_weg   text := 'aalst';    -- deze club verdwijnt volledig
  c_leeg  text := 'cutoff';   -- deze club wordt leeggemaakt maar blijft bestaan

  v_weg   uuid;
  v_leeg  uuid;
  v_n     int;
begin
  select id into v_weg  from clubs where slug = c_weg;
  select id into v_leeg from clubs where slug = c_leeg;

  -- ----------------------------------------------------------------- kijken
  raise notice '--- wat er nu staat ---';

  if v_weg is null then
    raise notice '%: bestaat niet (meer). Niets te verwijderen.', c_weg;
  else
    raise notice '%: % avonden, % uitslagen, % leden, % medewerkers, % structuren, % seizoenen.',
      c_weg,
      (select count(*) from tournaments       where club_id = v_weg),
      (select count(*) from tournament_results where club_id = v_weg),
      (select count(*) from club_players      where club_id = v_weg),
      (select count(*) from club_members      where club_id = v_weg),
      (select count(*) from blind_structures  where club_id = v_weg),
      (select count(*) from seasons           where club_id = v_weg);
  end if;

  if v_leeg is null then
    raise notice '%: bestaat niet. Controleer de slug bovenaan dit bestand.', c_leeg;
  else
    raise notice '%: % avonden, % uitslagen, % inkopen, % inschrijvingen, % leden, % uitnodigingen, % aanvragen.',
      c_leeg,
      (select count(*) from tournaments             where club_id = v_leeg),
      (select count(*) from tournament_results      where club_id = v_leeg),
      (select count(*) from buyins                  where club_id = v_leeg),
      (select count(*) from tournament_registrations where club_id = v_leeg),
      (select count(*) from club_players            where club_id = v_leeg),
      (select count(*) from player_invites          where club_id = v_leeg),
      (select count(*) from player_signups          where club_id = v_leeg);
  end if;

  raise notice 'Spelersprofielen op het hele platform: %.', (select count(*) from players);

  if not c_echt_doen then
    raise notice '---';
    raise notice 'PROEFDRAAI. Er is NIETS verwijderd.';
    raise notice 'Zet c_echt_doen op true en draai dit bestand opnieuw.';
    return;
  end if;

  -- ----------------------------------------------------------------- doen
  -- De volgorde ligt vast. Eerst overal de tornooien: daar hangen via cascade
  -- de deelnames, inkopen, uitschakelingen, inschrijvingen, deals en uitslagen
  -- aan. Pas daarna de spelers, want `tournament_results` verwijst met
  -- `on delete restrict` naar `players` — met opzet, zodat je nooit een speler
  -- wist waar nog een uitslag aan hangt. En de club zelf helemaal op het
  -- einde, anders botst diezelfde regel op de cascade.

  if v_weg is not null then
    delete from tournaments    where club_id = v_weg;
    delete from player_invites where club_id = v_weg;
    delete from player_signups where club_id = v_weg;
    delete from club_players   where club_id = v_weg;
  end if;

  if v_leeg is not null then
    delete from tournaments    where club_id = v_leeg;
    delete from player_invites where club_id = v_leeg;
    delete from player_signups where club_id = v_leeg;
    delete from club_players   where club_id = v_leeg;
  end if;

  -- Spelers die nu nergens meer bij horen. Wie nog bij een andere club lid is
  -- of nog ergens een uitslag heeft staan, blijft bestaan.
  delete from players p
   where not exists (select 1 from club_players cp       where cp.player_id = p.id)
     and not exists (select 1 from tournament_results r  where r.player_id  = p.id)
     and not exists (select 1 from tournament_players tp where tp.player_id = p.id);
  get diagnostics v_n = row_count;
  raise notice '% spelersprofielen verwijderd.', v_n;

  -- En dan de club die weg moet. Medewerkers, structuren, niveaus,
  -- uitbetalingsschema's, seizoenen, puntensystemen, het auditspoor en de
  -- facturatieregel hangen er met een cascade aan en gaan vanzelf mee.
  if v_weg is not null then
    delete from clubs where id = v_weg;
    raise notice 'Club % is verwijderd.', c_weg;
  end if;

  -- Eén ding kan hier stilletjes misgaan en het is meteen het vervelendste:
  -- een club zonder medewerkers. Dan bestaat de omgeving nog maar kan niemand
  -- er nog in, en dat merk je pas als je aan de deur staat.
  if v_leeg is not null then
    select count(*) into v_n from club_members where club_id = v_leeg;
    if v_n = 0 then
      raise warning 'LET OP: % heeft geen enkele medewerker meer. Niemand kan de clubomgeving nog openen. Voeg jezelf toe met medewerker_toevoegen.sql.', c_leeg;
    else
      raise notice '% heeft nog % medewerker(s) met toegang.', c_leeg, v_n;
    end if;
  end if;

  raise notice '---';
  raise notice 'Klaar. Kijk hieronder na of alles op nul staat.';
end $$;

-- ===========================================================================
--  H E T   O O R D E E L
-- ===========================================================================
-- Eén regel. Staat er "LEEG", dan is het gelukt. Staat er iets anders, dan
-- staat er nog iets en zegt de kolom ernaast wat.

select
  case
    when (select count(*) from clubs where slug = 'aalst') > 0
      then 'AALST STAAT ER NOG'
    when (select count(*) from tournaments t join clubs c on c.id = t.club_id
          where c.slug = 'cutoff') > 0
      then 'CUTOFF HEEFT NOG AVONDEN'
    when (select count(*) from club_players cp join clubs c on c.id = cp.club_id
          where c.slug = 'cutoff') > 0
      then 'CUTOFF HEEFT NOG LEDEN'
    when (select count(*) from players) > 0
      then 'ER STAAN NOG SPELERSPROFIELEN'
    else 'LEEG'
  end as oordeel,
  (select count(*) from clubs)                                as clubs_over,
  (select count(*) from tournaments)                          as avonden_over,
  (select count(*) from players)                              as spelers_over,
  (select count(*) from tournament_results)                   as uitslagen_over,
  (select count(*) from buyins)                               as inkopen_over;

-- Wat er van Cutoff overblijft, en dat hoort er te zijn.
select
  (select count(*) from club_members m      join clubs c on c.id = m.club_id  where c.slug = 'cutoff') as medewerkers,
  (select count(*) from blind_structures s  join clubs c on c.id = s.club_id  where c.slug = 'cutoff') as structuren,
  (select count(*) from payout_templates p  join clubs c on c.id = p.club_id  where c.slug = 'cutoff') as uitbetalingen,
  (select count(*) from seasons se          join clubs c on c.id = se.club_id where c.slug = 'cutoff') as seizoenen;

-- Wie er nog toegang heeft tot de clubomgeving. Hier hoor jij in te staan.
select c.name as club, u.email, m.role
from club_members m
join clubs c      on c.id = m.club_id
join auth.users u on u.id = m.user_id
order by c.name, m.role, u.email;

-- De accounts blijven bestaan; die haalt dit bestand niet weg. Wil je er
-- eentje echt weg, dan doe je dat in Supabase → Authentication → Users.
select count(*) as accounts_in_auth from auth.users;
