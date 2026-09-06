-- Pokerleague — een speler handmatig bevestigen
--
-- **Dit is een noodgreep, geen oplossing.** Gebruik het om iemand die vast zit
-- meteen binnen te krijgen; de echte oplossing is een eigen SMTP-server
-- instellen bij Supabase (Authentication → SMTP Settings), want anders blijft
-- dit bij elke nieuwe speler opnieuw gebeuren.
--
-- **Waarom dit nodig is.** De standaard mailer van Supabase verstuurt alleen
-- naar de leden van je eigen Supabase-team. Elk ander adres wordt geweigerd met
-- "Email address not authorized" — de mail vertrekt dus niet, en de speler
-- blijft hangen op "je e-mailadres is nog niet bevestigd". Dat jij je eigen
-- bevestigingsmails wél kreeg, klopt met dat beeld: jij zit in dat team.
--
-- Wat dit script doet: het zet het adres van die ene speler op bevestigd, zodat
-- hij zich kan aanmelden. Verder niets. Zijn wachtwoord, zijn profiel en zijn
-- inschrijving blijven zoals ze zijn.
--
-- Draaien in de SQL-editor van Supabase.

do $$
declare
  -- ------------------------------------------------------------- invullen
  c_email text := 'vul.hier@in.be';
  -- -------------------------------------------------------------

  v_user   uuid;
  v_bevest timestamptz;
  v_naam   text;
begin
  if c_email = 'vul.hier@in.be' then
    raise exception 'Vul eerst het e-mailadres in bovenaan het blok.';
  end if;

  select u.id, (to_jsonb(u) ->> 'email_confirmed_at')::timestamptz
    into v_user, v_bevest
  from auth.users u
  where lower(u.email) = lower(trim(c_email));

  if v_user is null then
    raise exception 'Geen account op %. Laat hem eerst registreren op pokerleague.be/registreren.', c_email;
  end if;

  if v_bevest is not null then
    raise notice 'Het adres % is al bevestigd sinds %. Er is niets te doen.',
      c_email, to_char(v_bevest, 'dd/mm/yyyy HH24:MI');
    raise notice 'Raakt hij toch niet binnen, dan ligt het aan zijn wachtwoord en niet aan de bevestiging.';
    return;
  end if;

  update auth.users set email_confirmed_at = now() where id = v_user;

  select display_name into v_naam from players
  where auth_user_id = v_user and merged_into_id is null;

  raise notice 'OK  % is nu bevestigd. Hij kan zich aanmelden op pokerleague.be.',
    coalesce(v_naam, c_email);
  raise notice 'Vergeet de echte oplossing niet: eigen SMTP instellen bij Authentication -> SMTP Settings.';
end $$;

-- Wie er wacht op een bevestiging. Staan hier meerdere mensen, dan is het
-- zeker de mailer en niet die ene speler.
select
  u.email,
  coalesce(p.display_name, '—')          as speler,
  u.created_at::date                     as geregistreerd,
  case when (to_jsonb(u) ->> 'email_confirmed_at') is null
       then 'WACHT OP BEVESTIGING' else 'bevestigd' end as staat
from auth.users u
left join players p on p.auth_user_id = u.id and p.merged_into_id is null
order by (to_jsonb(u) ->> 'email_confirmed_at') is not null, u.created_at desc
limit 50;
