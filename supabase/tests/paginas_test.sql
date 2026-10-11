-- Tests voor de eigen pagina's van een club.
--
-- Drie dingen die stuk kunnen en die je pas merkt als het te laat is: een
-- concept dat per ongeluk publiek staat, een Franstalige bezoeker die een
-- leeg scherm krijgt omdat de vertaling nog ontbreekt, en een floor die het
-- reglement kan herschrijven.

begin;

do $$
declare
  v_club uuid; v_season uuid; v_rc uuid; v_id uuid;
  v_baas  uuid := gen_random_uuid();
  v_floor uuid := gen_random_uuid();
  v_slug text := 'pg-' || substr(gen_random_uuid()::text, 1, 10);
  v_rij record;
begin
  insert into auth.users (id, email) values
    (v_baas,  format('b-%s@test.be', substr(v_baas::text, 1, 8))),
    (v_floor, format('f-%s@test.be', substr(v_floor::text, 1, 8)));

  insert into clubs (slug, name, compliance)
  values (v_slug, 'Paginatest', jsonb_build_object('enforce', 'off'))
  returning id into v_club;
  insert into club_members (club_id, user_id, role) values
    (v_club, v_baas, 'owner'), (v_club, v_floor, 'floor');

  insert into ranking_configs (club_id, name, method, params)
  values (v_club, 'Telling', 'sqrt_ratio', '{"multiplier":10}'::jsonb)
  returning id into v_rc;
  insert into seasons (club_id, name, starts_on, ranking_config_id)
  values (v_club, 'League', current_date, v_rc)
  returning id into v_season;

  -- ------------------------------------------------- een concept blijft dicht
  insert into club_pages (club_id, season_id, slug, is_published,
                          title_nl, body_nl, title_en, body_en)
  values (v_club, v_season, 'reglement', false,
          'Reglement', '## Een
Tekst in het Nederlands.', 'Rules', '## One
Text in English.')
  returning id into v_id;

  assert not exists (select 1 from public.club_public_page(v_slug, 'reglement', 'nl')),
    'een ongepubliceerde pagina was publiek leesbaar';
  assert not exists (select 1 from public.club_public_pages(v_slug)),
    'een ongepubliceerde pagina stond in de lijst';
  raise notice 'OK  een concept is niet publiek';

  update club_pages set is_published = true where id = v_id;

  select * into v_rij from public.club_public_page(v_slug, 'reglement', 'nl');
  assert v_rij.title = 'Reglement', 'de Nederlandse titel kwam niet terug';
  assert v_rij.locale = 'nl', 'de taal klopte niet';
  assert v_rij.season_name = 'League', 'het seizoen kwam niet mee';
  raise notice 'OK  een gepubliceerde pagina is publiek leesbaar, met zijn seizoen erbij';

  -- --------------------------------------------- terugval op een andere taal
  -- Frans staat leeg. Dan hoort de bezoeker de Nederlandse tekst te krijgen
  -- én te weten dat het een terugval is, en geen leeg scherm.
  select * into v_rij from public.club_public_page(v_slug, 'reglement', 'fr');
  assert v_rij.body is not null and v_rij.body <> '',
    'een ontbrekende vertaling gaf een leeg scherm';
  assert v_rij.locale = 'nl',
    format('de terugval hoort nl te melden, meldde %s', v_rij.locale);
  raise notice 'OK  een ontbrekende vertaling valt terug en zegt dat ook';

  -- En met Frans erbij krijgt hij wél Frans.
  update club_pages set title_fr = 'Règlement', body_fr = 'Texte en français.' where id = v_id;
  select * into v_rij from public.club_public_page(v_slug, 'reglement', 'fr');
  assert v_rij.locale = 'fr' and v_rij.title = 'Règlement',
    'de Franse versie kwam niet terug nadat ze ingevuld was';
  raise notice 'OK  is de vertaling er wel, dan krijgt hij die';

  -- ------------------------------------------------- filteren op seizoen
  assert (select count(*) from public.club_public_pages(v_slug, v_season)) = 1,
    'de pagina van dit seizoen stond niet in de lijst';
  assert (select count(*) from public.club_public_pages(v_slug, gen_random_uuid())) = 0,
    'een pagina van een ander seizoen kwam toch mee';
  raise notice 'OK  pagina''s zijn per seizoen op te vragen';

  -- ------------------------------------------------------------ het adres
  begin
    insert into club_pages (club_id, slug, title_nl, body_nl)
    values (v_club, 'Geen Hoofdletters', 'x', 'y');
    raise exception 'een adres met hoofdletters en spaties werd aanvaard';
  exception when check_violation then
    raise notice 'OK  een adres moet kleine letters, cijfers en streepjes zijn';
  end;

  begin
    insert into club_pages (club_id, slug, title_nl, body_nl)
    values (v_club, 'reglement', 'x', 'y');
    raise exception 'twee pagina''s met hetzelfde adres werden aanvaard';
  exception when unique_violation then
    raise notice 'OK  hetzelfde adres kan maar één keer binnen een club';
  end;
end $$;

-- ---------------------------------------------------------------------------
-- Wie mag er schrijven
-- ---------------------------------------------------------------------------

do $$
declare
  v_club uuid; v_id uuid;
  v_baas  uuid := gen_random_uuid();
  v_floor uuid := gen_random_uuid();
  v_vreemd uuid := gen_random_uuid();
  v_slug text := 'pr-' || substr(gen_random_uuid()::text, 1, 10);
  v_n int;
begin
  insert into auth.users (id, email) values
    (v_baas,   format('b2-%s@test.be', substr(v_baas::text, 1, 8))),
    (v_floor,  format('f2-%s@test.be', substr(v_floor::text, 1, 8))),
    (v_vreemd, format('v2-%s@test.be', substr(v_vreemd::text, 1, 8)));

  insert into clubs (slug, name, compliance)
  values (v_slug, 'Rechtentest', jsonb_build_object('enforce', 'off'))
  returning id into v_club;
  insert into club_members (club_id, user_id, role) values
    (v_club, v_baas, 'owner'), (v_club, v_floor, 'floor');

  insert into club_pages (club_id, slug, is_published, title_nl, body_nl)
  values (v_club, 'huisregels', true, 'Huisregels', 'Tekst.')
  returning id into v_id;

  -- Een floor bedient de avond en herschrijft het reglement niet.
  perform set_config('request.jwt.claim.sub', v_floor::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  -- Echt van rol wisselen en niet alleen de claim zetten: postgres omzeilt
  -- row level security, en dan meet deze test niets.
  execute 'set local role authenticated';
  update club_pages set body_nl = 'Gewijzigd door de floor' where id = v_id;
  get diagnostics v_n = row_count;
  assert v_n = 0, 'een floor kon een pagina wijzigen';
  assert (select count(*) from club_pages where club_id = v_club) = 1,
    'een floor hoort de pagina wel te kunnen lezen';
  raise notice 'OK  een floor leest de pagina wel maar wijzigt ze niet';

  -- Een buitenstaander ziet hem niet eens in de tabel.
  perform set_config('request.jwt.claim.sub', v_vreemd::text, true);
  assert (select count(*) from club_pages where club_id = v_club) = 0,
    'een buitenstaander zag de pagina''s van een vreemde club';
  raise notice 'OK  een buitenstaander ziet de tabel niet';

  -- De eigenaar wel.
  perform set_config('request.jwt.claim.sub', v_baas::text, true);
  update club_pages set body_nl = 'Gewijzigd door de baas' where id = v_id;
  get diagnostics v_n = row_count;
  assert v_n = 1, 'de eigenaar kon zijn eigen pagina niet wijzigen';
  assert (select body_nl from club_pages where id = v_id) = 'Gewijzigd door de baas',
    'de wijziging kwam niet aan';
  raise notice 'OK  owner en admin mogen wel schrijven';

  -- En updated_at loopt mee, want anders zegt de pagina onderaan iets
  -- onwaars over wanneer ze voor het laatst veranderd is.
  --
  -- Niet te meten met "nieuwer dan created_at": binnen één transactie staat
  -- now() stil, dus die twee zijn hier per definitie gelijk. Wel te meten
  -- door een oude datum te proberen zetten — de trigger hoort hem te
  -- overschrijven, ook als de wijziging zelf een datum meebrengt.
  update club_pages set updated_at = now() - interval '5 days' where id = v_id;
  assert (select updated_at from club_pages where id = v_id) = now(),
    'updated_at liet zich op een oude datum zetten';
  raise notice 'OK  de datum onderaan de pagina wordt bij elke wijziging bijgewerkt';

  execute 'reset role';
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);
end $$;

rollback;
