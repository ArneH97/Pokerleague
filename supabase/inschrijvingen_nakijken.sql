-- Pokerleague — wie schreef er in, en wat is de stand van hun account
--
-- Eén blik op de trechter van de openingsavond. Verandert niets; je mag dit
-- zo vaak draaien als je wil.
--
-- De kolom `stand` is waar het om gaat:
--
--   heeft account   — hij kan aanmelden en ziet zijn eigen cijfers
--   uitnodiging weg — de mail is vertrokken, hij moet er alleen nog op klikken
--   mail wacht nog  — de uitnodiging staat klaar maar is nog niet verstuurd
--   geen mail       — er staat niets klaar; hij kan zich altijd nog gewoon
--                     registreren met hetzelfde adres
--
-- Dat laatste is geen probleem voor de avond zelf: zijn plaats staat vast en
-- de floor zet hem aan tafel. Het account is comfort achteraf.

select
  p.display_name                                   as naam,
  p.email                                          as mailadres,
  to_char(r.created_at at time zone 'Europe/Brussels', 'DD/MM HH24:MI') as ingeschreven,
  case
    when p.auth_user_id is not null then 'heeft account'
    when i.sent_at is not null      then 'uitnodiging weg'
    when i.id is not null           then 'mail wacht nog'
    else                                 'geen mail'
  end                                              as stand,
  case when tp.id is not null then 'ja' else '' end as aan_tafel
from tournament_registrations r
join tournaments t on t.id = r.tournament_id
join clubs c       on c.id = t.club_id
join players p     on p.id = r.player_id
left join lateral (
  select i.id, i.sent_at
  from player_invites i
  where i.player_id = p.id and i.club_id = c.id
  order by i.created_at desc
  limit 1
) i on true
left join tournament_players tp
  on tp.tournament_id = t.id and tp.player_id = p.id
where c.slug = 'cutoff'
  and r.cancelled_at is null
order by r.created_at;

-- De samenvatting.
--
-- Let op het onderscheid. Wie aan tafel gaat, wordt uit de lijst hierboven
-- gehaald — dat is de bedoeling, want je vinkt hem af. Om te weten hoeveel
-- mensen zich ooit inschreven, moet je dus óók de ingetrokken rijen meetellen
-- en het verschil maken tussen "geschrapt omdat hij binnen is" en "geschrapt
-- omdat hij afzegde".
select
  count(*)                                                   as ooit_ingeschreven,
  count(*) filter (where tp.id is not null)                  as al_aan_tafel,
  count(*) filter (where tp.id is null and r.cancelled_at is null)     as nog_verwacht,
  count(*) filter (where tp.id is null and r.cancelled_at is not null) as afgezegd,
  count(*) filter (where p.auth_user_id is not null)         as met_account
from tournament_registrations r
join tournaments t on t.id = r.tournament_id
join clubs c       on c.id = t.club_id
join players p     on p.id = r.player_id
left join tournament_players tp
  on tp.tournament_id = t.id and tp.player_id = p.id
where c.slug = 'cutoff';

-- Vertrekken de uitnodigingen eigenlijk? Staat hier een rij met `sent_at`
-- leeg en een `attempts` die oploopt, dan lukt het versturen niet en is er
-- iets mis met de mailinstellingen — zie docs/mail.md.
select
  p.email,
  i.created_at::date as klaargezet,
  i.sent_at,
  i.attempts,
  i.last_error
from player_invites i
join players p on p.id = i.player_id
join clubs c   on c.id = i.club_id
where c.slug = 'cutoff'
order by i.created_at desc
limit 20;
