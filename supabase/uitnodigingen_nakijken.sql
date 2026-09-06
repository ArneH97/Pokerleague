-- Pokerleague — waarom kreeg die speler geen mail?
--
-- Draai dit in de SQL-editor van Supabase. Deel 1 tot 4 veranderen niets; ze
-- tonen alleen wat er staat en waarom de verzender iemand overslaat. Deel 5 is
-- de knop om een uitnodiging opnieuw klaar te zetten, en die staat standaard
-- uit.
--
-- **Lees dit eerst, want het scheelt je vaak het hele onderzoek.** Een
-- uitnodiging is een gemak, geen sleutel. Wie zich inschreef met een
-- e-mailadres kan gewoon zelf naar pokerleague.be/registreren gaan en daar een
-- account maken met *exact datzelfde adres*. Zijn profiel — inschrijving,
-- resultaten, punten — wordt dan automatisch aan dat account gekoppeld op basis
-- van het geverifieerde mailadres. Hij hoeft nooit op een uitnodigingslink te
-- klikken.
--
-- Dus: krijgt iemand zijn mail niet, dan is "ga naar pokerleague.be/registreren
-- met hetzelfde adres" het antwoord dat vandaag werkt. De rest hieronder is om
-- uit te zoeken waaróm die mail niet vertrok, zodat het de volgende keer wel
-- goed gaat.

-- ---------------------------------------------------------------------------
-- 1. Ingeschreven voor een komend tornooi, maar nog geen account
-- ---------------------------------------------------------------------------
-- Dit is meestal waar je naar op zoek bent. Per persoon: heeft hij een
-- uitnodiging, is die vertrokken, en wat ging er mis.
select
  p.display_name                                   as speler,
  p.email,
  t.name                                           as tornooi,
  to_char(r.created_at, 'dd/mm HH24:MI')           as ingeschreven,
  case
    when i.id is null              then 'GEEN uitnodiging aangemaakt'
    when i.accepted_at is not null then 'afgevinkt — account bestaat al'
    when i.sent_at is not null     then 'mail vertrokken op '
                                        || to_char(i.sent_at, 'dd/mm HH24:MI')
    when i.attempts >= 3           then 'opgegeven na 3 pogingen'
    when i.expires_at <= now()     then 'verlopen'
    else                                'staat in de wachtrij'
  end                                              as uitnodiging,
  i.attempts                                       as pogingen,
  i.last_error                                     as laatste_fout
from tournament_registrations r
join tournaments t on t.id = r.tournament_id
join clubs       c on c.id = t.club_id
join players     p on p.id = r.player_id
left join player_invites i
       on i.player_id = p.id and i.club_id = c.id
where c.slug = 'cutoff'
  and r.cancelled_at is null
  and p.auth_user_id is null
  and p.merged_into_id is null
order by t.scheduled_at, p.display_name;

-- ---------------------------------------------------------------------------
-- 2. Alle uitnodigingen van Cutoff
-- ---------------------------------------------------------------------------
select
  i.email,
  p.display_name,
  to_char(i.created_at,  'dd/mm HH24:MI')          as aangemaakt,
  to_char(i.sent_at,     'dd/mm HH24:MI')          as verstuurd,
  to_char(i.last_try_at, 'dd/mm HH24:MI')          as laatste_poging,
  i.attempts                                       as pogingen,
  i.last_error                                     as laatste_fout,
  i.expires_at::date                               as geldig_tot,
  p.auth_user_id is not null                       as heeft_al_account,
  case
    when i.accepted_at is not null then 'afgevinkt — account bestaat al'
    when i.sent_at is not null     then 'al verstuurd'
    when i.attempts >= 3           then 'opgegeven na 3 pogingen'
    when i.expires_at <= now()     then 'verlopen'
    else                                'STAAT IN DE WACHTRIJ'
  end                                              as waarom
from player_invites i
join players p on p.id = i.player_id
join clubs   c on c.id = i.club_id
where c.slug = 'cutoff'
order by i.created_at desc;

-- ---------------------------------------------------------------------------
-- 3. Leden van Cutoff met een mailadres maar zonder account
-- ---------------------------------------------------------------------------
-- Staat hier iemand die in lijst 2 ontbreekt, dan is de uitnodiging nooit
-- aangemaakt. Dat is een gat in de inschrijving, niet in de verzender.
select
  p.display_name,
  p.email,
  p.locale,
  p.link_state,
  exists (
    select 1 from player_invites i
    where i.club_id = c.id and i.player_id = p.id
  ) as heeft_uitnodiging
from club_players cp
join clubs   c on c.id = cp.club_id
join players p on p.id = cp.player_id
where c.slug = 'cutoff'
  and p.email is not null
  and p.auth_user_id is null
  and p.merged_into_id is null
order by p.display_name;

-- ---------------------------------------------------------------------------
-- 4. Mag jouw account de wachtrij überhaupt zien?
-- ---------------------------------------------------------------------------
-- De verzender draait op jouw sessie en RLS filtert mee. Sta je hier niet als
-- owner of admin van cutoff, dan ziet hij niets — ongeacht wat er in de tabel
-- staat.
select u.email, m.role, c.slug
from club_members m
join clubs c      on c.id = m.club_id
join auth.users u on u.id = m.user_id
where c.slug = 'cutoff'
order by m.role;

-- ---------------------------------------------------------------------------
-- 5. Een uitnodiging opnieuw klaarzetten
-- ---------------------------------------------------------------------------
-- Zet `c_doe_het` op true en vul het adres in. Dit zet de teller op nul, geeft
-- er weer 30 dagen op en haalt `sent_at` weg, zodat de cron hem bij de
-- volgende ronde (elk kwartier) opnieuw probeert.
--
-- Doe dit pas als je wéét dat het versturen nu werkt — anders stuur je hem
-- gewoon opnieuw de muur in. Staat er bij `laatste_fout` iets over een
-- ontbrekende sleutel, kijk dan eerst op Vercel of RESEND_API_KEY en MAIL_FROM
-- ingesteld staan.

do $$
declare
  c_doe_het boolean := false;
  c_email   text    := 'vul.hier@in.be';

  v_club uuid;
  v_n    int;
begin
  if not c_doe_het then
    raise notice 'Deel 5 staat uit. Zet c_doe_het op true en vul een adres in om een uitnodiging opnieuw klaar te zetten.';
    return;
  end if;

  select id into v_club from clubs where slug = 'cutoff';

  update player_invites i
  set attempts   = 0,
      sent_at    = null,
      last_error = null,
      expires_at = now() + interval '30 days'
  where i.club_id = v_club
    and lower(i.email) = lower(trim(c_email))
    and i.accepted_at is null;
  get diagnostics v_n = row_count;

  if v_n = 0 then
    raise notice 'Geen openstaande uitnodiging op % bij cutoff. Kijk in lijst 1 of hij er wel eentje heeft.', c_email;
  else
    raise notice 'OK  % uitnodiging(en) op % staan weer in de wachtrij. De cron probeert het binnen het kwartier.', v_n, c_email;
  end if;
end $$;
