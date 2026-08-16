-- Pokerleague — huisstijl en domein van Cutoff instellen
--
-- Draai dit nadat 0005 erdoor is. Je mag het meerdere keren draaien.
--
-- Het domein hier bepaalt welke clubomgeving een bezoeker krijgt: een verzoek
-- op app.cutoff.be wordt intern doorgeschreven naar /c/cutoff/…, zodat de club
-- schone URL's ziet zonder clubnaam erin. Zolang het domein nog niet in
-- Vercel staat werkt /c/cutoff/… gewoon rechtstreeks — je kan dit dus nu al
-- invullen zonder dat er iets breekt.

update clubs
set
  custom_domain = 'app.cutoff.be',

  -- Huisstijlkleur van de club. Wordt gebruikt voor knoppen en accenten; de
  -- tekstkleur erop wordt automatisch zwart of wit gekozen op basis van hoe
  -- donker deze kleur is.
  primary_color = '#c81e2d',

  -- Publieke URL naar het logo. Leeg laten mag; dan valt alles terug op de
  -- clubnaam in tekst. Zet het bestand in Supabase Storage in een publieke
  -- bucket, of gebruik een bestaande URL van de club.
  logo_url = null,

  -- Contractueel: mogen de resultaten van deze club mee in PokerLeague?
  -- Zet dit pas op true zodra dat getekend is. Let op: dit is de toestemming
  -- van de CLUB. Of een speler met naam in een openbare ranking verschijnt
  -- beslist die speler zelf via players.public_profile.
  shares_results = false

where slug = 'cutoff';

-- Controle: zo ziet het er nu uit.
select slug, name, custom_domain, primary_color, shares_results
from clubs
where slug = 'cutoff';
