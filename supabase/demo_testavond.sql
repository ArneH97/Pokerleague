-- Pokerleague — een tornooi dat nu meteen te testen is
--
-- Zet één avond klaar die middenin een echte situatie staat, zodat je alles
-- kan uitproberen zonder eerst twintig keer te klikken:
--
--   * de klok loopt, halverwege level 5 van de structuur
--   * 14 spelers ingeschreven, waarvan 9 al uitgeschakeld
--   * 5 spelers nog aan tafel, met verschillende stapels
--   * de late reg staat op level 3, dus de inkopen zijn gesloten en het
--     prijzengeldpaneel gaat meteen open zonder waarschuwing
--   * twee rebuys geboekt, zodat de pot niet gelijk is aan het aantal spelers
--   * één speler zonder mailadres, zodat je het oranje vlagje ziet
--
-- Daarmee kan je in één keer proberen: spelers toevoegen, rebuy en addon,
-- uitschakelen en terugdraaien, de prijzenverdeling met bubbel, en de deal
-- aan de finaletafel met vijf spelers.
--
-- Het tornooi heet "Demo Testavond", dus demo_cutoff_wissen.sql haalt het er
-- samen met de rest weer uit. Je mag dit bestand opnieuw draaien: het begint
-- met zichzelf op te ruimen.

do $$
declare
  v_club   uuid;
  v_season uuid;
  v_payout uuid;
  v_struct uuid;
  v_tour   uuid;
  v_tp     uuid;
  v_player uuid;
  v_winner uuid;
  v_tps    uuid[] := array[]::uuid[];
  v_namen  text[] := array[
    'Jan Peeters','Bart Verhoeven','Kevin De Smet','Nico Maes','Tom Willems',
    'Dries Janssens','Wouter Claes','Stijn Goossens','Koen Wouters','Filip Aerts',
    'Sofie De Backer','Leen Coppens','Kim Segers'
  ];
  v_mail   text;
  i        int;
  v_idx    int;
  v_pot    int;
