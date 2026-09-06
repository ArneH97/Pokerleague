-- Pokerleague — een tweede floor toevoegen bij Cutoff
--
-- **Eerst dit: hij maakt zelf een account.** Op pokerleague.be/registreren, met
-- het e-mailadres dat je hieronder invult, en hij bevestigt de mail die hij
-- krijgt. Eén account volstaat: daarmee is hij speler op het platform én floor
-- bij Cutoff. Bestaat het account nog niet, dan doet dit script niets en zegt
-- het dat — dan laat je hem registreren en draai je het opnieuw.
--
-- **De vier rollen.**
--
--   owner   alles, inclusief de clubinstellingen en het aanstellen van andere
--           medewerkers.
--   admin   in de code vandaag identiek aan owner. Er is geen enkele controle
--           die alleen owner toelaat — het verschil is voorlopig hoe het leest,
--           niet wat het mag.
--   floor   de hele avond, en niets daarbuiten. Zie hieronder.
--   viewer  meekijken, niets wijzigen.
--
-- **Wat een floor mag:** een tornooi aanmaken en bijstellen, spelers toevoegen
-- en verwijderen, inschrijvingen afhandelen, de klok starten en pauzeren, de
-- komende levels aanpassen en er eentje bijzetten als het uitloopt, rebuys en
-- addons, chipcounts invullen en bevriezen, tafels openen en sluiten, seaten en
-- herseaten, deals, de uitbetaling en het afsluiten van de avond.
--
-- **Wat een floor niet mag:** de clubinstellingen en de huisstijl, andere
-- medewerkers aanstellen, een blindstructuur aanmaken of bewerken buiten een
-- lopende avond om, prijzensjablonen, de puntentelling en de seizoenen.
--
-- Wil je iemand die écht alles kan wat jij kan — dus ook de instellingen en het
-- aanstellen van een derde — zet `c_role` dan op 'admin'.
--
-- Twee keer draaien doet niets dubbel: bestaat de rol al, dan wordt ze
-- bijgewerkt naar wat er hieronder staat.

do $$
declare
  -- ------------------------------------------------------------- invullen
  c_slug  text := 'cutoff';
  c_email text := 'julien.sterckx@gmail.com';
  c_role  text := 'admin';          -- 'owner' | 'admin' | 'floor' | 'viewer'

  -- Optioneel dubbelslot: het account-id zoals jij het in Supabase ziet. Staat
  -- hier iets anders dan wat er op dat e-mailadres gevonden wordt, dan stopt
  -- het script. Zo kan een typefout in het adres nooit de verkeerde persoon
  -- rechten geven. Laat leeg (null) als je het niet weet.
  c_verwacht_id uuid := '31de78a2-2088-4aa9-9306-9372e3c6f048';
  -- -------------------------------------------------------------

  v_club     uuid;
  v_user     uuid;
  v_bevest   timestamptz;
  v_oud      club_role;
  v_naam     text;
begin
  if c_email = 'vul.hier@in.be' then
    raise exception 'Vul eerst het e-mailadres in bovenaan het blok.';
  end if;

  if c_role not in ('owner', 'admin', 'floor', 'viewer') then
    raise exception 'De rol "%" bestaat niet. Kies owner, admin, floor of viewer.', c_role;
  end if;

  select id into v_club from clubs where slug = c_slug;
  if v_club is null then
    raise exception 'Geen club met slug %.', c_slug;
  end if;

  -- Via to_jsonb in plaats van rechtstreeks u.email_confirmed_at: die kolom
  -- hoort bij Supabase' eigen authtabel en niet bij ons schema. Zo blijft dit
  -- script draaien ook als die tabel er ooit anders uitziet.
  select u.id, (to_jsonb(u) ->> 'email_confirmed_at')::timestamptz
    into v_user, v_bevest
  from auth.users u where lower(u.email) = lower(trim(c_email));

  if v_user is null then
    raise notice 'Nog geen account voor %.', c_email;
    raise notice 'Laat hem registreren op pokerleague.be/registreren met exact dat adres, en draai dit dan opnieuw.';
    return;
  end if;

  if c_verwacht_id is not null and v_user <> c_verwacht_id then
    raise exception 'Op % staat account %, maar er werd % verwacht. Niets gedaan.',
      c_email, v_user, c_verwacht_id;
  end if;

  if v_bevest is null then
    raise notice 'LET OP: % heeft zijn e-mailadres nog niet bevestigd. De rol wordt gezet, maar aanmelden lukt pas na het bevestigen.', c_email;
  end if;

  select display_name into v_naam from players
  where auth_user_id = v_user and merged_into_id is null;

  select role into v_oud from club_members where club_id = v_club and user_id = v_user;

  insert into club_members (club_id, user_id, role)
  values (v_club, v_user, c_role::club_role)
  on conflict (club_id, user_id) do update set role = excluded.role;

  if v_oud is null then
    raise notice 'OK  % (%) is nu % bij %.',
      coalesce(v_naam, '(nog geen profielnaam)'), c_email, c_role, c_slug;
  elsif v_oud::text = c_role then
    raise notice 'OK  % was al % bij %. Niets veranderd.', c_email, c_role, c_slug;
  else
    raise notice 'OK  % ging van % naar % bij %.', c_email, v_oud, c_role, c_slug;
  end if;

  -- Een floor die zelf meespeelt, hoort ook gewoon in de spelerslijst van de
  -- club te staan. Dat is losstaand van zijn rol en kost niets als het er al is.
  if exists (select 1 from players where auth_user_id = v_user and merged_into_id is null) then
    insert into club_players (club_id, player_id)
    select v_club, p.id from players p
    where p.auth_user_id = v_user and p.merged_into_id is null
    on conflict (club_id, player_id) do nothing;
  end if;

  raise notice 'Hij ziet Cutoff nu staan zodra hij zich opnieuw aanmeldt.';
end $$;

-- Wie er nu toegang heeft tot Cutoff, en met welke rol.
select
  u.email,
  m.role,
  coalesce(p.display_name, '—')                as profielnaam,
  case when (to_jsonb(u) ->> 'email_confirmed_at') is null
       then 'nog niet bevestigd' else 'ok' end as account,
  m.created_at::date                           as sinds
from club_members m
join clubs c       on c.id = m.club_id
join auth.users u  on u.id = m.user_id
left join players p on p.auth_user_id = u.id and p.merged_into_id is null
where c.slug = 'cutoff'
order by
  case m.role when 'owner' then 1 when 'admin' then 2 when 'floor' then 3 else 4 end,
  u.email;
