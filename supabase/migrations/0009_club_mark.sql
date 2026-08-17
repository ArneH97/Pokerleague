-- Pokerleague — het beeldmerk apart van het volledige logo
--
-- Een clublogo is meestal een blok: beeldmerk, naam en baseline samen, vaak
-- met een eigen achtergrond ingebakken. Dat plak je niet op een zaalscherm —
-- je ziet de rechthoek van het bestand tegen de achtergrond van de klok
-- afsteken, en de naam staat er dan twee keer.
--
-- Daarom een tweede verwijzing: alleen het beeldmerk, vrijstaand, met een
-- doorzichtige achtergrond. Dat kan groot en zacht achter de tijd staan
-- zonder rand. De clubnaam zetten we als tekst erboven, in de taal en het
-- lettertype van het platform.

alter table clubs
  add column if not exists mark_url text;

comment on column clubs.mark_url is
  'Alleen het beeldmerk, vrijstaand op een doorzichtige achtergrond (PNG of SVG). Wordt groot en vervaagd achter de zaalklok gezet. Leeg = geen watermerk, dan toont de klok enkel de clubnaam.';
