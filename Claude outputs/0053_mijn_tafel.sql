-- Pokerleague — wat een speler aan tafel echt wil weten
--
-- Op de spelerspagina stond tot nu: mijn stapel, het gemiddelde, hoeveel
-- spelers er over zijn en de prijzenpot. Vier getallen die geen van alle de
-- vraag beantwoorden die iemand aan tafel stelt: *hoe sta ik ervoor?*
--
-- Aan een pokertafel wordt die vraag in big blinds gesteld en niet in chips.
-- 54.000 zegt niets — 27 big blinds zegt "je hebt nog ruimte", 9 big blinds
-- zegt "je moet iets gaan doen". Datzelfde geldt voor het gemiddelde: het is
-- pas een ijkpunt als je het in dezelfde eenheid kan lezen als je eigen
-- stapel.
--
-- Daar komt bij: waar sta ik in het veld, en hoe ver is het geld nog? Dat
-- laatste is de reden dat mensen bij een bubbel anders gaan spelen, en het
-- staat nu nergens.
--
-- **Waarom de plaats een slag om de arm krijgt.** De rangschikking komt uit de
-- chipcounts, en die zijn onvolledig: op een gewone avond vult niet iedereen
-- ze in. Een "3de van 14" die eigenlijk op zes ingevulde stapels berust, is
-- een verzonnen zekerheid. Vandaar dat de functie er twee getallen bij geeft —
-- hoeveel stapels er meetellen — zodat het scherm eerlijk kan zijn over wat
-- het weet. Wie zelf niets invulde, krijgt geen plaats; die kan hem verdienen
-- door zijn stapel in te geven.
--
-- **De blinds tijdens een pauze.** Dan telt het eerstvolgende speelniveau,
-- niet nul. Anders staat er midden in de pauze "je hebt oneindig veel big
-- blinds", en dat is het moment waarop iemand zijn stapel juist wil inschatten
-- voor de volgende ronde.

drop function if exists public.my_live_tournaments();

create or replace function public.my_live_tournaments()
returns table (
  tournament_id        uuid,
  tournament_player_id uuid,
  name                 text,
  club_slug            text,
  club_name            text,
  logo_url             text,
  primary_color        text,
  currency             char(3),
  status               text,
  clock                text,
  level_idx            int,
  -- Waar de klok staat, in de taal van de zaal.
  level_label          text,
  is_break             boolean,
  small_blind          int,
  big_blind            int,
  ante                 int,
  next_big_blind       int,
  -- Mijn stapel, en wat er over de ingave bekend is.
  my_chips             int,
  my_chips_by          text,
  my_chips_at          timestamptz,
  counts_frozen        boolean,
  -- Het veld.
  players_left         int,
  entries              int,
  avg_stack            int,
  chips_in_play        int,
  -- Waar ik sta. Null als ik zelf niets invulde.
  my_rank              int,
  ranked_players       int,
  -- Hoe ver het geld nog is.
  paid_places          int,
  prize_pool_cents     bigint
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with me as (
    select id from players
    where auth_user_id = auth.uid() and merged_into_id is null
  ),
  mijn as (
    select tp.*
    from tournament_players tp
    join tournaments t on t.id = tp.tournament_id
    where tp.player_id = (select id from me)
      -- Lopend of gepauzeerd. Een afgesloten avond hoort bij je resultaten,
      -- niet bij "waar zit ik nu".
      and t.status in ('running', 'paused')
      and tp.status in ('active', 'registered')
  )
  select
    t.id,
    m.id,
    t.name,
    c.slug,
    c.name,
    c.logo_url,
    c.primary_color,
    c.currency,
    t.status::text,
    t.clock::text,
    t.level_idx,

    -- Het niveau waar de klok op staat, en het niveau waar je mee rekent.
    -- Tijdens een pauze zijn dat er twee verschillende.
    (select l.label from blind_levels l
      where l.structure_id = t.structure_id and l.idx = t.level_idx),
    coalesce((select l.is_break from blind_levels l
      where l.structure_id = t.structure_id and l.idx = t.level_idx), false),
    coalesce((select l.small_blind from blind_levels l
      where l.structure_id = t.structure_id and l.idx >= t.level_idx and not l.is_break
      order by l.idx limit 1), 0),
    coalesce((select l.big_blind from blind_levels l
      where l.structure_id = t.structure_id and l.idx >= t.level_idx and not l.is_break
      order by l.idx limit 1), 0),
    coalesce((select l.ante from blind_levels l
      where l.structure_id = t.structure_id and l.idx >= t.level_idx and not l.is_break
      order by l.idx limit 1), 0),
    coalesce((select l.big_blind from blind_levels l
      where l.structure_id = t.structure_id and l.idx > t.level_idx and not l.is_break
      order by l.idx limit 1), 0),

    m.chip_count,
    m.chip_count_by::text,
    m.chip_count_updated_at,
    t.counts_frozen_at is not null,

    (select count(*)::int from tournament_players x
      where x.tournament_id = t.id and x.status in ('active','registered')),
    (select count(*)::int from tournament_players x where x.tournament_id = t.id),
    (public.chips_in_play(t.id) / greatest(1, (
       select count(*)::int from tournament_players x
       where x.tournament_id = t.id and x.status in ('active','registered'))))::int,
    public.chips_in_play(t.id),

    -- Mijn plaats, gerekend over wie er een stapel heeft ingevuld. Zonder
    -- eigen aantal geen plaats: dan zou je bij de laatste staan omdat je
    -- niets doorgaf, en dat is geen informatie maar een verwijt.
    case when m.chip_count is null then null else (
      select count(*)::int + 1
      from tournament_players x
      where x.tournament_id = t.id
        and x.status in ('active','registered')
        and x.chip_count is not null
        and x.chip_count > m.chip_count
    ) end,
    (select count(*)::int from tournament_players x
      where x.tournament_id = t.id
        and x.status in ('active','registered')
        and x.chip_count is not null),

    (select count(*)::int from public.tournament_prizes(t.id)),
    (select coalesce(sum(b.amount_cents), 0) from buyins b
      where b.tournament_id = t.id and not b.is_void)
  from mijn m
  join tournaments t on t.id = m.tournament_id
  join clubs c       on c.id = t.club_id
  order by t.scheduled_at desc;
$$;

comment on function public.my_live_tournaments() is
  'De avonden waar de aangemelde speler nu aan tafel zit, met alles wat hij aan tafel wil weten: de blinds van dit moment, zijn stapel, het gemiddelde, zijn plaats over de ingevulde stapels en hoeveel plaatsen er betaald worden.';

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function public.my_live_tournaments() to authenticated;
  end if;
end $$;
