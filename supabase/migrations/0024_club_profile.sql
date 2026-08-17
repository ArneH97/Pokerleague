-- Pokerleague — het visitekaartje van een club
--
-- De publieke pagina toonde tot nu alleen wat er uit het tornooisysteem komt:
-- wat er loopt, wat er gespeeld is, wie er bovenaan staat. Prima voor wie de
-- club kent. Wie er voor het eerst op belandt weet daarna nog altijd niet waar
-- het is, wanneer er gespeeld wordt of aan wie hij iets moet vragen — en dat
-- zijn nu net de drie vragen waarmee iemand een eerste keer komt.
--
-- Vandaar een handvol velden bij de club. Ze zijn allemaal optioneel, en de
-- pagina laat weg wat niet ingevuld is: een lege kop met "Adres" eronder is
-- erger dan geen kop. Een club die niets invult krijgt precies de pagina die
-- hij vandaag heeft.
--
-- Bewust kolommen en geen jsonb. Dit is geen instelling maar identiteit; het
-- hoort leesbaar te zijn in een select, en er hoort commentaar bij te kunnen.

alter table clubs
  add column if not exists intro         text,
  add column if not exists address_line  text,
  add column if not exists maps_url      text,
  add column if not exists play_rhythm   text,
  add column if not exists contact_email text,
  add column if not exists contact_phone text,
  add column if not exists opens_on      date;

comment on column clubs.intro is
  'Een of twee zinnen over de club, voor wie hem voor het eerst tegenkomt. Geen verkooppraat: waar het over gaat en voor wie het is.';
comment on column clubs.address_line is
  'De volledige adresregel van de zaal, zoals je ze op een envelop zou zetten. Bewust in een keer en niet opgesplitst: clubs.city dient voor de kop van de pagina (de gemeente waar men de club van kent) en dat is lang niet altijd de gemeente van de postcode.';
comment on column clubs.maps_url is
  'Link naar de kaart. Optioneel — zonder link is het adres gewoon tekst.';
comment on column clubs.play_rhythm is
  'Wanneer er gespeeld wordt, in mensentaal: "elke zaterdag, deuren 19u30, start 20u". Vrije tekst, want geen twee clubs doen dit hetzelfde.';
comment on column clubs.contact_email is
  'Waar een speler met een vraag terechtkan. Komt op de publieke pagina te staan, dus geen priveadres.';
comment on column clubs.contact_phone is
  'Idem. Leeg laten is prima; dan staat er alleen een mailadres.';
comment on column clubs.opens_on is
  'De dag waarop de club opengaat. Zolang die in de toekomst ligt en er nog niets gespeeld is, zet de publieke pagina daar een aftelling neer in plaats van lege kaders met nullen. Na de eerste avond mag dit blijven staan: zodra er tornooien zijn wint de echte inhoud vanzelf.';

-- ---------------------------------------------------------------------------
-- Nakijken wat er staat
-- ---------------------------------------------------------------------------

select
  slug,
  name,
  coalesce(city, '—')          as gemeente,
  coalesce(address_line, '—')  as adres,
  coalesce(play_rhythm, '—')   as speeldag,
  coalesce(contact_email, '—') as mail,
  coalesce(opens_on::text, '—') as opent
from clubs
order by name;
