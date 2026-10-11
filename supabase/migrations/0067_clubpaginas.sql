-- Pokerleague — eigen pagina's per club, drietalig
--
-- Een club heeft tekst die nergens past. Een leaguereglement, huisregels, een
-- uitleg over het gedoogbeleid. Dat hoort niet in de code van het platform:
-- dan moet er een drop en een push aan te pas komen om een komma te
-- verzetten, en dan verandert niemand er ooit nog iets aan.
--
-- Dus een tabel. Een club maakt een pagina, vult hem in drie talen in, en hij
-- staat op zijn eigen domein. Onzichtbaar tot hij hem publiceert.
--
-- **Waarom een pagina aan een seizoen mag hangen.** Het reglement van de
-- Marrakech League is geen clubreglement — het geldt voor één competitie, van
-- oktober tot eind februari. Hangt de pagina aan dat seizoen, dan kan het
-- klassement van dat seizoen ernaar linken, en staat ze na februari niet meer
-- in de weg bij de volgende league. `season_id` mag leeg blijven: dan is het
-- een gewone clubpagina die altijd geldt.
--
-- **Waarom drie kolommen per taal en geen jsonb.** Een ontbrekende vertaling
-- moet zichtbaar leeg zijn en niet een sleutel die er toevallig niet in zit.
-- En zo kan je in het bewerkscherm gewoon drie velden naast elkaar zetten.

create table if not exists club_pages (
  id          uuid primary key default gen_random_uuid(),
  club_id     uuid not null references clubs(id)   on delete cascade,
  /** Optioneel: hoort deze pagina bij één seizoen? */
  season_id   uuid references seasons(id) on delete set null,
  /** Het stukje adres: /p/<slug>. Kleine letters, cijfers en streepjes. */
  slug        text not null,
  is_published boolean not null default false,
  sort_order  int not null default 0,
  /** Een afbeelding bovenaan, bijvoorbeeld de affiche van de league. */
  image_url   text,

  title_nl text, body_nl text,
  title_fr text, body_fr text,
  title_en text, body_en text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint club_pages_slug_vorm check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  constraint club_pages_slug_uniek unique (club_id, slug)
);

create index if not exists club_pages_club_idx   on club_pages (club_id, sort_order);
create index if not exists club_pages_season_idx on club_pages (season_id);

comment on table club_pages is
  'Eigen tekstpagina''s van een club, in drie talen. Hangt er een season_id aan, dan hoort de pagina bij dat seizoen en linkt het klassement ervan ernaar.';

-- `updated_at` bijhouden in de database en niet in de server-actie: dan
-- klopt hij ook als een pagina ooit via SQL bijgewerkt wordt, en dat gebeurt
-- bij het inladen van een reglement.
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists club_pages_touch on club_pages;
create trigger club_pages_touch
  before update on club_pages
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- Rechten
-- ---------------------------------------------------------------------------
-- Lezen mag elke staf en elke speler van de club, ook ongepubliceerd: zo kan
-- je nakijken hoe het eruitziet voor je het aanzet. Buitenstaanders lezen via
-- club_public_page(), dat zelf op gepubliceerd filtert.

alter table club_pages enable row level security;

drop policy if exists club_pages_read  on club_pages;
drop policy if exists club_pages_write on club_pages;

create policy club_pages_read on club_pages
  for select using (public.is_club_member(club_id) or public.is_club_player(club_id));

create policy club_pages_write on club_pages
  for all using (public.has_club_role(club_id, array['owner','admin']::club_role[]))
  with check (public.has_club_role(club_id, array['owner','admin']::club_role[]));

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant select, insert, update, delete on club_pages to authenticated;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- De publieke kant
-- ---------------------------------------------------------------------------
-- Eén pagina ophalen, in de gevraagde taal, met terugval op wat er wél
-- ingevuld is. Een bezoeker die Frans kiest en een pagina treft die alleen in
-- het Nederlands bestaat, hoort die tekst te zien en geen leeg scherm — met
-- een vermelding erbij dat de vertaling ontbreekt, zodat het niet lijkt alsof
-- de club slordig Nederlands schrijft tegen een Franstalige.

