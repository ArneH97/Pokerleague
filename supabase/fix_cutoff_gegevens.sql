-- Pokerleague — Cutoff: gemeente en taal rechtzetten
--
-- Baardegem in plaats van Gent (dat was een gok van mij in het seed-script),
-- en de clubomgeving in het Engels omdat de floor Frans spreekt en de
-- eigenaar Nederlands. Engels is dan de minst slechte gemene deler.
--
-- De taal geldt voor de clubomgeving: floor, klok, tornooibeheer. Spelers
-- krijgen straks hun eigen taalkeuze op PokerLeague, los hiervan.

update clubs
set city   = 'Baardegem',
    locale = 'en'
where slug = 'cutoff';

select slug, name, city, locale, primary_color, logo_url
from clubs
where slug = 'cutoff';
