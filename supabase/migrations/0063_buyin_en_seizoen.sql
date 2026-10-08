-- Pokerleague — de buy-in weegt mee, en een klassement dat één competitie is
--
-- Drie dingen die bij elkaar horen, omdat ze alle drie over hetzelfde gaan:
-- een league waarin het klopt wat er op het spel staat.
--
-- ---------------------------------------------------------------------------
-- 1. Een avond van vijftig euro is niet dezelfde avond als een van dertig
-- ---------------------------------------------------------------------------
-- `sqrt_ratio` kende tot nu alleen de plaats en de veldgrootte. Twee avonden
-- met twintig spelers leverden exact hetzelfde op, of er nu dertig of vijftig
-- euro per inkoop op tafel lag. Voor een huisranking is dat prima. Voor een
-- league met een prijs aan het eind betekent het dat de goedkope zondagen
-- even zwaar wegen als de grote avonden, en dan is er geen reden meer om de
-- grote avond te spelen.
--
-- Er komt dus een derde factor bij:
--
--     punten = multiplier × √N ÷ plaats^exponent × (buyin ÷ ijkpunt)^gewicht
--
-- Met het ijkpunt op dertig euro en een gewicht van een halve — de wortel van
-- de verhouding — levert dat bij twintig spelers voor de winnaar:
--
--     €15 → 32     €30 → 45     €50 → 58     €100 → 82
--
-- Vijftig euro is dus 29 procent meer waard dan dertig. Genoeg om de grote
-- avond te laten tellen, te weinig om de goedkope avond zinloos te maken —
-- wie alleen de dertig-eurotornooien speelt, blijft meedoen voor de league.
-- Recht proportioneel wegen (gewicht 1) zou vijftig euro 67 procent meer
-- waard maken, en dan speelt de helft van de kalender niet meer mee.
--
-- De factor zit geklemd tussen een half en twee. Een eenmalig tornooi van
-- vijfhonderd euro hoort zwaarder te wegen dan een gewone avond, maar niet
-- zwaarder dan vier gewone avonden samen; anders beslist één zondag de hele
-- competitie.
--
-- Zonder `buyin_ref` in de parameters verandert er niets. Dat is niet
-- vriendelijkheid maar noodzaak: dit raakt de puntenformule van elke club die
-- het platform ooit gebruikt, en een telling die achteraf verschuift is geen
-- telling.
--
-- **Wat er als buy-in geldt:** het bedrag dat naar de pot gaat, per inkoop,
-- zonder rake. Niet wat er uiteindelijk in de pot lag — dan zou een avond met
-- veel rebuys zwaarder wegen dan hij aankondigde, en dat weet je pas achteraf.
-- Wie zijn tornooi aankondigt als "50 + 5" wordt hier dus op die 50 gewogen.
--
-- ---------------------------------------------------------------------------
-- 2. Een club mag zeggen dat er maar één klassement is
-- ---------------------------------------------------------------------------
-- Het klassementsscherm toont drie dingen: het seizoen, het jaar en de maand.
-- Dat is de juiste keuze voor een club met een doorlopende huisranking. Het is
-- de verkeerde keuze voor een club die tot eind februari één competitie
-- speelt: dan staan er naast de league nog twee andere lijstjes, met andere
-- namen bovenaan, en is de vraag "wie staat er eerst" niet meer te
-- beantwoorden.
--
-- `standings_seasons_only` zet die twee uit, voor de staf én voor de zaal.
-- Een vlag en geen verwijdering: na februari zet je hem terug af en staat de
-- jaarstand er weer, met alles wat er intussen gespeeld is.
--
-- ---------------------------------------------------------------------------
-- 3. En de zaal moet de league kunnen zien
-- ---------------------------------------------------------------------------
-- `club_public_standings` kent geen seizoenen en geen beste-N. Zolang de
-- publieke stand "alles sinds het begin" was, klopte dat. Maar een league
-- waar de spelers de stand niet van kunnen zien, is geen league — en dus komt
-- er een publieke seizoensstand bij, met dezelfde beste-N-regel en dezelfde
-- drempel als aan de clubkant, en zonder prijzengeld zoals het hoort.

-- ---------------------------------------------------------------------------
-- 1. De buy-in in de formule
-- ---------------------------------------------------------------------------