create or replace function public.club_public_page(
  p_club_slug text,
  p_slug      text,
  p_locale    text default 'nl'
)
returns table (
  slug        text,
  title       text,
  body        text,
  /** De taal die je werkelijk krijgt. Anders dan gevraagd = terugval. */
  locale      text,
  image_url   text,
  season_name text,
  updated_at  timestamptz
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with p as (
    select cp.*, s.name as seizoen
    from club_pages cp
    join clubs c on c.id = cp.club_id
    left join seasons s on s.id = cp.season_id
    where c.slug = p_club_slug
      and c.is_active
      and cp.slug = p_slug
      and cp.is_published
  ),
  gekozen as (
    select
      p.*,
      case p_locale
        when 'fr' then coalesce(nullif(p.title_fr, ''), nullif(p.title_nl, ''), p.title_en)
        when 'en' then coalesce(nullif(p.title_en, ''), nullif(p.title_nl, ''), p.title_fr)
        else           coalesce(nullif(p.title_nl, ''), nullif(p.title_en, ''), p.title_fr)
      end as titel,
      case p_locale
        when 'fr' then coalesce(nullif(p.body_fr, ''), nullif(p.body_nl, ''), p.body_en)
        when 'en' then coalesce(nullif(p.body_en, ''), nullif(p.body_nl, ''), p.body_fr)
        else           coalesce(nullif(p.body_nl, ''), nullif(p.body_en, ''), p.body_fr)
      end as tekst,
      case p_locale
        when 'fr' then case when nullif(p.body_fr, '') is not null then 'fr'
                            when nullif(p.body_nl, '') is not null then 'nl' else 'en' end
        when 'en' then case when nullif(p.body_en, '') is not null then 'en'
                            when nullif(p.body_nl, '') is not null then 'nl' else 'fr' end
        else           case when nullif(p.body_nl, '') is not null then 'nl'
                            when nullif(p.body_en, '') is not null then 'en' else 'fr' end
      end as taal
    from p
  )
  select g.slug, g.titel, g.tekst, g.taal, g.image_url, g.seizoen, g.updated_at
  from gekozen g
  where g.tekst is not null;
$$;

comment on function public.club_public_page(text, text, text) is
  'Eén gepubliceerde clubpagina in de gevraagde taal, met terugval op een taal die wél ingevuld is. De kolom locale zegt welke taal je werkelijk kreeg.';

-- Welke pagina's er zijn, om naar te kunnen linken.

create or replace function public.club_public_pages(
  p_club_slug text,
  p_season_id uuid default null,
  p_locale    text default 'nl'
)
returns table (
  slug      text,
  title     text,
  season_id uuid
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    cp.slug,
    case p_locale
      when 'fr' then coalesce(nullif(cp.title_fr, ''), nullif(cp.title_nl, ''), cp.title_en)
      when 'en' then coalesce(nullif(cp.title_en, ''), nullif(cp.title_nl, ''), cp.title_fr)
      else           coalesce(nullif(cp.title_nl, ''), nullif(cp.title_en, ''), cp.title_fr)
    end,
    cp.season_id
  from club_pages cp
  join clubs c on c.id = cp.club_id
  where c.slug = p_club_slug
    and c.is_active
    and cp.is_published
    and (p_season_id is null or cp.season_id = p_season_id)
  order by cp.sort_order, cp.slug;
$$;

comment on function public.club_public_pages(text, uuid, text) is
  'De gepubliceerde pagina''s van een club, eventueel alleen die van één seizoen, om naar te linken.';

do $$
declare
  r text;
begin
  foreach r in array array['anon', 'authenticated'] loop
    if exists (select 1 from pg_roles where rolname = r) then
      execute format('grant execute on function public.club_public_page(text,text,text) to %I', r);
      execute format('grant execute on function public.club_public_pages(text,uuid,text) to %I', r);
    end if;
  end loop;
end $$;
