-- Tests voor de stafrollen van een club.
--
-- De aanleiding is een fout die pas bij de tweede medewerker zichtbaar werd.
-- `getClubRole` haalde de rol op met `where club_id = ...` en niets meer, en
-- nam aan dat daar één rij uit komt. Dat klopt zolang een club één medewerker
-- heeft. De leespolicy laat een medewerker echter álle stafrijen van zijn club
-- zien — met opzet, daar moet ooit een medewerkersscherm op draaien — dus bij
-- twee medewerkers kwamen er twee rijen terug, viel de query om, en was
-- iedereen zijn toegang kwijt. De eigenaar incluis.
--
-- Deze test legt allebei de helften vast: de policy mag ze zien, én ieder ziet
-- precies één rij als er op zichzelf gefilterd wordt.

begin;

do $$
declare
  v_club uuid;
  v_arne uuid := gen_random_uuid();
  v_jul  uuid := gen_random_uuid();
  v_vreemd uuid := gen_random_uuid();
  v_n    int;
  v_rol  text;
begin
  insert into auth.users (id, email) values
    (v_arne, format('baas-%s@test.be', substr(v_arne::text, 1, 8))),
    (v_jul,  format('tweede-%s@test.be', substr(v_jul::text, 1, 8))),
    (v_vreemd, format('vreemd-%s@test.be', substr(v_vreemd::text, 1, 8)));

  insert into clubs (slug, name, compliance)
  values ('st-' || substr(gen_random_uuid()::text, 1, 12), 'Staftest',
          jsonb_build_object('enforce','off'))
  returning id into v_club;

  insert into club_members (club_id, user_id, role) values (v_club, v_arne, 'owner');

  -- ------------------------------------------------- één medewerker: geen probleem
  perform set_config('request.jwt.claim.sub', v_arne::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  set local role authenticated;

  select count(*) into v_n from club_members where club_id = v_club;
  assert v_n = 1, format('met één medewerker hoort er één rij te zijn, kreeg %s', v_n);
  raise notice 'OK  met één medewerker geeft de rolquery één rij';

  reset role;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);

  -- ------------------------------------------------- en dan komt de tweede
  insert into club_members (club_id, user_id, role) values (v_club, v_jul, 'admin');

  perform set_config('request.jwt.claim.sub', v_arne::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  set local role authenticated;

  -- Dit is de val. Zien mág, en dat blijft zo — maar wie hier één rij
  -- verwacht, breekt vanaf hier.
  select count(*) into v_n from club_members where club_id = v_club;
  assert v_n = 2,
    format('een medewerker hoort alle stafrijen van zijn club te zien, kreeg %s', v_n);
  raise notice 'OK  een medewerker ziet de hele staf van zijn club (%s rijen)', v_n;

  -- En zo hoort de rol opgehaald te worden: mét het filter op de gebruiker.
  select count(*) into v_n from club_members
   where club_id = v_club and user_id = auth.uid();
  assert v_n = 1,
    format('met het filter op user_id hoort er precies één rij te zijn, kreeg %s', v_n);

  select role::text into v_rol from club_members
   where club_id = v_club and user_id = auth.uid();
  assert v_rol = 'owner', format('de eigenaar hoort owner te blijven, kreeg %s', v_rol);
  raise notice 'OK  met het filter op user_id houdt de eigenaar zijn rol, ook naast een tweede medewerker';

  -- De tweede medewerker krijgt zijn eigen rol, niet die van de eerste.
  reset role;
  perform set_config('request.jwt.claim.sub', v_jul::text, true);
  set local role authenticated;

  select role::text into v_rol from club_members
   where club_id = v_club and user_id = auth.uid();
  assert v_rol = 'admin', format('de tweede medewerker hoort admin te zijn, kreeg %s', v_rol);
  raise notice 'OK  de tweede medewerker krijgt zijn eigen rol';

  -- ------------------------------------------------------ en een buitenstaander
  reset role;
  perform set_config('request.jwt.claim.sub', v_vreemd::text, true);
  set local role authenticated;

  select count(*) into v_n from club_members where club_id = v_club;
  assert v_n = 0, format('een buitenstaander hoort niets te zien, kreeg %s', v_n);
  raise notice 'OK  een buitenstaander ziet de staf van de club niet';

  reset role;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);
end $$;

rollback;
