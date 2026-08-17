-- Pokerleague — de klok stopt wanneer het tornooi afgelopen is
--
-- Een afgesloten tornooi met een lopende klok is verwarrend op de enige plek
-- waar het telt: het scherm in de zaal. De laatste hand is gespeeld, het geld
-- ligt op tafel, en de beamer telt vrolijk verder naar het volgende level.
--
-- Waar het misging: floor_finish_tournament zette in migratie 0002 netjes
-- clock = 'stopped', maar toen 0017 die functie herschreef voor de
-- prijzenverdeling is die regel niet meegekomen. Sindsdien bleef de klok
-- doorlopen na een deal of een gewone afsluiting.
--
-- Het is verleidelijk om die ene regel terug te zetten. Dat lost het geval van
-- vandaag op en niet dat van morgen: elke volgende manier om een tornooi af te
-- sluiten moet er dan opnieuw aan denken. Een tornooi dat afgelopen is hoort
-- een stilstaande klok te hebben, punt — en dat is een regel over de tabel,
-- niet over één functie. Vandaar een trigger.
--
-- De opgebouwde tijd wordt daarbij bijgeboekt, zodat "gespeeld" op de laatste
-- stand blijft staan in plaats van terug te springen naar het begin van het
-- level.

create or replace function public.tournaments_stop_clock_when_finished()
returns trigger
language plpgsql
as $$
begin
  if new.status in ('finished', 'cancelled') then
    -- Wat er sinds het startmoment gelopen heeft, hoort nog geboekt te
    -- worden; anders verliest de eindstand die laatste minuten.
    if new.clock = 'running' and new.level_started_at is not null then
      new.level_elapsed_ms :=
        coalesce(new.level_elapsed_ms, 0)
        + greatest(0, (extract(epoch from (now() - new.level_started_at)) * 1000)::bigint);
    end if;

    new.clock            := 'stopped';
    new.level_started_at := null;
    new.ended_at         := coalesce(new.ended_at, now());
  end if;

  return new;
end;
$$;

drop trigger if exists trg_tournaments_stop_clock on tournaments;

create trigger trg_tournaments_stop_clock
before update on tournaments
for each row
execute function public.tournaments_stop_clock_when_finished();

-- ---------------------------------------------------------------------------
-- Tornooien die al afgesloten zijn met een lopende klok rechttrekken
-- ---------------------------------------------------------------------------

update tournaments
set clock            = 'stopped',
    level_started_at = null,
    ended_at         = coalesce(ended_at, now())
where status in ('finished', 'cancelled')
  and (clock <> 'stopped' or level_started_at is not null);
