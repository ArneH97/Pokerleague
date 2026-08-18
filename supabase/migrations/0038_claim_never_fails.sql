-- Pokerleague — een bezette gebruikersnaam mag geen account kosten
--
-- Wat er gebeurde: iemand bevestigt zijn mailadres, klikt op de link, en
-- krijgt "We konden je profiel niet vinden of aanmaken." Geen profiel, geen
-- uitleg, en een account dat in `auth.users` staat maar nergens anders.
--
-- De oorzaak zit één laag dieper dan hij lijkt. `claim_my_player` schreef de
-- gewenste gebruikersnaam gewoon mee in de insert. Was die intussen bezet —
-- door een ouder profiel, of doordat iemand in de tussentijd sneller was — dan
-- brak de unieke index de hele functie af. Het profiel kwam er niet, en alles
-- wat eraan hangt dus ook niet.
--
-- Dat is de verkeerde rangorde. **Het profiel is het punt; de gebruikersnaam
-- is een voorkeur.** Een voorkeur die niet lukt, hoort de zaak niet tegen te
-- houden — hij hoort opnieuw gevraagd te worden. Vandaar dat de naam hier
-- alleen nog meegaat als hij vrij is, en anders leeg blijft; het welkomstscherm
-- vraagt hem daarna alsnog, en dáár kan het wel misgaan zonder schade.
--
-- Het formulier controleert de beschikbaarheid al terwijl je typt (0036). Dat
-- blijft nuttig, maar het is een hulpmiddel en geen garantie: tussen de
-- controle en het opeisen zit een bevestigingsmail, en daar kan een dag
-- tussen zitten.

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
  if v_email is null then
    raise exception 'Dit account heeft geen mailadres' using errcode = 'check_violation';
  end if;

  if v_birth is not null and public.age_on(v_birth, current_date) < 18 then
    raise exception 'Je moet 18 jaar zijn om een account te maken.'
      using errcode = 'check_violation';
  end if;

  -- Alleen een naam die vrij is. Is hij bezet, dan gaat hij niet mee en blijft
  -- het veld leeg — het welkomstscherm vraagt hem opnieuw.
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
  'Koppelt de aangemelde gebruiker aan zijn spelersprofiel. Meermaals aanroepen is veilig. Een bezette gebruikersnaam wordt overgeslagen in plaats van de hele aanroep te laten mislukken: het profiel is het punt, de naam is een voorkeur.';

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function public.claim_my_player(text, text, text, boolean, text, date, boolean)
      to authenticated;
  end if;
end $$;
