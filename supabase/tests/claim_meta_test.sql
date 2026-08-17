-- Pokerleague — de naam uit de registratie overleeft de omweg langs de mailbox
--
-- Het geval dat in de praktijk misging: iemand vult zijn naam in bij het
-- registreren, moet dan zijn adres bevestigen per mail, en komt terug op een
-- profiel dat "halsberghe.arne" heet — het stuk voor de apenstaart van zijn
-- mailadres. Op het moment dat hij terugkomt is het formulier allang weg.
--
-- De gegevens staan dan nog op een plek: het token. Deze test controleert dat
-- ze daar vandaan gehaald worden, en dat een profiel dat al zonder naam
-- bestond alsnog aangevuld wordt.
\set ON_ERROR_STOP on
begin;
do $$
declare v_uid uuid; v_id uuid; v_naam text; v_user text;
begin
  insert into auth.users (email) values ('meta@t28.be') returning id into v_uid;

  -- Precies de situatie na een bevestigingsmail: aangemeld, maar het
  -- formulier is allang weg. De gegevens zitten alleen nog in het token.
  perform set_config('request.jwt.claims', json_build_object(
    'sub', v_uid, 'role', 'authenticated', 'email', 'meta@t28.be',
    'user_metadata', json_build_object(
      'first_name', 'Arne', 'last_name', 'Halsberghe',
      'username', 'arneh', 'public_listing', true))::text, true);
  perform set_config('request.jwt.claim.sub', v_uid::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  v_id := public.claim_my_player();
  select display_name, username into v_naam, v_user from players where id = v_id;

  if v_naam <> 'Arne Halsberghe' then
    raise exception 'FOUT: naam uit de registratie niet overgenomen, kreeg %', v_naam;
  end if;
  if v_user <> 'arneh' then raise exception 'FOUT: gebruikersnaam kwijt, kreeg %', v_user; end if;
  if not (select public_listing from players where id = v_id) then
    raise exception 'FOUT: de toestemming uit de registratie is niet overgenomen';
  end if;
  raise notice 'OK  naam en gebruikersnaam komen uit de registratie, ook zonder formulier';

  -- En het geval van Arne: profiel bestaat al zonder naam, metadata wel.
  update players set first_name = null, last_name = null, username = null,
                     display_name = 'meta' where id = v_id;
  perform public.claim_my_player();
  select username into v_user from players where id = v_id;
  if v_user <> 'arneh' then raise exception 'FOUT: bestaand profiel niet aangevuld'; end if;
  raise notice 'OK  een profiel dat al zonder naam bestond wordt alsnog aangevuld';

  perform set_config('request.jwt.claims', '', true);
end $$;
rollback;
