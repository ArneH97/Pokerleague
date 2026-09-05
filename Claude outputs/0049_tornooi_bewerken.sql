-- Pokerleague — een tornooi bijstellen nadat het is aangemaakt
--
-- Tot nu was aanmaken een eenrichtingsstraat: je koos de blindstructuur, de
-- inleg en het prijzenschema in het aanmaakscherm, en daarna kon er niets meer
-- bij. Eén tikfout in de buy-in, of een structuur die pas ná het aanmaken werd
-- gebouwd, en er moest SQL aan te pas komen.
--
-- **Waarom één functie met een jsonb en geen achttien parameters.** Een
-- tornooi heeft twintig instelbare velden en er komen er nog bij. Een functie
-- met achttien argumenten moet bij elk nieuw veld opnieuw gedropt en
-- aangemaakt worden, en elke oproeper moet mee. Met een patch stuurt het
-- scherm alleen wat er veranderde, en blijft de rest onaangeroerd.
--
-- Dat kan hier veilig omdat de patch niet rechtstreeks in de tabel gaat:
-- `jsonb_populate_record` legt hem eerst over de bestaande rij, en daarna
-- schrijven we uitsluitend de kolommen die hieronder met naam genoemd staan.
-- Een sleutel die daar niet bij hoort — `club_id`, `status`, `level_idx` —
-- geeft een foutmelding in plaats van dat hij stilletjes genegeerd wordt. Wie
-- zich vertikt in een veldnaam hoort dat te merken.
--
-- **Wat er niet meer mag wijzigen, en waarom.**
--
--   * De blindstructuur, zodra de klok gelopen heeft. Een tornooi onthoudt op
--     welk levelnummer het staat, niet welke blinds daarbij horen. Verwissel
--     je de structuur halverwege, dan springt de zaal naar level 7 van de
--     nieuwe structuur — met andere blinds dan wat er op tafel ligt.
--   * Alles behalve de naam, de notitie en de zichtbaarheid, zodra de avond
--     afgelopen is. Daar zijn de uitslagen berekend, de punten toegekend en
--     het geld verdeeld. Wie dáár nog aan wil rekenen, hoort dat niet via een
--     bewerkscherm te doen.
--
-- **Wat wél mag terwijl er al spelers zitten.** De inleg bijstellen. Dat
-- klinkt gevaarlijk en is het niet: elke inkoop staat als eigen rij in
-- `buyins` met het bedrag van dát moment. De prijzenpot is de som van die
-- rijen, niet een herberekening achteraf. Wie om acht uur merkt dat er € 35
-- staat in plaats van € 40, zet het recht voor de rest van de avond zonder dat
-- de eerste vier spelers ineens iets anders betaald blijken te hebben.

create or replace function public.update_tournament(
  p_tournament_id uuid,
  p_patch         jsonb
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  t       tournaments%rowtype;
  v_new   tournaments%rowtype;
  v_sleutel text;
  v_klok  boolean;

  -- Wat een mens mag bijstellen. Alles wat hier niet in staat, hoort bij de
  -- floor (de klok, de status) of bij de databank (de club, het id).
  c_toegestaan constant text[] := array[
    'name', 'notes', 'scheduled_at', 'player_visibility',
    'season_id', 'structure_id', 'payout_template_id',
    'buyin_cents', 'fee_cents', 'rebuy_cents', 'rebuy_fee_cents',
    'addon_cents', 'addon_fee_cents', 'addon_stack',
    'bounty_mode', 'bounty_cents',
    'starting_stack', 'max_reentries', 'late_reg_level',
    'prereg_bonus_stack'
  ];
  -- En hiervan blijft er ná afloop nog iets over: een verkeerd gespelde naam
  -- mag je altijd rechtzetten.
  c_na_afloop constant text[] := array['name', 'notes', 'player_visibility'];
begin
  select * into t from tournaments where id = p_tournament_id;
  if not found then
    raise exception 'Tornooi bestaat niet';
  end if;

  if not public.is_service_context()
     and not public.has_club_role(t.club_id, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten om dit tornooi te wijzigen'
      using errcode = 'insufficient_privilege';
  end if;

  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then
    raise exception 'Geef een object mee met de velden die moeten wijzigen'
      using errcode = 'check_violation';
  end if;

  for v_sleutel in select jsonb_object_keys(p_patch) loop
    if not (v_sleutel = any(c_toegestaan)) then
      raise exception 'Het veld "%" kan hier niet gewijzigd worden.', v_sleutel
        using errcode = 'check_violation';
    end if;
    if t.status in ('finished', 'cancelled') and not (v_sleutel = any(c_na_afloop)) then
      raise exception 'Deze avond is afgelopen. Alleen de naam en de zichtbaarheid kunnen nog wijzigen, "%" niet.', v_sleutel
        using errcode = 'check_violation';
    end if;
  end loop;

  -- De patch over de bestaande rij leggen. Wat niet in de patch staat, houdt
  -- zijn huidige waarde.
  v_new := jsonb_populate_record(t, p_patch);

  v_klok := t.started_at is not null or t.level_idx > 0;
  if v_new.structure_id is distinct from t.structure_id and v_klok then
    raise exception 'De klok van deze avond heeft al gelopen. De blindstructuur wisselen zou de zaal naar een ander level sturen dan wat er op tafel ligt.'
      using errcode = 'check_violation';
  end if;

  if v_new.starting_stack <= 0 then
    raise exception 'De startstapel moet groter zijn dan nul' using errcode = 'check_violation';
  end if;

  if least(
       v_new.buyin_cents, v_new.fee_cents, v_new.bounty_cents,
       coalesce(v_new.rebuy_cents, 0), coalesce(v_new.rebuy_fee_cents, 0),
       coalesce(v_new.addon_cents, 0), coalesce(v_new.addon_fee_cents, 0),
       v_new.prereg_bonus_stack, v_new.max_reentries
     ) < 0 then
    raise exception 'Bedragen en aantallen kunnen niet negatief zijn' using errcode = 'check_violation';
  end if;

  update tournaments set
    name               = v_new.name,
    notes              = v_new.notes,
    scheduled_at       = v_new.scheduled_at,
    player_visibility  = v_new.player_visibility,
    season_id          = v_new.season_id,
    structure_id       = v_new.structure_id,
    payout_template_id = v_new.payout_template_id,
    buyin_cents        = v_new.buyin_cents,
    fee_cents          = v_new.fee_cents,
    rebuy_cents        = v_new.rebuy_cents,
    rebuy_fee_cents    = v_new.rebuy_fee_cents,
    addon_cents        = v_new.addon_cents,
    addon_fee_cents    = v_new.addon_fee_cents,
    addon_stack        = v_new.addon_stack,
    bounty_mode        = v_new.bounty_mode,
    bounty_cents       = v_new.bounty_cents,
    starting_stack     = v_new.starting_stack,
    max_reentries      = v_new.max_reentries,
    late_reg_level     = v_new.late_reg_level,
    prereg_bonus_stack = v_new.prereg_bonus_stack
  where id = p_tournament_id;
end;
$$;

comment on function public.update_tournament(uuid, jsonb) is
  'Stelt een bestaand tornooi bij. Alleen staf van de club; alleen de velden uit de witte lijst; de blindstructuur niet meer zodra de klok gelopen heeft; na afloop enkel nog naam, notitie en zichtbaarheid.';

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function public.update_tournament(uuid, jsonb) to authenticated;
  end if;
end $$;
