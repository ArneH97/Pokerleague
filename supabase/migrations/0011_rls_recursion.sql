-- Pokerleague — een lus tussen twee leesregels doorbreken
--
-- Het probleem, zoals het op het scherm kwam:
--   infinite recursion detected in policy for relation "players"
--
-- Twee policies verwezen naar elkaars tabel met een gewone subquery:
--
--   players_read       ... exists (select 1 from club_players ...)
--   club_players_read  ... exists (select 1 from players ...)
--
-- Op zo'n subquery past Postgres opnieuw row level security toe. Wie
-- `players` leest, triggert dus `club_players_read`, die op zijn beurt
-- `players_read` triggert, en zo verder. Zolang je één van beide tabellen
-- apart bevraagt valt dat niet op — Postgres kan de lus soms wegoptimaliseren.
-- Vraag je ze samen op (club_players mét de naam uit players, wat het
-- spelersbeheer aan de floor doet), dan slaat hij vast.
--
-- De oplossing is niet om de regel te versoepelen maar om de subquery uit de
-- policy te halen: een SECURITY DEFINER functie draait met de rechten van de
-- eigenaar en zet dus géén nieuwe RLS-ronde in gang. Precies dezelfde
-- voorwaarde, alleen niet meer in een kring.

-- ---------------------------------------------------------------------------
-- 1. De twee voorwaarden als functie
-- ---------------------------------------------------------------------------

-- Ben ik staf van een club waar deze speler lid is?
create or replace function public.staff_sees_player(p_player_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from club_players cp
    join club_members cm on cm.club_id = cp.club_id
    where cp.player_id = p_player_id
      and cm.user_id = auth.uid()
  );
$$;

comment on function public.staff_sees_player(uuid) is
  'Staf van een club mag de spelers van die club lezen. Als functie en niet als subquery in de policy, anders ontstaat er een lus met club_players_read.';

-- Ben ik staf met schrijfrecht bij een club waar deze speler lid is?
create or replace function public.staff_edits_player(p_player_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from club_players cp
    join club_members cm on cm.club_id = cp.club_id
    where cp.player_id = p_player_id
      and cm.user_id = auth.uid()
      and cm.role in ('owner', 'admin', 'floor')
  );
$$;

-- Is dit spelersprofiel van mij?
create or replace function public.is_my_player(p_player_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from players
    where id = p_player_id and auth_user_id = auth.uid()
  );
$$;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function public.staff_sees_player(uuid)  to authenticated;
    grant execute on function public.staff_edits_player(uuid) to authenticated;
    grant execute on function public.is_my_player(uuid)       to authenticated;
  end if;
  if exists (select 1 from pg_roles where rolname = 'anon') then
    grant execute on function public.staff_sees_player(uuid)  to anon;
    grant execute on function public.staff_edits_player(uuid) to anon;
    grant execute on function public.is_my_player(uuid)       to anon;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 2. De policies opnieuw, zonder kruisverwijzing
-- ---------------------------------------------------------------------------
-- Inhoudelijk verandert er niets aan wie wat mag zien.

drop policy if exists players_read on players;
create policy players_read on players
  for select using (
    auth_user_id = auth.uid()
    or public_profile
    or public.shares_club_with(id)
    or public.staff_sees_player(id)
  );

drop policy if exists players_staff_update on players;
create policy players_staff_update on players
  for update using (
    link_state = 'shadow'
    and public.staff_edits_player(id)
  );

drop policy if exists club_players_read on club_players;
create policy club_players_read on club_players
  for select using (
    public.is_club_member(club_id)
    or public.is_my_player(player_id)
  );
