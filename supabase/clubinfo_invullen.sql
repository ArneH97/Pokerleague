-- Pokerleague — de clubinfo van Cutoff
--
-- Wat hier op null staat verdwijnt van de pagina: er komt geen leeg kopje te
-- staan. Je mag dit zo vaak draaien als je wil; het overschrijft telkens.
--
-- Draai eerst 0024_club_profile.sql, anders bestaan deze kolommen nog niet.

update clubs set

  -- Een of twee zinnen, voor wie de club voor het eerst tegenkomt. Pas gerust
  -- aan — dit is de enige tekst op de pagina die niet uit het systeem komt.
  intro = 'Pokerclub in Baardegem. Elke speelavond een tornooi met een vaste '
          || 'structuur, een echte klok en een klassement dat het hele seizoen '
          || 'meeloopt. Nieuwe spelers zijn welkom.',

  -- De volledige adresregel, zoals op een envelop.
  address_line = 'Baardegem-Dorp 63, 9310 Aalst',

  maps_url = 'https://www.google.com/maps/place//data=!4m2!3m1!1s0x47c395d2753ef089:0x59fd489e68cdbd89?sa=X&ved=1t:8290&hl=nl&ictx=111',

  -- Wanneer er gespeeld wordt, in mensentaal. Vul gerust de uren aan zodra
  -- die vastliggen — deze regel is vrije tekst en komt zo op de pagina.
  play_rhythm = 'Elke zondag en woensdag',

  contact_email = 'julien@cutoff.be',
  contact_phone = '+32 467 82 72 33',

  -- De openingsdag. Zolang die in de toekomst ligt en er nog niets gespeeld
  -- is, zet de pagina daar een aftelling neer in plaats van lege kaders.
  opens_on = date '2026-09-06'

where slug = 'cutoff';

select
  slug, name,
  coalesce(city, '—')          as gemeente,
  coalesce(address_line, '—')  as adres,
  coalesce(play_rhythm, '—')   as speeldag,
  coalesce(contact_email, '—') as mail,
  coalesce(contact_phone, '—') as telefoon,
  coalesce(opens_on::text, '—') as opent
from clubs where slug = 'cutoff';