begin
  select id into v_club from clubs where slug = 'cutoff';
  if v_club is null then
    raise exception 'Club cutoff bestaat niet. Draai eerst seed_cutoff.sql.';
  end if;

  delete from tournaments where club_id = v_club and name = 'Demo Testavond';

  select id into v_season from seasons
  where club_id = v_club and is_active order by starts_on desc limit 1;
  select id into v_payout from payout_templates
  where club_id = v_club or club_id is null order by club_id nulls last limit 1;
  select id into v_struct from blind_structures
  where club_id = v_club or club_id is null order by club_id nulls last limit 1;

  if v_struct is null then
    raise exception 'Geen blindstructuur gevonden. Maak er eerst een aan.';
  end if;

  insert into tournaments (
    club_id, season_id, payout_template_id, structure_id, name, scheduled_at,
    status, player_visibility,
    buyin_cents, fee_cents, rebuy_cents, rebuy_fee_cents,
    addon_cents, addon_fee_cents, addon_stack,
    bounty_mode, bounty_cents,
    starting_stack, max_reentries, late_reg_level,
    started_at, clock
  ) values (
    v_club, v_season, v_payout, v_struct, 'Demo Testavond', now() - interval '2 hours',
    'running'::tournament_status, 'public'::visibility,
    2000, 500, 2000, 500,
    1000, 0, 30000,
    'none'::bounty_mode, 0,
    20000, 1, 3,
    now() - interval '2 hours', 'running'::clock_status
  )
  returning id into v_tour;

  -- ------------------------------------------------------------- spelers ---
  for i in 1 .. array_length(v_namen, 1) loop
    -- Bestaat deze speler al bij Cutoff, dan pakken we hem; anders maken we
    -- er een met een demo-adres zodat het opruimscript hem terugvindt.
    select p.id into v_player
    from players p
    join club_players cp on cp.player_id = p.id and cp.club_id = v_club
    where p.display_name = v_namen[i] and p.merged_into_id is null
    limit 1;

    if v_player is null then
      v_mail := lower(regexp_replace(
        translate(v_namen[i], ' éèêëïîôûüàç', '.eeeeiiouuac'), '[^a-zA-Z.]', '', 'g'))
        || '@demo.pokerleague.be';
      v_tp := public.floor_add_entry(v_tour, null, v_namen[i], v_mail);
    else
      v_tp := public.floor_add_entry(v_tour, v_player);
    end if;

    v_tps := v_tps || v_tp;
  end loop;

  -- Eén speler zonder mailadres, precies zoals iemand die aan de deur zegt
  -- dat hij het niet uit het hoofd kent.
  v_tp := public.floor_add_entry(v_tour, null, 'Marcel Vandeputte', null,
                                 'Kent het niet uit het hoofd');
  v_tps := v_tps || v_tp;

  -- Twee rebuys, zodat de pot niet zomaar het aantal spelers maal de buy-in is.
  perform public.floor_rebuy(v_tps[2], 'rebuy');
  perform public.floor_rebuy(v_tps[7], 'rebuy');

  -- ---------------------------------------------------------- chipstanden ---
  -- Willekeurige getallen zetten leek onschuldig maar klopte niet: de som
  -- moet gelijk zijn aan wat er in spel is (elke inkoop legt een startstack
  -- op tafel). Anders staat de controle bij de deal meteen op 73% en lijkt
  -- er iets mis met de software terwijl het de demodata is.
  --
  -- Daarom: iedereen krijgt eerst een startstack, en daarna verschuiven we
  -- chips tussen spelers onderling. Zo blijft het totaal exact kloppen en
  -- zijn de stapels toch verschillend.
  for i in 1 .. array_length(v_tps, 1) loop
    update tournament_players set chip_count = 20000 where id = v_tps[i];
  end loop;

  -- De twee spelers met een rebuy hebben er een tweede stack bij liggen.
  update tournament_players set chip_count = chip_count + 20000
  where id in (v_tps[2], v_tps[7]);

  -- Wat schuiven: even spelers winnen van oneven spelers.
  for i in 1 .. array_length(v_tps, 1) - 1 by 2 loop
    update tournament_players set chip_count = chip_count - (3000 + (i * 1300) % 9000)
    where id = v_tps[i];
    update tournament_players set chip_count = chip_count + (3000 + (i * 1300) % 9000)
    where id = v_tps[i + 1];
  end loop;

  -- ------------------------------------------------------- uitschakelen ---
  -- Negen spelers eruit; vijf blijven er zitten. De server bepaalt de
  -- plaatsen, dus de eindstand klopt straks gewoon. De chips van wie afvalt
  -- gaan naar de grootste stapel aan tafel — zo verdwijnen ze niet uit het
  -- spel en klopt het totaal op het einde nog altijd.
  for i in 1 .. 9 loop
    select tp.id into v_tp
    from tournament_players tp
    where tp.tournament_id = v_tour and tp.status in ('active','registered')
    order by tp.chip_count asc, tp.registered_at asc
    limit 1;

    select tp2.id into v_winner
    from tournament_players tp2
    where tp2.tournament_id = v_tour and tp2.status in ('active','registered')
      and tp2.id <> v_tp
    order by tp2.chip_count desc limit 1;

    update tournament_players
    set chip_count = chip_count
      + (select coalesce(chip_count, 0) from tournament_players where id = v_tp)
    where id = v_winner;

    update tournament_players set chip_count = 0 where id = v_tp;

    perform public.floor_eliminate(v_tp, v_winner);
  end loop;

  -- --------------------------------------------------------------- klok ---
  -- Op het vijfde speellevel van de structuur, twaalf minuten bezig. De late
  -- reg stond op level 3, dus de inkopen zijn gesloten: het zaalscherm toont
  -- "rebuys closed" en het prijzengeld is meteen vast te leggen.
  select bl.idx into v_idx
  from (
    select idx, row_number() over (order by idx) as n
    from blind_levels
    where structure_id = v_struct and not is_break
  ) bl
  where bl.n = 5;

  update tournaments
  set level_idx        = coalesce(v_idx, 4),
      level_started_at = now() - interval '12 minutes',
      level_elapsed_ms = 0,
      clock            = 'running'
  where id = v_tour;

  select coalesce(sum(amount_cents), 0) into v_pot
  from buyins where tournament_id = v_tour and not is_void;

  raise notice 'Testavond klaar: 14 spelers, 5 nog aan tafel, pot % cent.', v_pot;
end $$;

-- Waar je moet zijn.
select
  t.name,
  t.status,
  '/c/' || c.slug || '/floor/' || t.id as floor_scherm,
  '/c/' || c.slug || '/klok/'  || t.id as zaalscherm,
  (select count(*) from tournament_players tp where tp.tournament_id = t.id) as spelers,
  (select count(*) from tournament_players tp
    where tp.tournament_id = t.id and tp.status = 'active')                  as nog_aan_tafel,
  (select coalesce(sum(b.amount_cents), 0) from buyins b
    where b.tournament_id = t.id and not b.is_void)                          as pot_cent
from tournaments t
join clubs c on c.id = t.club_id
where t.name = 'Demo Testavond';
