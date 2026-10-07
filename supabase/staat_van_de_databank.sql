-- Pokerleague — welke migraties staan er écht in deze databank?
--
-- Een migratiebestand dat in je repo staat, is nog niet gedraaid. Pushen zet
-- de code op Vercel; de databank verandert alleen als je het script in deze
-- editor uitvoert. Dat verschil is onzichtbaar tot er iets niet werkt zoals
-- het hoort — en dan zoek je in de verkeerde hoek.
--
-- Dit script verandert niets. Het kijkt per migratie of het spoor dat ze
-- achterlaat aanwezig is: een functie, een kolom, of een stuk tekst in de
-- functie zelf. Staat er ergens ONTBREEKT, dan is die migratie nooit
-- uitgevoerd.

with sporen(nr, wat, aanwezig) as (
  values
    (48, 'Speler verwijderen · renumber_finish_positions()',
     to_regprocedure('public.renumber_finish_positions(uuid)') is not null),

    (49, 'Tornooi bewerken · update_tournament()',
     to_regprocedure('public.update_tournament(uuid, jsonb)') is not null),

    -- Niet of de functie bestaat — die bestond al — maar of ze de nieuwe
    -- regel bevat: een rebuy zet de stapel óp de startstapel in plaats van
    -- hem erbij op te tellen.
    (50, 'Rebuy zet de stapel terug op de startstapel',
     exists (
       select 1 from pg_proc p
       join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'floor_rebuy'
         and p.prosrc like '%in (''reentry'', ''rebuy'') then t.starting_stack%')),

    (51, 'Chips in spel · buyins.chips_delta',
     exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'buyins'
               and column_name = 'chips_delta')),

    (52, 'Stapels bevriezen · tournaments.counts_frozen_at',
     exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'tournaments'
               and column_name = 'counts_frozen_at')),

    (54, 'Spelers per tafel · tournaments.seats_per_table',
     exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'tournaments'
               and column_name = 'seats_per_table')),

    (55, 'Tafelindeling · floor_autoseat()',
     to_regprocedure('public.floor_autoseat(uuid)') is not null),

    (56, 'Live blinds en stoelen · clock_position()',
     to_regprocedure('public.clock_position(uuid)') is not null),

    (57, 'Plaats schatten · my_live_tournaments() geeft rank_estimated',
     exists (
       select 1 from pg_proc p
       join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'my_live_tournaments'
         and pg_get_function_result(p.oid) like '%rank_estimated%')),

    (58, 'Levels tijdens de avond · floor_set_upcoming_levels()',
     to_regprocedure('public.floor_set_upcoming_levels(uuid, integer, jsonb)') is not null),

    (59, 'Tornooi verwijderen · floor_delete_tournament()',
     to_regprocedure('public.floor_delete_tournament(uuid)') is not null),

    -- 0059 haalde ook het aantal inschrijvingen uit de publieke RPC's. Als
    -- dit nog ja zegt, zien je spelers die teller nog altijd staan.
    (59, 'Aantal inschrijvingen weg bij spelers',
     not exists (
       select 1 from information_schema.parameters
       where specific_schema = 'public' and parameter_name = 'registered'
         and specific_name in (
           select specific_name from information_schema.routines
           where routine_schema = 'public'
             and routine_name in ('tournament_signup_card', 'my_calendar'))))
)
select
  nr                                               as migratie,
  wat,
  case when aanwezig then 'ok' else 'ONTBREEKT' end as staat
from sporen
order by nr, wat;
