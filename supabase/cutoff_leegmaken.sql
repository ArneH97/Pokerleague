-- Pokerleague — Cutoff leegmaken voor de setup met de club
--
-- Haalt alle tornooien, uitslagen, inkopen en het hele ledenbestand van Cutoff
-- weg. Demogegevens én wat je zelf hebt ingetikt tijdens het testen — dit maakt
-- geen onderscheid, en dat is precies de bedoeling: je gaat morgen met hen aan
-- tafel en dan moet er niets staan dat niet van hen is.
--
-- Wat BLIJFT staan, en dat is met opzet:
--
--   * de club zelf, met logo, kleuren, adres, speeldag en instellingen
--   * de staf (club_members) — anders sluit je jezelf buiten
--   * de blindstructuren, de prijzenverdelingen en het puntensysteem
--   * de seizoenen
--
-- Dat is de configuratie die je morgen níét opnieuw wil intikken. Weg gaat
-- alles wat een avond of een speler is.
--
-- De volgorde is niet vrijblijvend. Eerst de tornooien: daar hangen via cascade
-- de deelnames, inkopen, uitschakelingen, inschrijvingen, deals en uitslagen
-- aan. Pas daarna de spelers, want `tournament_results` verwijst met
-- `on delete restrict` naar `players` — met opzet, zodat je nooit een speler
-- wist waar nog een uitslag aan hangt.
--
-- Spelers die óók bij een andere club spelen blijven bestaan; alleen hun
-- lidmaatschap bij Cutoff verdwijnt. Sinds Aalst erbij is, is dat geen
-- theoretisch geval meer.
--
-- HOE GEBRUIK JE DIT
--
--   1. Draai het bestand zoals het is. Er wordt dan nog niets verwijderd —
--      je krijgt te zien wát er zou verdwijnen.
--   2. Klopt dat, zet `c_echt_doen` op `true` en draai het opnieuw.
--
-- Die tussenstap staat er met opzet in. Dit gooit gegevens weg in de echte
-- database en er is op dit plan geen herstelpunt van vijf minuten geleden —
-- alleen een dagelijkse back-up.

do $$
declare
  -- Zet dit op true om echt te verwijderen.
  c_echt_doen boolean := false;
  c_slug      text    := 'cutoff';

  v_club uuid;
  v_tour int; v_res int; v_buy int; v_link int; v_inv int; v_sign int; v_pl int;
begin
  select id into v_club from clubs where slug = c_slug;
  if v_club is null then
    raise exception 'Geen club met slug %.', c_slug;
  end if;

  -- Eerst tellen wat er is. Ook in de echte doorloop, zodat de melding
  -- achteraf zegt wát er weg is en niet alleen dát er iets weg is.
  select count(*) into v_tour from tournaments      where club_id = v_club;
  select count(*) into v_res  from tournament_results where club_id = v_club;
  select count(*) into v_buy  from buyins           where club_id = v_club;
  select count(*) into v_link from club_players     where club_id = v_club;
  select count(*) into v_inv  from player_invites   where club_id = v_club;
  select count(*) into v_sign from player_signups   where club_id = v_club;

  raise notice 'Bij %: % avonden, % uitslagen, % inkopen, % leden, % uitnodigingen, % aanvragen.',
    c_slug, v_tour, v_res, v_buy, v_link, v_inv, v_sign;

  if not c_echt_doen then
    raise notice 'PROEFDRAAI — er is niets verwijderd. Zet c_echt_doen op true en draai opnieuw.';
    return;
  end if;

  -- 1. De avonden. Cascade ruimt deelnames, geld, knock-outs, inschrijvingen,
  --    deals en uitslagen op.
  delete from tournaments where club_id = v_club;

  -- 2. Openstaande uitnodigingen en aanvragen om lid te worden. Die hangen aan
  --    de club en niet aan een avond, dus ze overleven stap 1. Blijven ze
  --    staan, dan begint de club morgen met een lijstje aanvragen van mensen
  --    die er tijdens het testen zijn ingezet.
  delete from player_invites  where club_id = v_club;
  delete from player_signups  where club_id = v_club;

  -- 3. Het ledenbestand van deze club.
  delete from club_players where club_id = v_club;

  -- 4. Spelersprofielen die daarna nergens meer bij horen. Wie nog bij een
  --    andere club lid is, of nog ergens een uitslag of een deelname heeft
  --    staan, blijft bestaan.
  delete from players p
   where not exists (select 1 from club_players cp       where cp.player_id = p.id)
     and not exists (select 1 from tournament_results r  where r.player_id  = p.id)
     and not exists (select 1 from tournament_players tp where tp.player_id = p.id);
  get diagnostics v_pl = row_count;

  raise notice 'Leeggemaakt: % avonden, % leden, % uitnodigingen, % aanvragen, % spelersprofielen.',
    v_tour, v_link, v_inv, v_sign, v_pl;
  raise notice 'Blijven staan: de club, de staf, de structuren, de uitbetalingen en de seizoenen.';
end $$;

-- Controle. De eerste vier hoken op nul, de laatste drie niet.
select
  (select count(*) from tournaments t        join clubs c on c.id = t.club_id  where c.slug = 'cutoff') as avonden,
  (select count(*) from club_players cp      join clubs c on c.id = cp.club_id where c.slug = 'cutoff') as leden,
  (select count(*) from tournament_results r join clubs c on c.id = r.club_id  where c.slug = 'cutoff') as uitslagen,
  (select count(*) from buyins b             join clubs c on c.id = b.club_id  where c.slug = 'cutoff') as inkopen,
  (select count(*) from club_members m       join clubs c on c.id = m.club_id  where c.slug = 'cutoff') as staf_blijft,
  (select count(*) from blind_structures s   join clubs c on c.id = s.club_id  where c.slug = 'cutoff') as structuren_blijven,
  (select count(*) from seasons se           join clubs c on c.id = se.club_id where c.slug = 'cutoff') as seizoenen_blijven;

-- En wie er morgen nog toegang heeft tot de clubomgeving.
select u.email, m.role
from club_members m
join clubs c      on c.id = m.club_id
join auth.users u on u.id = m.user_id
where c.slug = 'cutoff'
order by m.role, u.email;
