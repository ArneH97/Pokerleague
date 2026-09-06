-- Pokerleague — het testtornooi bij Cutoff opruimen
--
-- Weg mag: het tornooi dat letterlijk 'test' heet, met alles wat eraan hangt —
-- de deelnames, de inkopen, de uitschakelingen, de inschrijvingen, de tafels en
-- de uitslag. Dat gaat vanzelf mee: alle tabellen die naar een tornooi wijzen
-- staan op `on delete cascade`. Eén regel weg is alles weg.
--
-- Blijven staan: de grand opening en haar inschrijvingen. Dat is niet alleen
-- een belofte in een commentaar — het script telt de inschrijvingen van álle
-- andere tornooien vóór en na het verwijderen, en draait alles terug als dat
-- getal ook maar één verschilt. Liever een script dat weigert dan een avond die
-- weg is.
--
-- **Draai eerst alleen deel 1.** Dat print de tornooien van Cutoff met hun naam
-- tussen aanhalingstekens, zodat je spaties aan het begin of het einde ziet.
-- Klopt de lijst, draai dan de rest.
--
-- **Twee knoppen bovenaan het blok:**
--   c_naam        welke naam eruit moet. Exact, maar hoofdletters en spaties
--                 aan de randen doen er niet toe: 'Test ' vindt 'test'.
--   c_ook_spelers wat er met de gastspelers moet die je voor de test aanmaakte.
--                 Op `false` blijven ze staan (alleen hun deelname is weg). Op
--                 `true` gaan ze weg — maar alleen als ze aan geen enkel ander
--                 tornooi meegedaan hebben, geen account hebben en nooit
--                 geclaimd zijn. Wie ook maar iets van die drie is, blijft.

-- ===========================================================================
-- DEEL 1 — kijken. Verandert niets.
-- ===========================================================================

select
  '"' || t.name || '"'                                  as naam,
  t.status,
  to_char(t.scheduled_at, 'dd/mm/yyyy HH24:MI')         as gepland,
  (select count(*) from tournament_players  x where x.tournament_id = t.id) as deelnames,
  (select count(*) from tournament_registrations x where x.tournament_id = t.id) as inschrijvingen,
  (select count(*) from buyins              x where x.tournament_id = t.id) as inkopen,
  t.id
from tournaments t
join clubs c on c.id = t.club_id
where c.slug = 'cutoff'
order by t.scheduled_at;

-- ===========================================================================
-- DEEL 2 — opruimen. Pas draaien als de lijst hierboven klopt.
-- ===========================================================================

do $$
declare
  c_slug        text    := 'cutoff';
  c_naam        text    := 'test';
  c_ook_spelers boolean := false;

  v_club        uuid;
  v_weg         uuid[];
  v_alles       int;
  v_insch_voor  int;
  v_insch_na    int;
  v_spelers     int;
  v_struct      int;
  r             record;
