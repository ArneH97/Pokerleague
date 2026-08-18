-- Pokerleague — Johan als floor bij Aalst Poker Club
--
-- Zijn account bestaat al (johanlooyens@icloud.com), dus dit is alles wat er
-- nog moet gebeuren. Draaien in de SQL-editor van Supabase.
--
-- Wat de rol `floor` mag: de avond zelf. Een tornooi aanmaken, spelers
-- toevoegen aan de deur, herinkopen en add-ons boeken, uitschakelen, de klok
-- bedienen, uitbetalen en afsluiten. Wat hij níét mag: de clubinstellingen
-- wijzigen of andere medewerkers aanstellen — daar is `admin` of `owner` voor.
-- Voor een test is dat precies de goede grens: alles wat een avond nodig
-- heeft, en niets waarmee hij de club per ongeluk kan omgooien.

do $$
declare
  c_slug  text := 'aalst';
  c_email text := 'johanlooyens@icloud.com';
  c_role  text := 'floor';

  v_club uuid;
  v_user uuid;
begin
  select id into v_club from clubs where slug = c_slug;
  if v_club is null then
    raise exception 'Geen club met slug %.', c_slug;
  end if;

  select id into v_user from auth.users where lower(email) = lower(c_email);
  if v_user is null then
    raise notice 'Nog geen account voor %. Laat hem eerst registreren op pokerleague.be/registreren.', c_email;
    return;
  end if;

  insert into club_members (club_id, user_id, role)
  values (v_club, v_user, c_role::club_role)
  on conflict (club_id, user_id) do update set role = excluded.role;

  raise notice '% is nu % bij %.', c_email, c_role, c_slug;
end $$;

-- Wie er toegang heeft, per club.
select c.name as club, u.email, m.role, m.created_at::date as sinds
from club_members m
join clubs c      on c.id = m.club_id
join auth.users u on u.id = m.user_id
order by c.name, m.role, u.email;
