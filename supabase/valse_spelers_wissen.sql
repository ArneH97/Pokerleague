-- Pokerleague — verzonnen spelers uit het ledenbestand halen
--
-- Voor de vier die tijdens het testen aan de deur zijn ingetikt en die nooit
-- echte mensen waren. Namen invullen bovenaan het blok; alles daarna gaat
-- vanzelf.
--
-- **Er zit een drievoudig slot op.** Er wordt alleen iemand geraakt die
-- tegelijk aan drie voorwaarden voldoet: hij hoort bij Cutoff, hij heeft géén
-- mailadres, en hij heeft géén account. Een echt lid heeft altijd minstens één
-- van die twee — dus zelfs als er ooit een echte Dirk bij komt, blijft die
-- staan. Namen worden vergeleken zonder hoofdletters en zonder randspaties.
--
-- **Wie gespeeld heeft, wordt niet gewist.** De databank staat dat trouwens
-- ook niet toe: een speler met deelnames, inkopen of een uitslag zit vast aan
-- die avonden, en hem weghalen zou de uitslag en het klassement van een
-- gespeelde avond veranderen. Dit script kijkt dat vooraf na en zegt per
-- persoon wat er gebeurt in plaats van halverwege op een foutmelding te
-- stranden.
--
-- Voor wie wél gespeeld heeft is er `c_gespeelde_uit_club`: die haalt hem uit
-- het ledenbestand van Cutoff maar laat zijn profiel en zijn resultaten staan.
-- Standaard staat dat uit.
--
-- **Draai eerst alleen deel 1.**

-- ===========================================================================
-- DEEL 1 — wie het zijn en wat er aan hen hangt
-- ===========================================================================

select
  p.display_name                       as speler,
  coalesce(p.no_email_reason, '—')     as reden,
  p.link_state,
  (select count(*) from tournament_players       x where x.player_id = p.id) as deelnames,
  (select count(*) from tournament_results       x where x.player_id = p.id) as uitslagen,
  (select count(*) from buyins                   x where x.player_id = p.id) as inkopen,
  (select count(*) from tournament_registrations x where x.player_id = p.id) as inschrijvingen,
  p.id
from club_players cp
join clubs   c on c.id = cp.club_id
join players p on p.id = cp.player_id
where c.slug = 'cutoff'
  and p.email is null
  and p.auth_user_id is null
  and p.merged_into_id is null
order by p.display_name;

-- ===========================================================================
-- DEEL 2 — wissen
-- ===========================================================================

do $$
declare
  -- ------------------------------------------------------------- invullen
  c_slug  text   := 'cutoff';
  c_namen text[] := array['christian', 'dirk', 'jef', 'stef'];

  -- Wie wél gespeeld heeft: uit het ledenbestand halen (true) of met rust
  -- laten (false). Zijn profiel en zijn resultaten blijven hoe dan ook staan.
  c_gespeelde_uit_club boolean := false;
  -- -------------------------------------------------------------

  v_club uuid;
  v_gewist  int := 0;
  v_los     int := 0;
  v_blijft  int := 0;
  r         record;
begin
  select id into v_club from clubs where slug = c_slug;
  if v_club is null then
    raise exception 'Geen club met slug %.', c_slug;
  end if;

  for r in
    select p.id, p.display_name,
           (select count(*) from tournament_players       x where x.player_id = p.id)
         + (select count(*) from tournament_results       x where x.player_id = p.id)
         + (select count(*) from buyins                   x where x.player_id = p.id) as sporen,
           (select count(*) from tournament_registrations x where x.player_id = p.id) as insch
    from club_players cp
    join players p on p.id = cp.player_id
    where cp.club_id = v_club
      and p.email is null
      and p.auth_user_id is null
      and p.merged_into_id is null
      and lower(trim(p.display_name)) = any (
            select lower(trim(n)) from unnest(c_namen) n)
    order by p.display_name
  loop
    if r.sporen = 0 then
      -- Niets gespeeld: het profiel mag helemaal weg. Inschrijvingen en
      -- openstaande uitnodigingen gaan mee (die staan op cascade).
      delete from players where id = r.id;
      v_gewist := v_gewist + 1;
      raise notice 'Gewist: "%" — had niets gespeeld%.',
        r.display_name,
        case when r.insch > 0 then format(' (%s inschrijving(en) gingen mee)', r.insch) else '' end;

    elsif c_gespeelde_uit_club then
      delete from club_players where club_id = v_club and player_id = r.id;
      v_los := v_los + 1;
      raise notice 'Uit het ledenbestand: "%" — heeft % ding(en) gespeeld, dus profiel en resultaten blijven staan.',
        r.display_name, r.sporen;

    else
      v_blijft := v_blijft + 1;
      raise notice 'BLIJFT: "%" — heeft % ding(en) gespeeld. Wissen zou een gespeelde avond veranderen.',
        r.display_name, r.sporen;
    end if;
  end loop;

  if v_gewist + v_los + v_blijft = 0 then
    raise notice 'Niemand gevonden. Ofwel staan ze er niet meer, ofwel heeft er intussen eentje een mailadres gekregen — kijk in deel 1.';
  end if;

  raise notice '---';
  raise notice '% profiel(en) gewist, % uit het ledenbestand gehaald, % ongemoeid gelaten.',
    v_gewist, v_los, v_blijft;
  if v_blijft > 0 then
    raise notice 'Wil je die laatste toch uit de ledenlijst (met behoud van hun resultaten), zet c_gespeelde_uit_club op true en draai opnieuw.';
  end if;
end $$;

-- ===========================================================================
-- DEEL 3 — nakijken
-- ===========================================================================
-- Wie er nu nog zonder mailadres in het ledenbestand van Cutoff staat.

select
  p.display_name                   as speler,
  coalesce(p.no_email_reason, '—') as reden,
  (select count(*) from tournament_players x where x.player_id = p.id) as deelnames
from club_players cp
join clubs   c on c.id = cp.club_id
join players p on p.id = cp.player_id
where c.slug = 'cutoff'
  and p.email is null
  and p.auth_user_id is null
  and p.merged_into_id is null
order by p.display_name;
