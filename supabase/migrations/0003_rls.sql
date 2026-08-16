-- ClubStack — row level security.
-- Uitgangspunt: alles dicht, dan gericht openzetten. Een club mag nooit
-- data van een andere club zien, en het geldregister is nooit zichtbaar
-- voor spelers.

-- De helperfuncties (is_club_member, has_club_role, is_club_player,
-- can_view_tournament, shares_club_with) staan in 0002 en moeten dus eerst
-- gedraaid zijn.

-- ---------------------------------------------------------------------------
alter table clubs               enable row level security;
alter table club_members        enable row level security;
alter table players             enable row level security;
alter table club_players        enable row level security;
alter table player_invites      enable row level security;
alter table blind_structures    enable row level security;
alter table blind_levels        enable row level security;
alter table payout_templates    enable row level security;
alter table ranking_configs     enable row level security;
alter table seasons             enable row level security;
alter table tournaments         enable row level security;
alter table tournament_tables   enable row level security;
alter table tournament_players  enable row level security;
alter table buyins              enable row level security;
alter table eliminations        enable row level security;
alter table tournament_results  enable row level security;
alter table audit_log           enable row level security;

-- ---------------------------------------------------------------------------
-- Clubs — de clubgids is publiek, beheer niet.
-- ---------------------------------------------------------------------------

create policy clubs_read on clubs
  for select using (is_active or public.is_club_member(id));

create policy clubs_update on clubs
  for update using (public.has_club_role(id, array['owner','admin']::club_role[]));

-- ---------------------------------------------------------------------------
-- Staf
-- ---------------------------------------------------------------------------

create policy club_members_read on club_members
  for select using (user_id = auth.uid() or public.is_club_member(club_id));

create policy club_members_write on club_members
  for all using (public.has_club_role(club_id, array['owner','admin']::club_role[]))
  with check (public.has_club_role(club_id, array['owner','admin']::club_role[]));

-- ---------------------------------------------------------------------------
-- Spelers
-- ---------------------------------------------------------------------------
-- Zichtbaar als: het is je eigen profiel, je deelt een club, staf van een club
-- waar de speler lid is, of de speler heeft zijn profiel publiek gezet.

create policy players_read on players
  for select using (
    auth_user_id = auth.uid()
    or public_profile
    or public.shares_club_with(id)
    or exists (
      select 1 from club_players cp
      where cp.player_id = players.id and public.is_club_member(cp.club_id)
    )
  );

create policy players_self_update on players
  for update using (auth_user_id = auth.uid())
  with check (auth_user_id = auth.uid());

-- Staf mag schaduwprofielen aanmaken en bijwerken voor de eigen club.
create policy players_staff_insert on players
  for insert with check (
    exists (select 1 from club_members cm
            where cm.user_id = auth.uid()
              and cm.role in ('owner','admin','floor'))
  );

create policy players_staff_update on players
  for update using (
    link_state = 'shadow'
    and exists (
      select 1 from club_players cp
      where cp.player_id = players.id
        and public.has_club_role(cp.club_id, array['owner','admin','floor']::club_role[])
    )
  );

create policy club_players_read on club_players
  for select using (
    public.is_club_member(club_id)
    or exists (select 1 from players p
               where p.id = club_players.player_id and p.auth_user_id = auth.uid())
  );

create policy club_players_write on club_players
  for all using (public.has_club_role(club_id, array['owner','admin','floor']::club_role[]))
  with check (public.has_club_role(club_id, array['owner','admin','floor']::club_role[]));

create policy player_invites_staff on player_invites
  for all using (public.has_club_role(club_id, array['owner','admin']::club_role[]))
  with check (public.has_club_role(club_id, array['owner','admin']::club_role[]));

-- ---------------------------------------------------------------------------
-- Configuratie — platformsjablonen (club_id null) leest iedereen.
-- ---------------------------------------------------------------------------

create policy blind_structures_read on blind_structures
  for select using (club_id is null or public.is_club_member(club_id));

create policy blind_structures_write on blind_structures
  for all using (club_id is not null and public.has_club_role(club_id, array['owner','admin']::club_role[]))
  with check (club_id is not null and public.has_club_role(club_id, array['owner','admin']::club_role[]));

create policy blind_levels_read on blind_levels
  for select using (
    exists (select 1 from blind_structures s
            where s.id = blind_levels.structure_id
              and (s.club_id is null or public.is_club_member(s.club_id)))
  );

create policy blind_levels_write on blind_levels
  for all using (
    exists (select 1 from blind_structures s
            where s.id = blind_levels.structure_id
              and s.club_id is not null
              and public.has_club_role(s.club_id, array['owner','admin']::club_role[]))
  )
  with check (
    exists (select 1 from blind_structures s
            where s.id = blind_levels.structure_id
              and s.club_id is not null
              and public.has_club_role(s.club_id, array['owner','admin']::club_role[]))
  );

