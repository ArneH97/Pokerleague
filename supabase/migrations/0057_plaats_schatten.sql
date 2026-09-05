-- Pokerleague — je plaats schatten in plaats van tellen
--
-- "3de van 9" klonk exact en was het niet. Die 9 waren de spelers die hun
-- stapel hadden ingevuld, en dat zijn er op een gewone avond een handvol. Wie
-- als enige zijn chips doorgaf stond eerste van één — een getal dat niets zegt
-- en toch als een stand leest.
--
-- **Wat we wél zeker weten.** Het aantal chips in spel staat vast: dat volgt
-- uit het geldregister en niet uit wat spelers doorgeven. Gedeeld door het
-- aantal spelers dat nog zit, geeft dat een gemiddelde dat altijd klopt. Jouw
-- eigen stapel weet je zelf. Twee getallen die er zijn, dus, en daaruit valt
-- af te leiden waar je ongeveer staat — zonder dat er iemand anders iets moet
-- invullen.
--
-- **De schatting.** Neem aan dat de stapels ruwweg gelijkmatig liggen tussen
-- niets en het dubbele van het gemiddelde. Zit je precies op het gemiddelde,
-- dan staat de helft van het veld boven je: bij vijf spelers ben je de derde.
-- Heb je het dubbele, dan sta je bovenaan; heb je bijna niets, onderaan.
--
--     plaats = 1 + (1 - stapel / (2 × gemiddelde)) × (spelers - 1)
--
-- Dat is een model en geen meting, en het pretendeert ook niet meer te zijn:
-- het scherm zet er een ± voor. Maar het is over het hele veld gerekend en
-- niet over de vier mensen die toevallig hun gsm bovenhaalden, en dus zegt het
-- iets waar je aan tafel wat aan hebt.
--
-- **Behalve als iedereen wél ingevuld heeft.** Dan is tellen beter dan
-- schatten, en telt hij gewoon. Het scherm laat het ± dan weg. Dat is precies
-- de situatie na een telronde van de floor, en dan hoort het getal ook hard te
-- zijn.

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
  level_label          text,
  is_break             boolean,
  small_blind          int,
  big_blind            int,
  ante                 int,
  next_big_blind       int,
  level_remaining_ms   bigint,
  my_chips             int,
  my_chips_by          text,
  my_chips_at          timestamptz,
  counts_frozen        boolean,
  my_table             int,
  my_seat              int,
  players_left         int,
  entries              int,
  avg_stack            int,
  chips_in_play        int,
  my_rank              int,
  /** True als de plaats een schatting is uit het gemiddelde. */
  rank_estimated       boolean,
  ranked_players       int,
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
    k.level_idx,
    (select l.label from blind_levels l
      where l.structure_id = t.structure_id and l.idx = k.level_idx),
    coalesce((select l.is_break from blind_levels l
      where l.structure_id = t.structure_id and l.idx = k.level_idx), false),
    coalesce((select l.small_blind from blind_levels l
      where l.structure_id = t.structure_id and l.idx >= k.level_idx and not l.is_break
      order by l.idx limit 1), 0),
    coalesce((select l.big_blind from blind_levels l
      where l.structure_id = t.structure_id and l.idx >= k.level_idx and not l.is_break
      order by l.idx limit 1), 0),
    coalesce((select l.ante from blind_levels l
      where l.structure_id = t.structure_id and l.idx >= k.level_idx and not l.is_break
      order by l.idx limit 1), 0),
    coalesce((select l.big_blind from blind_levels l
      where l.structure_id = t.structure_id and l.idx > k.level_idx and not l.is_break
      order by l.idx limit 1), 0),
    k.remaining_ms,
    m.chip_count,
    m.chip_count_by::text,
    m.chip_count_updated_at,
    t.counts_frozen_at is not null,
    m.table_no,
    m.seat_no,
    v.over,
    v.deelnames,
    v.gemiddeld,
    v.in_spel,

    -- De plaats. Weet iedereen zijn stapel, dan tellen we; anders schatten we
    -- uit het gemiddelde. Zonder eigen aantal staat er niets — dat blijft een
    -- vraag aan de speler en geen verwijt.
    case
      when m.chip_count is null then null
      when v.ingevuld >= v.over then v.exacte_plaats
      when v.gemiddeld <= 0 then null
      else greatest(1, least(v.over, round(
             1 + (1 - least(1, m.chip_count::numeric / (2 * v.gemiddeld))) * (v.over - 1)
           )::int))
    end,
    (m.chip_count is not null and v.ingevuld < v.over and v.gemiddeld > 0),
    v.ingevuld,

    (select count(*)::int from public.tournament_prizes(t.id)),
    (select coalesce(sum(b.amount_cents), 0) from buyins b
      where b.tournament_id = t.id and not b.is_void)
  from mijn m
  join tournaments t on t.id = m.tournament_id
  join clubs c       on c.id = t.club_id
  cross join lateral public.clock_position(t.id) k
  cross join lateral (
    select
      (select count(*)::int from tournament_players x
        where x.tournament_id = t.id and x.status in ('active','registered')) as over,
      (select count(*)::int from tournament_players x
        where x.tournament_id = t.id) as deelnames,
      (select count(*)::int from tournament_players x
        where x.tournament_id = t.id and x.status in ('active','registered')
          and x.chip_count is not null) as ingevuld,
      public.chips_in_play(t.id) as in_spel,
      (public.chips_in_play(t.id) / greatest(1, (
         select count(*)::int from tournament_players x
         where x.tournament_id = t.id and x.status in ('active','registered'))))::int as gemiddeld,
      (select count(*)::int + 1
        from tournament_players x
        where x.tournament_id = t.id
          and x.status in ('active','registered')
          and x.chip_count is not null
          and x.chip_count > m.chip_count) as exacte_plaats
  ) v
  order by t.scheduled_at desc;
$$;

comment on function public.my_live_tournaments() is
  'De avonden waar de aangemelde speler nu aan tafel zit. De plaats wordt geteld als iedereen zijn stapel ingaf, en anders geschat uit de verhouding tot het gemiddelde — dat gemiddelde volgt uit het geldregister en klopt altijd.';

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function public.my_live_tournaments() to authenticated;
  end if;
end $$;
