-- Pokerleague — een sessie die hoort bij een account dat niet meer bestaat
--
-- Dit is geen randgeval dat ooit eens kan gebeuren; het overkwam ons meteen na
-- het opruimen van de testaccounts. En je komt er zelf niet meer uit.
--
-- Hoe het ontstaat: een aanmeldtoken is ondertekend en geldig tot het vervalt.
-- Supabase controleert bij elk verzoek die handtekening, niet of de gebruiker
-- nog bestaat. Verwijder je het account — door op te ruimen, of omdat iemand
-- zichzelf uitschrijft — dan blijft het token in de browser gewoon werken.
-- `auth.uid()` geeft dan een id terug dat nergens meer in `auth.users` staat.
--
-- Wat er dan gebeurde: `claim_my_player` probeerde een profiel aan te maken met
-- die verwijzing, de vreemde sleutel weigerde, en de speler kreeg
-- "insert or update on table players violates foreign key constraint". Een
-- melding die klopt, niets uitlegt, en — dit is het ergste — bij elke
-- verversing terugkomt. Zonder zijn koekjes te wissen komt hij er niet uit.
--
-- De oplossing is niet dat we die verwijzing losser maken. Ze klopt: een
-- profiel dat aan een account hangt hoort aan een bestaand account te hangen.
-- Wat mankeerde is dat niemand het uitlegde. Nu herkent de functie de toestand
-- en zegt ze wat er aan de hand is, met een foutcode waar het scherm iets mee
-- kan: afmelden en opnieuw aanmelden.

create or replace function public.claim_my_player(
  p_first_name text default null,
  p_last_name  text default null,
  p_username   text default null,
  p_listing    boolean default null,
  p_locale     text default null,
  p_birthdate  date default null,
  p_consent    boolean default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid    uuid  := auth.uid();
  v_email  text  := public.auth_email();
  v_meta   jsonb := public.auth_meta();
  v_id     uuid;
  v_first  text    := coalesce(nullif(trim(p_first_name), ''), nullif(trim(v_meta->>'first_name'), ''));
  v_last   text    := coalesce(nullif(trim(p_last_name),  ''), nullif(trim(v_meta->>'last_name'),  ''));
  v_want   text    := coalesce(nullif(trim(p_username),   ''), nullif(trim(v_meta->>'username'),   ''));
  v_user   text;
  v_list   boolean := coalesce(p_listing, (v_meta->>'public_listing')::boolean, false);
  v_full   text    := nullif(trim(coalesce(v_first, '') || ' ' || coalesce(v_last, '')), '');

  v_arg_locale text := public.norm_locale(p_locale);
  v_new_locale text := coalesce(public.norm_locale(p_locale),
                                public.norm_locale(v_meta->>'locale'));

  v_birth   date    := coalesce(p_birthdate, nullif(v_meta->>'birthdate', '')::date);
  v_consent boolean := coalesce(p_consent, (v_meta->>'stats_consent')::boolean, false);
  v_when    timestamptz := case when v_consent then now() else null end;
begin
  if v_uid is null then
    raise exception 'Niet aangemeld' using errcode = 'insufficient_privilege';
  end if;

  -- Het token is geldig, maar hoort het nog bij iemand? Deze controle staat
  -- vóór alle andere, want zonder bestaand account is elke volgende regel
  -- zinloos. SQLSTATE 28000 zodat het scherm dit geval kan herkennen en zelf
  -- kan afmelden in plaats van dezelfde fout te blijven tonen.
  if not exists (select 1 from auth.users where id = v_uid) then
    raise exception 'Je sessie hoort bij een account dat niet meer bestaat. Meld je opnieuw aan.'
      using errcode = '28000';
  end if;

  if v_email is null then
    raise exception 'Dit account heeft geen mailadres' using errcode = 'check_violation';
  end if;

  if v_birth is not null and public.age_on(v_birth, current_date) < 18 then
    raise exception 'Je moet 18 jaar zijn om een account te maken.'
      using errcode = 'check_violation';
  end if;

  -- Zie 0038: een bezette naam kost geen account.
  v_user := case when v_want is not null and public.username_available(v_want)
                 then v_want else null end;

  select id into v_id
  from players
  where auth_user_id = v_uid and merged_into_id is null;

  if found then
    update players
    set first_name       = coalesce(first_name, v_first),
        last_name        = coalesce(last_name,  v_last),
        username         = coalesce(username,   v_user),
        locale           = coalesce(v_arg_locale, locale),
        birthdate        = coalesce(birthdate, v_birth),
        stats_consent_at = coalesce(stats_consent_at, v_when),
        display_name     = case
          when v_full is not null and display_name = split_part(lower(v_email), '@', 1)
          then v_full else display_name end
    where id = v_id;
    return v_id;
  end if;

  select id into v_id
  from players
  where lower(email) = v_email
    and auth_user_id is null
    and merged_into_id is null
  limit 1;

  if found then
    update players
    set auth_user_id     = v_uid,
        link_state       = 'claimed',
        first_name       = coalesce(v_first, first_name),
        last_name        = coalesce(v_last,  last_name),
        username         = coalesce(username, v_user),
        display_name     = coalesce(v_full, display_name),
        locale           = coalesce(v_new_locale, locale),
        birthdate        = coalesce(v_birth, birthdate),
        stats_consent_at = coalesce(stats_consent_at, v_when),
        public_listing   = v_list
    where id = v_id;
    return v_id;
  end if;

  insert into players (
    display_name, first_name, last_name, username, email,
    auth_user_id, link_state, public_listing, locale, birthdate, stats_consent_at
  ) values (
    coalesce(v_full, v_user, split_part(v_email, '@', 1)),
    v_first, v_last, v_user, v_email, v_uid, 'claimed', v_list,
    coalesce(v_new_locale, 'nl'), v_birth, v_when
  )
  returning id into v_id;

  return v_id;
end;
$$;

comment on function public.claim_my_player(text, text, text, boolean, text, date, boolean) is
  'Koppelt de aangemelde gebruiker aan zijn spelersprofiel. Meermaals aanroepen is veilig. Een bezette gebruikersnaam wordt overgeslagen; een sessie van een verwijderd account geeft SQLSTATE 28000 terug zodat het scherm kan afmelden.';

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function public.claim_my_player(text, text, text, boolean, text, date, boolean)
      to authenticated;
  end if;
end $$;
