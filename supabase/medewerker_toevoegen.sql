-- Pokerleague — iemand toegang geven tot een clubomgeving
--
-- Vier rollen, van veel naar weinig:
--
--   owner  — alles, inclusief de clubinstellingen en het aanstellen van
--            andere medewerkers. Meestal één of twee mensen.
--   admin  — alles behalve de club zelf: tornooien, leden, structuren.
--   floor  — de avond zelf: tornooi aanmaken, spelers toevoegen, herinkopen,
--            uitschakelen, uitbetalen, afsluiten. Dit is wat een floor nodig
--            heeft en niet meer.
--   viewer — meekijken, niets wijzigen.
--
-- VOORAF: de persoon maakt eerst zelf een account op
-- pokerleague.be/registreren. Eén account volstaat — hij is daarmee speler op
-- het platform én medewerker bij de club. Bestaat dat account nog niet, dan
-- zegt dit script dat en doet het verder niets.
--
-- Draaien in de SQL-editor van Supabase.

do $$
declare
  -- ------------------------------------------------------------- instellen
  c_slug  text := 'aalst';
  c_email text := 'vul.hier@in.be';
  c_role  text := 'floor';          -- 'owner' | 'admin' | 'floor' | 'viewer'
  -- -------------------------------------------------------------

  v_club uuid;
  v_user uuid;
begin
  select id into v_club from clubs where slug = c_slug;
  if v_club is null then
    raise exception 'Geen club met slug %.', c_slug;
  end if;

  select id into v_user from auth.users where lower(email) = lower(c_email);
  if v_user is null then
    raise notice 'Nog geen account voor %. Laat hem eerst registreren op pokerleague.be/registreren en draai dit dan opnieuw.', c_email;
    return;
  end if;

  insert into club_members (club_id, user_id, role)
  values (v_club, v_user, c_role::club_role)
  on conflict (club_id, user_id) do update set role = excluded.role;

  raise notice '% heeft nu de rol % bij %.', c_email, c_role, c_slug;
end $$;

-- Wie er nu toegang heeft.
select c.slug, u.email, m.role, m.created_at::date as sinds
from club_members m
join clubs c      on c.id = m.club_id
join auth.users u on u.id = m.user_id
order by c.slug, m.role;