create or replace function public.calc_points(
  p_method      ranking_method,
  p_params      jsonb,
  p_position    int,
  p_entries     int,
  p_knockouts   int default 0,
  p_buyin_cents int default 0,
  p_bonus_ko    numeric default 0,
  p_bonus_entry numeric default 0
)
returns numeric
language plpgsql
immutable
as $$
declare
  v_pts   numeric := 0;
  v_tbl   jsonb;
  v_mult  numeric;
  v_base  numeric;
  v_dec   numeric;
  v_floor numeric;
  v_exp   numeric;
  v_ref   numeric;
  v_gew   numeric;
  v_fac   numeric;
begin
  if p_position is null or p_position < 1 or p_entries is null or p_entries < 1 then
    return 0;
  end if;

  case p_method
    when 'fixed_table' then
      v_tbl := coalesce(p_params->'table', '[]'::jsonb);
      if p_position <= jsonb_array_length(v_tbl) then
        v_pts := (v_tbl->>(p_position - 1))::numeric;
      else
        v_pts := coalesce((p_params->>'tail')::numeric, 0);
      end if;

    when 'linear' then
      v_base  := coalesce((p_params->>'base')::numeric, 100);
      v_dec   := coalesce((p_params->>'decrement')::numeric, 5);
      v_floor := coalesce((p_params->>'floor')::numeric, 1);
      v_pts   := greatest(v_base - (p_position - 1) * v_dec, v_floor);

    when 'sqrt_ratio' then
      v_mult := coalesce((p_params->>'multiplier')::numeric, 10);
      -- Zonder exponent is dit letterlijk de oude formule. Tussen 0,5 en 1,5
      -- geklemd: lager dan een halve maakt de plaats bijna betekenisloos,
      -- hoger dan anderhalf krijgt alleen de winnaar nog punten en heeft de
      -- rest van de tafel niets meer te spelen.
      v_exp  := least(1.5, greatest(0.5, coalesce((p_params->>'exponent')::numeric, 0.5)));
      v_pts  := v_mult * sqrt(p_entries::numeric) / power(p_position::numeric, v_exp);

      -- En hoe duur de avond was. Alleen als de club een ijkpunt ingesteld
      -- heeft; anders blijft het bij plaats en veldgrootte, zoals altijd.
      v_ref := (p_params->>'buyin_ref')::numeric;
      if v_ref is not null and v_ref > 0 and coalesce(p_buyin_cents, 0) > 0 then
        v_gew := least(1.5, greatest(0, coalesce((p_params->>'buyin_weight')::numeric, 0.5)));
        v_fac := power((p_buyin_cents::numeric / 100.0) / v_ref, v_gew);
        -- Geklemd: één duur tornooi mag zwaarder wegen dan een gewone avond,
        -- maar geen vier gewone avonden tegelijk.
        v_pts := v_pts * least(2.0, greatest(0.5, v_fac));
      end if;

    when 'pokerstars' then
      v_mult := coalesce((p_params->>'multiplier')::numeric, 10);
      v_pts  := v_mult
                * (sqrt(p_entries::numeric) / sqrt(p_position::numeric))
                * log(10, 1 + (p_buyin_cents::numeric / 100.0));
  end case;

  v_pts := v_pts + (coalesce(p_knockouts, 0) * coalesce(p_bonus_ko, 0)) + coalesce(p_bonus_entry, 0);
  -- Hele getallen, zoals migratie 0022 vastlegde: een klassement met
  -- komma's leest als een berekening en telt niet meer op.
  return round(greatest(v_pts, 0), 0);
end;
$$;

comment on function public.calc_points(ranking_method, jsonb, int, int, int, int, numeric, numeric) is
  'Punten voor één uitslag. Bij sqrt_ratio bepaalt params.exponent hoe zwaar de plaats weegt (0,5 = de oude, vlakke telling) en laten params.buyin_ref en params.buyin_weight de inleg meewegen tegenover een ijkpunt in euro. Ontbreken die parameters, dan verandert er niets.';

-- ---------------------------------------------------------------------------
-- 2. Eén klassement in plaats van drie
-- ---------------------------------------------------------------------------

alter table clubs
  add column if not exists standings_seasons_only boolean not null default false;

comment on column clubs.standings_seasons_only is
  'Toont het klassement alleen per seizoen, zonder de jaar- en maandstand. Voor een club die één competitie met een prijs speelt; zet hem terug af en de jaarstand is er weer, met alles wat er intussen gespeeld is.';

