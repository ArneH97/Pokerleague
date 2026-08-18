-- Pokerleague — de kleur van de club mee in "mijn clubs"
--
-- Op de spelerspagina staan de clubs waar je bij hoort als kaarten. Zonder
-- kleur zijn dat vier identieke grijze blokken, en dan moet je elke keer de
-- naam lézen om te weten waar je klikt. Een clubkleur lost dat op de manier op
-- waarop het in de zaal ook werkt: je herkent het bord voor je de letters leest.
--
-- De kleur staat al op `clubs.primary_color` en wordt al publiek getoond via
-- `club_card`, dus er komt hier niets bij dat nog niet openbaar was. `my_clubs`
-- gaf hem alleen niet mee.
--
-- `drop` vooraf omdat `create or replace` het rijtype van een `returns table`
-- niet mag wijzigen — een kolom erbij is precies zo'n wijziging.

drop function if exists public.my_clubs();

create or replace function public.my_clubs()
returns table (
  slug          text,
  name          text,
  city          text,
  logo_url      text,
  primary_color text,
  since         timestamptz
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select c.slug, c.name, c.city, c.logo_url, c.primary_color, cp.created_at
  from club_players cp
  join clubs c   on c.id = cp.club_id
  join players p on p.id = cp.player_id
  where p.auth_user_id = auth.uid() and p.merged_into_id is null
  order by c.name;
$$;

comment on function public.my_clubs() is
  'De clubs waar de aangemelde speler lid van is, met de huisstijlkleur erbij zodat de spelerspagina ze uit elkaar kan houden.';

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function public.my_clubs() to authenticated;
  end if;
end $$;