begin
  select id into v_club from clubs where slug = c_slug;
  if v_club is null then
    raise exception 'Geen club met slug %.', c_slug;
  end if;

  -- Exact deze naam. Niet 'testavond', niet 'Test 2' — alleen wie na het
  -- wegstrepen van hoofdletters en randspaties precies 'test' heet.
  select array_agg(t.id) into v_weg
  from tournaments t
  where t.club_id = v_club and lower(trim(t.name)) = lower(trim(c_naam));

  if v_weg is null then
    raise exception 'Geen tornooi bij % met de naam "%". Kijk in deel 1 hoe het écht heet.',
      c_slug, c_naam;
  end if;

  select count(*) into v_alles from tournaments where club_id = v_club;
  if array_length(v_weg, 1) >= v_alles then
    raise exception 'Dit zou álle % tornooien van % wissen. Geweigerd.', v_alles, c_slug;
  end if;

  -- Wat er weggaat, hardop, mét de aantallen. Zo staat het in je logboek ook
  -- als je het achteraf nog eens wil nakijken.
  for r in
    select t.id, t.name, t.status, t.scheduled_at,
           (select count(*) from tournament_players x where x.tournament_id = t.id) as spelers,
           (select count(*) from tournament_registrations x where x.tournament_id = t.id) as insch,
           (select count(*) from buyins x where x.tournament_id = t.id) as inkopen
    from tournaments t where t.id = any (v_weg) order by t.scheduled_at
  loop
    raise notice 'Weg: "%" (%, %) — % deelnames, % inschrijvingen, % inkopen.',
      r.name, r.status, to_char(r.scheduled_at, 'dd/mm/yyyy'), r.spelers, r.insch, r.inkopen;
  end loop;

  -- En wat er blijft, zodat je de grand opening met eigen ogen ziet staan.
  for r in
    select t.name, t.status,
           (select count(*) from tournament_registrations x where x.tournament_id = t.id) as insch
    from tournaments t
    where t.club_id = v_club and not (t.id = any (v_weg)) order by t.scheduled_at
  loop
    raise notice 'Blijft: "%" (%) — % inschrijvingen.', r.name, r.status, r.insch;
  end loop;

  -- Het vangnet. Alles wat níet weg mag, geteld vóór het verwijderen.
  select count(*) into v_insch_voor
  from tournament_registrations x
  join tournaments t on t.id = x.tournament_id
  where t.club_id = v_club and not (t.id = any (v_weg));

  delete from tournaments where id = any (v_weg);

  select count(*) into v_insch_na
  from tournament_registrations x
  join tournaments t on t.id = x.tournament_id
  where t.club_id = v_club;

  if v_insch_na <> v_insch_voor then
    raise exception 'De inschrijvingen van de andere tornooien gingen van % naar %. Alles teruggedraaid.',
      v_insch_voor, v_insch_na;
  end if;
  raise notice 'OK  % inschrijvingen van de andere tornooien staan er nog, alle %.',
    v_insch_na, v_insch_voor;

  -- Had die avond een eigen kopie van de blindstructuur (die maakt het systeem
  -- aan zodra je tijdens het spelen aan de levels komt), dan hangt die nu
  -- nergens meer aan. Clubsjablonen blijven, die hebben geen tornooi nodig.
  delete from blind_structures bs
  where bs.club_id = v_club
    and bs.description like 'Eigen structuur van deze avond%'
    and not exists (select 1 from tournaments t where t.structure_id = bs.id);
  get diagnostics v_struct = row_count;
  if v_struct > 0 then
    raise notice 'OK  % losgeraakte kopie(ën) van de blindstructuur opgeruimd.', v_struct;
  end if;

  -- ---------------------------------------------------------------- spelers
  if c_ook_spelers then
    with wees as (
      select p.id
      from players p
      join club_players cp on cp.player_id = p.id and cp.club_id = v_club
      where p.auth_user_id is null
        and p.link_state <> 'claimed'
        and p.merged_into_id is null
        and not exists (select 1 from tournament_players tp where tp.player_id = p.id)
        and not exists (select 1 from tournament_registrations tr where tr.player_id = p.id)
    )
    delete from players p using wees w where p.id = w.id;
    get diagnostics v_spelers = row_count;
    raise notice 'OK  % gastspeler(s) zonder account en zonder enige andere deelname opgeruimd.', v_spelers;
  else
    select count(*) into v_spelers
    from players p
    join club_players cp on cp.player_id = p.id and cp.club_id = v_club
    where p.auth_user_id is null
      and p.link_state <> 'claimed'
      and p.merged_into_id is null
      and not exists (select 1 from tournament_players tp where tp.player_id = p.id)
      and not exists (select 1 from tournament_registrations tr where tr.player_id = p.id);
    if v_spelers > 0 then
      raise notice 'Er staan nu % gastspeler(s) bij % die aan niets meer meedoen. Wil je die ook weg, zet c_ook_spelers op true en draai opnieuw.',
        v_spelers, c_slug;
    end if;
  end if;

  raise notice 'Klaar.';
end $$;

-- ===========================================================================
-- DEEL 3 — nakijken. Dit hoort alleen nog de echte avonden te tonen.
-- ===========================================================================

select
  '"' || t.name || '"'                          as naam,
  t.status,
  to_char(t.scheduled_at, 'dd/mm/yyyy HH24:MI') as gepland,
  (select count(*) from tournament_players  x where x.tournament_id = t.id) as deelnames,
  (select count(*) from tournament_registrations x where x.tournament_id = t.id) as inschrijvingen
from tournaments t
join clubs c on c.id = t.club_id
where c.slug = 'cutoff'
order by t.scheduled_at;