-- ---------------------------------------------------------------------------
-- 3. De publieke seizoensstand
-- ---------------------------------------------------------------------------
-- Welke seizoenen er publiek te zien zijn. Alleen die waar ook werkelijk een
-- afgesloten publieke avond aan hangt: een seizoen aankondigen met een lege
-- stand eronder is erger dan het nog niet tonen.

create or replace function public.club_public_seasons(p_club_slug text)
returns table (
  id        uuid,
  name      text,
  starts_on date,
  ends_on   date,
  is_active boolean
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select s.id, s.name, s.starts_on, s.ends_on, s.is_active
  from seasons s
  join clubs c on c.id = s.club_id
  where c.slug = p_club_slug
    and c.is_active
    and exists (
      select 1 from tournaments t
      where t.season_id = s.id
        and t.player_visibility = 'public'
        and t.status = 'finished'
    )
  order by s.starts_on desc;
$$;

create or replace function public.club_public_season_standings(
  p_club_slug text,
  p_season_id uuid default null
)
returns table (
  player_name   text,
  tournaments   int,
  counted       int,
  points        numeric,
  best_position int,
  cashes        int,
  knockouts     int,
  qualified     boolean,
  min_required  int
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_season uuid;
  v_best_n int;
  v_min    int;
begin
  -- Geen seizoen meegegeven? Dan het nieuwste met publieke uitslagen. Dat is
  -- wat iemand die het klassement opent bedoelt.
  v_season := p_season_id;
  if v_season is null then
    select s.id into v_season
    from public.club_public_seasons(p_club_slug) s
    limit 1;
  end if;
  if v_season is null then
    return;
  end if;

  select rc.count_best_n, rc.min_tournaments
    into v_best_n, v_min
  from seasons s
  join clubs c on c.id = s.club_id
  left join ranking_configs rc on rc.id = s.ranking_config_id
  where s.id = v_season and c.slug = p_club_slug and c.is_active;

  if not found then
    return;
  end if;

  return query
  with zichtbaar as (
    select r.*,
           public.public_name(p.display_name, p.username, p.id,
                              p.public_listing, p.public_profile, c.public_names) as naam,
           row_number() over (partition by r.player_id order by r.points desc) as rn
    from tournament_results r
    join tournaments t on t.id = r.tournament_id
    join clubs c       on c.id = t.club_id
    join players p     on p.id = r.player_id
    where r.season_id = v_season
      and c.slug = p_club_slug
      and c.is_active
      and t.player_visibility = 'public'
      and t.status = 'finished'
  ),
  agg as (
    select z.player_id,
           min(z.naam)                                                     as naam,
           count(*)::int                                                   as tournaments,
           count(*) filter (where v_best_n is null or z.rn <= v_best_n)::int as counted,
           sum(z.points) filter (where v_best_n is null or z.rn <= v_best_n) as points,
           min(z.position)::int                                            as best_position,
           count(*) filter (where z.prize_cents > 0)::int                   as cashes,
           sum(z.knockouts)::int                                           as knockouts
    from zichtbaar z
    group by z.player_id
  )
  select a.naam, a.tournaments, a.counted, round(coalesce(a.points, 0), 0),
         a.best_position, a.cashes, a.knockouts,
         a.tournaments >= coalesce(v_min, 0),
         coalesce(v_min, 0)
  from agg a
  order by 4 desc, a.best_position asc;
end;
$$;

comment on function public.club_public_season_standings(text, uuid) is
  'De stand van een seizoen voor de zaal: dezelfde beste-N-regel en drempel als aan de clubkant, met de naamregeling van de club en zonder prijzengeld. Zonder seizoen meegegeven het nieuwste met publieke uitslagen.';

-- ---------------------------------------------------------------------------
-- 4. Een avond aan een seizoen hangen
-- ---------------------------------------------------------------------------
-- Het seizoen van een tornooi stond al in het aanmaakscherm, maar daar moet
-- je het tornooi voor openen en bewerken, één voor één. Wie een league
-- middenin de kalender begint wil de lijst zien en aanvinken.
--
-- En er zit meer aan vast dan één kolom. De uitslagen van een afgesloten
-- avond dragen hun eigen `season_id`, en de punten die erin staan zijn
-- berekend met de telling die aan het oude seizoen hing. Alleen het tornooi
-- verzetten laat de stand dus half verhuizen. Vandaar één functie die de drie
-- dingen samen doet.

create or replace function public.season_tournaments(
  p_club_id uuid,
  p_from    date default null,
  p_to      date default null
)
returns table (
  id           uuid,
  name         text,
  scheduled_at timestamptz,
  status       text,
  season_id    uuid,
  season_name  text,
  results      int,
  players      int,
  buyin_cents  int,
  fee_cents    int
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_tz text;
begin
  if not public.is_service_context()
     and not public.has_club_role(p_club_id, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten op de tornooien van deze club'
      using errcode = 'insufficient_privilege';
  end if;

  select timezone into v_tz from clubs where clubs.id = p_club_id;
  v_tz := coalesce(v_tz, 'Europe/Brussels');

  return query
  select t.id, t.name, t.scheduled_at, t.status::text, t.season_id, s.name,
         (select count(*)::int from tournament_results r where r.tournament_id = t.id),
         (select count(*)::int from tournament_players tp where tp.tournament_id = t.id),
         t.buyin_cents, t.fee_cents
  from tournaments t
  left join seasons s on s.id = t.season_id
  where t.club_id = p_club_id
    and (p_from is null or (t.scheduled_at at time zone v_tz)::date >= p_from)
    and (p_to   is null or (t.scheduled_at at time zone v_tz)::date <= p_to)
  order by t.scheduled_at desc;
end;
$$;

comment on function public.season_tournaments(uuid, date, date) is
  'De tornooien van een club met het seizoen waar ze aan hangen, om ze in één scherm te kunnen toewijzen.';

create or replace function public.tournament_set_season(
  p_tournament_id uuid,
  p_season_id     uuid
)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  t        tournaments%rowtype;
  v_rc     ranking_configs%rowtype;
  v_n      int := 0;
  r        record;
begin
  select * into t from tournaments where id = p_tournament_id;
  if not found then
    raise exception 'Tornooi bestaat niet';
  end if;

  -- Owner of admin, geen floor. Een floor bedient de avond; in welke
  -- competitie die avond meetelt is een beslissing over het klassement, en
  -- die hoort bij wie de punten instelt.
  if not public.is_service_context()
     and not public.has_club_role(t.club_id, array['owner','admin']::club_role[]) then
    raise exception 'Geen rechten' using errcode = 'insufficient_privilege';
  end if;

  if p_season_id is not null
     and not exists (select 1 from seasons s
                     where s.id = p_season_id and s.club_id = t.club_id) then
    raise exception 'Dat seizoen hoort niet bij deze club' using errcode = 'check_violation';
  end if;

  if t.season_id is not distinct from p_season_id then
    return 0;
  end if;

  update tournaments set season_id = p_season_id where id = p_tournament_id;
  update tournament_results set season_id = p_season_id where tournament_id = p_tournament_id;

  -- Nieuw seizoen, nieuwe telling. Zonder seizoen blijven de punten staan
  -- zoals ze berekend zijn: een avond uit een league halen hoort hem niet op
  -- nul te zetten.
  if p_season_id is null then
    return 0;
  end if;

  select rc.* into v_rc
  from seasons s
  join ranking_configs rc on rc.id = s.ranking_config_id
  where s.id = p_season_id;

  for r in
    select res.id, res.position, res.entries_total, res.knockouts
    from tournament_results res
    where res.tournament_id = p_tournament_id
  loop
    update tournament_results
    set points = public.calc_points(
          coalesce(v_rc.method, 'sqrt_ratio'),
          coalesce(v_rc.params, '{}'::jsonb),
          r.position, r.entries_total, r.knockouts, t.buyin_cents,
          coalesce(v_rc.bonus_per_ko, 0), coalesce(v_rc.bonus_entry, 0))
    where id = r.id;
    v_n := v_n + 1;
  end loop;

  return v_n;
end;
$$;

comment on function public.tournament_set_season(uuid, uuid) is
  'Hangt een tornooi aan een seizoen, verhuist zijn uitslagen mee en rekent hun punten opnieuw met de telling van dat seizoen. Geeft terug hoeveel uitslagregels herrekend zijn.';

-- ---------------------------------------------------------------------------
-- 5. Rechten
-- ---------------------------------------------------------------------------

do $$
declare
  r text;
begin
  foreach r in array array['anon', 'authenticated'] loop
    if exists (select 1 from pg_roles where rolname = r) then
      execute format('grant execute on function public.club_public_seasons(text) to %I', r);
      execute format('grant execute on function public.club_public_season_standings(text,uuid) to %I', r);
    end if;
  end loop;

  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function public.season_tournaments(uuid, date, date) to authenticated;
    grant execute on function public.tournament_set_season(uuid, uuid)    to authenticated;
  end if;
end $$;