create policy payout_templates_read on payout_templates
  for select using (club_id is null or public.is_club_member(club_id));

create policy payout_templates_write on payout_templates
  for all using (club_id is not null and public.has_club_role(club_id, array['owner','admin']::club_role[]))
  with check (club_id is not null and public.has_club_role(club_id, array['owner','admin']::club_role[]));

create policy ranking_configs_read on ranking_configs
  for select using (club_id is null or public.is_club_member(club_id) or public.is_club_player(club_id));

create policy ranking_configs_write on ranking_configs
  for all using (club_id is not null and public.has_club_role(club_id, array['owner','admin']::club_role[]))
  with check (club_id is not null and public.has_club_role(club_id, array['owner','admin']::club_role[]));

-- ---------------------------------------------------------------------------
-- Seizoenen en tornooien
-- ---------------------------------------------------------------------------

create policy seasons_read on seasons
  for select using (public.is_club_member(club_id) or public.is_club_player(club_id));

create policy seasons_write on seasons
  for all using (public.has_club_role(club_id, array['owner','admin']::club_role[]))
  with check (public.has_club_role(club_id, array['owner','admin']::club_role[]));

create policy tournaments_read on tournaments
  for select using (
    public.is_club_member(club_id)
    or player_visibility = 'public'
    or (player_visibility = 'members' and public.is_club_player(club_id))
  );

create policy tournaments_write on tournaments
  for all using (public.has_club_role(club_id, array['owner','admin','floor']::club_role[]))
  with check (public.has_club_role(club_id, array['owner','admin','floor']::club_role[]));

create policy tournament_tables_read on tournament_tables
  for select using (public.can_view_tournament(tournament_id));

create policy tournament_tables_write on tournament_tables
  for all using (public.has_club_role(club_id, array['owner','admin','floor']::club_role[]))
  with check (public.has_club_role(club_id, array['owner','admin','floor']::club_role[]));

-- Deelnemerslijst is zichtbaar zodra het tornooi zichtbaar is: dit voedt
-- "wie staat er aan de leiding" in de spelersapp.
create policy tournament_players_read on tournament_players
  for select using (public.can_view_tournament(tournament_id));

create policy tournament_players_write on tournament_players
  for all using (public.has_club_role(club_id, array['owner','admin','floor']::club_role[]))
  with check (public.has_club_role(club_id, array['owner','admin','floor']::club_role[]));

-- ---------------------------------------------------------------------------
-- Geldregister — uitsluitend staf. Geen enkele spelerslees-policy.
-- ---------------------------------------------------------------------------

create policy buyins_staff on buyins
  for all using (public.has_club_role(club_id, array['owner','admin','floor']::club_role[]))
  with check (public.has_club_role(club_id, array['owner','admin','floor']::club_role[]));

create policy eliminations_read on eliminations
  for select using (public.can_view_tournament(tournament_id));

create policy eliminations_write on eliminations
  for all using (public.has_club_role(club_id, array['owner','admin','floor']::club_role[]))
  with check (public.has_club_role(club_id, array['owner','admin','floor']::club_role[]));

-- ---------------------------------------------------------------------------
-- Resultaten — de leeslaag van de spelersapp.
-- ---------------------------------------------------------------------------

create policy tournament_results_read on tournament_results
  for select using (
    public.can_view_tournament(tournament_id)
    or exists (select 1 from players p
               where p.id = tournament_results.player_id and p.auth_user_id = auth.uid())
  );

create policy tournament_results_write on tournament_results
  for all using (public.has_club_role(club_id, array['owner','admin']::club_role[]))
  with check (public.has_club_role(club_id, array['owner','admin']::club_role[]));

create policy audit_log_read on audit_log
  for select using (public.has_club_role(club_id, array['owner','admin']::club_role[]));

-- ---------------------------------------------------------------------------
-- Rechten
-- ---------------------------------------------------------------------------
-- Supabase zet dit doorgaans al goed via default privileges, maar expliciet
-- is beter dan hopen. RLS blijft de echte poort: een grant zonder policy
-- levert nog steeds nul rijen op.
-- De DO-blokken maken dit ook draaibaar op een kale Postgres, waar de
-- Supabase-rollen niet bestaan.

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    grant usage on schema public to anon;
    grant select on all tables in schema public to anon;
  end if;

  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant usage on schema public to authenticated;
    grant select, insert, update, delete on all tables in schema public to authenticated;
    grant usage, select on all sequences in schema public to authenticated;
  end if;

  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant usage on schema public to service_role;
    grant all on all tables in schema public to service_role;
    grant all on all sequences in schema public to service_role;
  end if;
end $$;
