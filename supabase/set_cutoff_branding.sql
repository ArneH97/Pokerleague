-- Pokerleague — huisstijl en domein van Cutoff Cardroom
--
-- Draai dit nadat 0006 erdoor is. Je mag het meerdere keren draaien.
--
-- Cutoff is goud op diepzwart, met "more than a position" eronder. Dat is een
-- andere wereld dan het standaard grafiet van het platform, en dat hoort ook
-- zo: vanaf het moment dat hun floor aanlogt moet alles naar hen ruiken.
-- Daarom brengt een club niet alleen een accentkleur mee maar zijn volledige
-- vlakkenpalet.

update clubs
set
  name = 'Cutoff Cardroom',

  -- Het domein bepaalt welke clubomgeving een bezoeker krijgt: een verzoek op
  -- app.cutoff.be wordt intern doorgeschreven naar /c/cutoff/…. Zolang het
  -- domein nog niet in Vercel staat werkt /c/cutoff/… gewoon rechtstreeks.
  custom_domain = 'app.cutoff.be',

  -- Het goud uit het logo. Wordt gebruikt voor knoppen, accenten, de
  -- voortgangsbalk op de klok en de gloed achter de tijd.
  primary_color = '#c8a15c',

  -- Verwijzing naar het logobestand. Zet cutoff.png in public/clubs/ in de
  -- repo en push; dan staat hij op dit pad.
  logo_url = '/clubs/cutoff.png',

  -- Het volledige palet van de club. Alles wat je hier weglaat valt terug op
  -- het platformthema, dus een club met alleen een accentkleur werkt ook.
  settings = coalesce(settings, '{}'::jsonb) || jsonb_build_object(
    'theme', jsonb_build_object(
      'bg',           '#080706',
      'surface',      '#121010',
      'surface2',     '#1b1817',
      'surfaceHover', '#241f1d',
      'line',         '#2a2522',
      'lineStrong',   '#3d352f',
      'text',         '#f2ece0',
      'textMuted',    '#a89d8b',
      'textFaint',    '#6f6659'
    )
  ),

  -- Contractueel: mogen de resultaten van deze club mee in PokerLeague?
  -- Zet dit pas op true zodra dat getekend is. Let op: dit is de toestemming
  -- van de CLUB. Of een speler met naam in een openbare ranking verschijnt
  -- beslist die speler zelf via players.public_profile.
  shares_results = false

where slug = 'cutoff';

-- Controle: zo ziet het er nu uit.
select slug, name, custom_domain, primary_color, logo_url,
       settings->'theme'->>'bg' as achtergrond
from clubs
where slug = 'cutoff';
