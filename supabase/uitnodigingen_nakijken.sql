-- Pokerleague — waarom staat er niets in de wachtrij?
--
-- Draai dit in de SQL-editor van Supabase. Het verandert niets; het toont
-- alleen wat er staat en waarom de verzender het overslaat.

-- ---------------------------------------------------------------------------
-- 1. Alles wat er aan uitnodigingen bestaat voor Cutoff
-- ---------------------------------------------------------------------------
select
  i.email,
  p.display_name,
  i.created_at,
  i.sent_at,
  i.accepted_at,
  i.attempts,
  i.expires_at,
  p.auth_user_id is not null as heeft_al_account,
  case
    when i.sent_at is not null      then 'al verstuurd'
    when i.accepted_at is not null  then 'afgevinkt — account bestaat al'
    when i.attempts >= 3            then 'opgegeven na 3 pogingen'
    when i.expires_at <= now()      then 'verlopen'
    else 'STAAT IN DE WACHTRIJ'
  end as waarom
from player_invites i
join players p on p.id = i.player_id
join clubs   c on c.id = i.club_id
where c.slug = 'cutoff'
order by i.created_at desc;

-- ---------------------------------------------------------------------------
-- 2. Leden van Cutoff met een mailadres maar zonder account
-- ---------------------------------------------------------------------------
-- Dit zijn de mensen die een uitnodiging hóren te hebben. Staat hier iemand
-- die in lijst 1 ontbreekt, dan is de uitnodiging nooit aangemaakt — en dat
-- is een gat in floor_add_entry, niet in de verzender.
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
order by p.display_name;

-- ---------------------------------------------------------------------------
-- 3. Mag jouw account de wachtrij überhaupt zien?
-- ---------------------------------------------------------------------------
-- De verzender draait op jouw sessie en RLS filtert mee. Sta je hier niet als
-- owner of admin van cutoff, dan ziet hij niets — ongeacht wat er in de tabel
-- staat. (Dit toont álle staf; zoek je eigen mailadres.)
select
  u.email,
  m.role,
  c.slug
from club_members m
join clubs c      on c.id = m.club_id
join auth.users u on u.id = m.user_id
where c.slug = 'cutoff'
order by m.role;
