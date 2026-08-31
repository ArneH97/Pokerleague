-- Pokerleague — Aalst Poker Club volledig verwijderen
--
-- Aalst doet niet mee. Dit haalt de club en alles wat eraan hangt uit de
-- database: haar avonden, uitslagen, geld, leden, uitnodigingen, aanvragen,
-- blindstructuren, seizoenen, de toegang van haar medewerkers en haar
-- facturatieregel.
--
-- Dit is ingrijpender dan `cutoff_leegmaken.sql`. Daar bleef de club bestaan;
-- hier gaat de rij in `clubs` zelf weg en ruimt de database via de
-- cascade-regels de rest op. Terugdraaien kan niet — er is op dit plan alleen
-- een dagelijkse back-up.
--
-- Wat NIET verdwijnt:
--
--   * Johans account zelf. Dat staat in `auth.users` en hoort bij hem, niet
--     bij de club. Alleen zijn rol bij Aalst gaat weg, en daarmee zijn
--     toegang tot de clubomgeving. Wil je het account ook echt weg, doe dat
--     dan met de hand in Supabase → Authentication → Users.
--   * Spelers die óók bij een andere club spelen. Zij verliezen alleen hun
--     lidmaatschap bij Aalst.
--
-- HOE GEBRUIK JE DIT
--
--   1. Draai het bestand zoals het is. Er verdwijnt nog niets — je krijgt te
--      zien wát er zou verdwijnen.
--   2. Klopt dat, zet `c_echt_doen` op `true` en draai het opnieuw.
--
-- NA DIT SCRIPT staan er nog twee dingen open die niet in de database zitten:
--
--   * `aalst.pokerleague.be` in Vercel → Settings → Domains → verwijderen.
--   * het CNAME-record `aalst` bij EasyHost → verwijderen.
--
-- Zolang die twee blijven staan, komt iemand die het adres kent op een
-- 404 uit. Dat is niet gevaarlijk, maar het is ook niet netjes.

do $$
declare
  -- Zet dit op true om echt te verwijderen.
  c_echt_doen boolean := false;
  c_slug      text    := 'aalst';

  v_club uuid;
  v_tour int; v_res int; v_link int; v_staf int; v_inv int; v_sign int;
  v_struct int; v_seas int; v_pl int;
begin
  select id into v_club from clubs where slug = c_slug;
  if v_club is null then
    raise notice 'Er is geen club met slug %. Niets te doen.', c_slug;
    return;
  end if;

  select count(*) into v_tour   from tournaments       where club_id = v_club;
  select count(*) into v_res    from tournament_results where club_id = v_club;
  select count(*) into v_link   from club_players      where club_id = v_club;
  select count(*) into v_staf   from club_members      where club_id = v_club;
  select count(*) into v_inv    from player_invites    where club_id = v_club;
  select count(*) into v_sign   from player_signups    where club_id = v_club;
  select count(*) into v_struct from blind_structures  where club_id = v_club;
  select count(*) into v_seas   from seasons           where club_id = v_club;

  raise notice 'Bij %: % avonden, % uitslagen, % leden, % medewerkers, % uitnodigingen, % aanvragen, % structuren, % seizoenen.',
    c_slug, v_tour, v_res, v_link, v_staf, v_inv, v_sign, v_struct, v_seas;

  if not c_echt_doen then
    raise notice 'PROEFDRAAI — er is niets verwijderd. Zet c_echt_doen op true en draai opnieuw.';
    return;
  end if;

  -- Eerst de avonden, want `tournament_results` verwijst met `on delete
  -- restrict` naar `players`. Zouden we de club in één keer weghalen, dan
  -- botst die regel en breekt het script halverwege af.
  delete from tournaments   where club_id = v_club;
  delete from player_invites where club_id = v_club;
  delete from player_signups where club_id = v_club;
  delete from club_players  where club_id = v_club;

  -- Spelers die nu nergens meer bij horen.
  delete from players p
   where not exists (select 1 from club_players cp       where cp.player_id = p.id)
     and not exists (select 1 from tournament_results r  where r.player_id  = p.id)
     and not exists (select 1 from tournament_players tp where tp.player_id = p.id);
  get diagnostics v_pl = row_count;

  -- En dan de club zelf. Staf, structuren, niveaus, uitbetalingsschema's,
  -- seizoenen, puntensystemen en de facturatieregel hangen er met een
  -- cascade aan en gaan vanzelf mee.
  delete from clubs where id = v_club;

  raise notice 'Weg: de club %, met % avonden, % leden, % medewerkers en % spelersprofielen.',
    c_slug, v_tour, v_link, v_staf, v_pl;
  raise notice 'Denk nog aan het subdomein in Vercel en het CNAME-record bij EasyHost.';
end $$;

-- Wat er overblijft aan clubs, en wie er nog ergens toegang toe heeft.
select slug, name, city, is_active from clubs order by name;

select c.name as club, u.email, m.role
from club_members m
join clubs c      on c.id = m.club_id
join auth.users u on u.id = m.user_id
order by c.name, m.role, u.email;

-- Johans account bestaat hierna nog, zonder club. Wil je het echt weg:
-- Supabase → Authentication → Users → zoek johanlooyens@icloud.com → Delete.
select id, email
from auth.users
where lower(email) = 'johanlooyens@icloud.com';
