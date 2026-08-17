-- Pokerleague — de uitnodiging gaat effectief de deur uit
--
-- Sinds migratie 0010 zet `floor_add_entry` een rij in `player_invites` zodra
-- de floor iemand met een mailadres intikt die nog niet bestond. Die rij bleef
-- daar staan. `sent_at` is altijd leeg gebleven, want er was niemand die de
-- wachtrij leeghaalde — de mailer bestond nog niet.
--
-- Hier komt het gereedschap voor die verzender, plus het sluitstuk aan de
-- andere kant: de uitnodiging afvinken zodra de persoon zijn account effectief
-- heeft.
--
-- Eén ontwerpkeuze die de rest verklaart: **het token is een brief, geen
-- sleutel.** Wie op de link klikt krijgt niet meteen het profiel. Hij ziet wie
-- hem uitnodigt en wat er klaarstaat, en registreert daarna op het mailadres
-- uit de uitnodiging — met de gewone bevestigingsmail erachter. Dat is met
-- opzet een stap meer dan nodig lijkt. Een token in een URL lekt: het staat in
-- de browsergeschiedenis, het reist mee in een doorgestuurde mail, het staat op
-- het scherm als iemand meekijkt. Zou dat token op zichzelf toegang geven tot
-- andermans speelhistorie, dan is één doorgestuurde mail genoeg om ze te lezen.
-- Nu bewijst het alleen dat wij dit adres kennen, en moet de persoon nog altijd
-- aantonen dat hij die mailbox heeft.
--
-- Het opeisen zelf verandert dus niet: dat blijft `claim_my_player`, op het
-- geverifieerde adres uit het token van de sessie.

-- ---------------------------------------------------------------------------
-- 1. Boekhouding voor de verzender
-- ---------------------------------------------------------------------------
-- `sent_at` en `last_error` staan er sinds 0010. Wat ontbrak is een teller:
-- zonder die teller blijft een adres dat structureel weigert — een typfout aan
-- de deur, een mailbox die niet bestaat — elke ronde opnieuw geprobeerd
-- worden. Dat kost niets in geld maar wel in reputatie: bezorgdiensten kijken
-- naar het aandeel bounces, en een handvol adressen dat eeuwig blijft
-- terugkomen trekt dat cijfer omlaag voor álle mail die we sturen.

alter table player_invites
  add column if not exists attempts     int not null default 0,
  add column if not exists last_try_at  timestamptz;

comment on column player_invites.attempts is
  'Hoeveel keer de verzender het geprobeerd heeft. Na drie mislukkingen stopt hij ermee: dan is het geen tijdelijke storing meer maar een adres dat niet bestaat, en dat los je op aan de deur en niet door harder te proberen.';
comment on column player_invites.last_try_at is
  'Wanneer de laatste poging was. Alleen om te kunnen zien of de wachtrij nog draait.';

-- De index uit 0010 kijkt naar openstaande uitnodigingen. Die blijft kloppen,
-- maar hij mag ook de opgegeven pogingen overslaan.
drop index if exists player_invites_pending;
create index player_invites_pending
  on player_invites (created_at)
  where sent_at is null and accepted_at is null and attempts < 3;

-- ---------------------------------------------------------------------------
-- 2. De uitnodiging opzoeken op token
-- ---------------------------------------------------------------------------
-- De landingspagina is publiek: wie hier komt heeft per definitie nog geen
-- account. `player_invites` staat achter een policy die alleen bestuur van de
-- club binnenlaat, en dat blijft zo — deze functie is het enige gaatje, en ze
-- geeft precies terug wat er op die ene pagina moet staan. Geen player_id,
-- geen clubgegevens die niet al publiek zijn, geen andere uitnodigingen.
--
-- Het token is 64 hexadecimale tekens. Raden is geen aanvalsroute.

create or replace function public.invite_lookup(p_token text)
returns table (
  club_slug     text,
  club_name     text,
  club_city     text,
  logo_url      text,
  primary_color text,
  contact_email text,
  locale        text,
  player_name   text,
  email         text,
  expires_at    timestamptz,
  state         text            -- 'open' | 'expired' | 'accepted' | 'has_account'
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    c.slug,
    c.name,
    c.city,
    c.logo_url,
    c.primary_color,
    c.contact_email,
    coalesce(p.locale, c.locale),
    p.display_name,
    i.email,
    i.expires_at,
    case
      when i.accepted_at is not null   then 'accepted'
      when p.auth_user_id is not null  then 'has_account'
      when i.expires_at < now()        then 'expired'
      else 'open'
    end
  from player_invites i
  join clubs   c on c.id = i.club_id
  join players p on p.id = i.player_id
  where i.token = p_token
  limit 1
$$;

comment on function public.invite_lookup(text) is
  'Zoekt een uitnodiging op token, voor de publieke landingspagina. Geeft bewust geen player_id terug: het token opent een pagina, het opent geen profiel. Het opeisen gebeurt daarna gewoon via claim_my_player op het geverifieerde mailadres.';

-- ---------------------------------------------------------------------------
-- 3. Afvinken zodra iemand zijn account heeft
-- ---------------------------------------------------------------------------
-- Dit hoort een trigger te zijn en geen regel in `claim_my_player`. Er is
-- vandaag één weg naar een gekoppeld profiel, maar dat blijft niet zo — een
-- beheerder die twee profielen samenvoegt, een import, een latere
-- aanmeldknop via een andere aanbieder. Aan de tabel hangen betekent dat het
-- klopt ongeacht wie de koppeling legde.

create or replace function public.mark_invites_accepted()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update player_invites
  set accepted_at = now()
  where accepted_at is null
    and (player_id = new.id
         or (new.email is not null and lower(email) = lower(new.email)));
  return new;
end;
$$;

drop trigger if exists players_invite_accepted on players;
create trigger players_invite_accepted
  after insert or update of auth_user_id on players
  for each row
  when (new.auth_user_id is not null)
  execute function public.mark_invites_accepted();

-- Wat nu al gekoppeld is en nog openstaat, meteen rechttrekken.
update player_invites i
set accepted_at = now()
from players p
where i.accepted_at is null
  and p.auth_user_id is not null
  and (p.id = i.player_id or lower(p.email) = lower(i.email));

-- ---------------------------------------------------------------------------
-- 4. Wat het bestuur van een club ziet
-- ---------------------------------------------------------------------------
-- De verzender draait met de service-sleutel en heeft dit niet nodig; die
-- omzeilt RLS. Dit is voor het scherm: een club hoort te kunnen zien welke
-- uitnodigingen buiten zijn en welke bleven steken, want een adres met een
-- typfout erin corrigeer je aan de deur en nergens anders.

create or replace function public.club_invites(p_club_id uuid)
returns table (
  id           uuid,
  email        text,
  player_name  text,
  created_at   timestamptz,
  sent_at      timestamptz,
  accepted_at  timestamptz,
  attempts     int,
  last_error   text
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_service_context()
     and not public.has_club_role(p_club_id, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten' using errcode = 'insufficient_privilege';
  end if;

  return query
  select i.id, i.email, p.display_name, i.created_at, i.sent_at,
         i.accepted_at, i.attempts, i.last_error
  from player_invites i
  join players p on p.id = i.player_id
  where i.club_id = p_club_id
  order by i.created_at desc
  limit 200;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Rechten
-- ---------------------------------------------------------------------------

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    grant execute on function public.invite_lookup(text) to anon;
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function public.invite_lookup(text)   to authenticated;
    grant execute on function public.club_invites(uuid)    to authenticated;
  end if;
end $$;
