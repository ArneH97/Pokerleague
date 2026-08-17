-- Pokerleague — blindstructuren bewerken
--
-- Een structuur opslaan betekent alle levels vervangen. Vanuit de browser zou
-- dat twee losse aanroepen zijn: eerst wissen, dan invoegen. Gaat de tweede
-- mis of valt de wifi weg, dan staat er een structuur zonder levels — en dat
-- is precies de structuur waar een tornooi aan hangt.
--
-- Vandaar één functie die het in één transactie doet.

create or replace function public.replace_blind_levels(
  p_structure_id uuid,
  p_levels       jsonb
)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_club  uuid;
  v_lvl   jsonb;
  v_idx   int := 0;
  v_count int;
begin
  select club_id into v_club from blind_structures where id = p_structure_id;
  if not found then
    raise exception 'Blindstructuur bestaat niet';
  end if;

  -- Platformsjablonen (club_id null) zijn voor iedereen leesbaar maar door
  -- niemand te wijzigen; die horen alleen via een migratie te veranderen.
  if v_club is null then
    raise exception 'Een platformsjabloon kan je niet aanpassen. Maak er een kopie van.'
      using errcode = 'insufficient_privilege';
  end if;

  if not public.is_service_context()
     and not public.has_club_role(v_club, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten om deze structuur te wijzigen'
      using errcode = 'insufficient_privilege';
  end if;

  if jsonb_typeof(p_levels) <> 'array' or jsonb_array_length(p_levels) = 0 then
    raise exception 'Een structuur moet minstens één level bevatten'
      using errcode = 'check_violation';
  end if;

  delete from blind_levels where structure_id = p_structure_id;

  for v_lvl in select * from jsonb_array_elements(p_levels) loop
    insert into blind_levels (
      structure_id, idx, is_break, label, small_blind, big_blind, ante, duration_s
    ) values (
      p_structure_id,
      v_idx,
      coalesce((v_lvl->>'is_break')::boolean, false),
      nullif(trim(coalesce(v_lvl->>'label', '')), ''),
      greatest(coalesce((v_lvl->>'small_blind')::int, 0), 0),
      greatest(coalesce((v_lvl->>'big_blind')::int, 0), 0),
      greatest(coalesce((v_lvl->>'ante')::int, 0), 0),
      -- Nul seconden zou de klok laten doorrollen zonder ooit te stoppen.
      greatest(coalesce((v_lvl->>'duration_s')::int, 0), 30)
    );
    v_idx := v_idx + 1;
  end loop;

  select count(*) into v_count from blind_levels where structure_id = p_structure_id;
  return v_count;
end;
$$;

-- Kopie maken van een bestaande structuur, inclusief levels. Handig om een
-- platformsjabloon of een vorig seizoen als vertrekpunt te nemen.
create or replace function public.duplicate_blind_structure(
  p_structure_id uuid,
  p_club_id      uuid,
  p_name         text
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_new uuid;
begin
  if not public.is_service_context()
     and not public.has_club_role(p_club_id, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten om structuren aan te maken voor deze club'
      using errcode = 'insufficient_privilege';
  end if;

  if not exists (
    select 1 from blind_structures s
    where s.id = p_structure_id and (s.club_id is null or s.club_id = p_club_id)
  ) then
    raise exception 'Bronstructuur niet gevonden';
  end if;

  insert into blind_structures (club_id, name, description)
  select p_club_id, p_name, description
  from blind_structures where id = p_structure_id
  returning id into v_new;

  insert into blind_levels (structure_id, idx, is_break, label, small_blind, big_blind, ante, duration_s)
  select v_new, idx, is_break, label, small_blind, big_blind, ante, duration_s
  from blind_levels where structure_id = p_structure_id
  order by idx;

  return v_new;
end;
$$;
