-- Pokerleague — realtime
--
-- Zonder dit stuurt Supabase geen wijzigingen door en moet elk scherm
-- pollen. De zaalweergave en het floor-scherm zijn twee losse apparaten die
-- dezelfde klok tonen; die moeten binnen een seconde gelijk lopen.
--
-- RLS blijft gelden op de realtime-stroom: een client krijgt alleen
-- wijzigingen door van rijen die hij ook via een gewone query mag zien.

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then

    -- De klok zelf. Dit is de belangrijkste.
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public'
        and tablename = 'tournaments'
    ) then
      alter publication supabase_realtime add table public.tournaments;
    end if;

    -- Deelnemers: aantal over, chipcounts, uitschakelingen.
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public'
        and tablename = 'tournament_players'
    ) then
      alter publication supabase_realtime add table public.tournament_players;
    end if;

    -- Prijzenpot loopt mee met de inkopen. Alleen staf ziet deze rijen.
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public'
        and tablename = 'buyins'
    ) then
      alter publication supabase_realtime add table public.buyins;
    end if;

  end if;
end $$;

-- Realtime stuurt bij een update standaard alleen de gewijzigde kolommen mee
-- en bij een delete helemaal niets. Voor tournaments willen we de volledige
-- oude rij kunnen zien, zodat een client kan bepalen wat er veranderd is
-- zonder meteen opnieuw te moeten laden.
alter table public.tournaments replica identity full;
