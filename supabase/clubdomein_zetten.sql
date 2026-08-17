-- Pokerleague — het eigen domein van een club koppelen
--
-- Draai dit pas nádat het domein bij de hosting staat en de CNAME van de club
-- actief is. Andersom werkt ook, alleen krijgt de bezoeker dan even een
-- certificaatfout te zien, en dat is precies het soort eerste indruk dat je
-- niet wil.
--
-- Nodig is dit niet: cutoff.pokerleague.be werkt sowieso, zonder deze regel en
-- zonder DNS bij de club. Dit is de verbetering achteraf, niet de voorwaarde
-- vooraf. Zie docs/domeinen.md.
--
-- Beide adressen blijven daarna werken. Een link die iemand vorig jaar
-- bewaarde blijft dus geldig.

update clubs
set custom_domain = 'app.cutoff.be'
where slug = 'cutoff';

-- Nakijken wat er nu staat. custom_domain leeg betekent: alleen bereikbaar
-- via het subdomein van het platform, en dat is prima.
select slug, name, coalesce(custom_domain, '—') as eigen_domein, is_active
from clubs
order by name;
