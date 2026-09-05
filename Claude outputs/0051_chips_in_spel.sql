-- Pokerleague — hoeveel chips er écht in spel zijn
--
-- Op het zaalscherm en in het dealpaneel staat "chips in spel". Dat getal werd
-- geraden uit de tellers: elke inkoop, rebuy en re-entry één startstapel, elke
-- addon een addonstapel. Sinds vanmiddag klopt dat op twee punten niet meer.
--
--   * **De bonus van de voorinschrijving stond er nooit in.** Wie vooraf
--     inschrijft begint met 45.000 en niet met 40.000. Met twintig van die
--     spelers zit er 100.000 aan chips op tafel die het scherm niet kent — en
--     dan lijkt het alsof er een fiches-la verdwenen is terwijl alles klopt.
--   * **Een rebuy legt niet langer een startstapel bíj.** Hij zet de stapel op
--     de startstapel (zie 0050). Wie met 8.000 opnieuw inkocht, brengt er dus
--     32.000 bij en geen 40.000.
--
-- Raden is hier ook niet nodig, want elke inkoop staat al als eigen rij in het
-- geldregister. Er ontbrak alleen een kolom: hoeveel chips die inkoop op tafel
-- legde. Vanaf nu staat dat erbij, en is "chips in spel" gewoon de som van die
-- kolom — even hard als de prijzenpot, en met dezelfde herkomst.
--
-- **Waarom een trigger en niet een regel in elke functie.** De twee functies
-- die inkopen boeken zijn de drukste van de avond en samen driehonderd regels.
-- Ze allebei herschrijven om er één berekening in te weven, daags voor een
-- opening, is precies het soort verandering waarvan je 's nachts wakker ligt.
-- Een trigger op `buyins` heeft alles wat hij nodig heeft — het tornooi en de
-- stapel van de speler op dat moment — en laat die functies met rust.
--
-- Dat werkt omdat beide functies dezelfde volgorde aanhouden. Bij een eerste
-- inkoop bestaat de deelnemersrij al, mét de bonus erin; bij een rebuy is de
-- stapel nog die van vóór de inkoop. Precies wat er nodig is.

alter table buyins
  add column if not exists chips_delta int;

comment on column public.buyins.chips_delta is
  'Hoeveel chips deze inkoop op tafel legde. Bij een eerste inkoop de startstapel plus een eventuele bonus voor voorinschrijving; bij een rebuy het verschil met wat de speler nog had; bij een re-entry een verse startstapel; bij een addon de addonstapel. De som over alle niet-geschrapte rijen is het aantal chips in spel.';

-- ---------------------------------------------------------------------------
-- 1. De berekening, één keer, op de rand van de tabel
-- ---------------------------------------------------------------------------

create or replace function public.set_buyin_chip_delta()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  t  tournaments%rowtype;
  tp tournament_players%rowtype;
begin
  -- Wie het zelf meegeeft, weet het beter. Laat staan.
  if new.chips_delta is not null then
    return new;
  end if;

  select * into t  from tournaments        where id = new.tournament_id;
  select * into tp from tournament_players where id = new.tournament_player_id;

  new.chips_delta := case new.kind
    -- De eerste inkoop: de stapel die de speler zojuist kreeg, bonus en al.
    when 'buyin'   then coalesce(tp.chip_count, t.starting_stack)
    -- Een addon is een extra portie bovenop wat er ligt.
    when 'addon'   then coalesce(t.addon_stack, t.starting_stack)
    -- Een rebuy vervangt de stapel: er komt bij wat het verschil is met wat
    -- de speler nog had liggen.
    when 'rebuy'   then greatest(0, t.starting_stack - coalesce(tp.chip_count, 0))
    -- Een re-entry: de speler lag eruit en zijn chips telden al niet meer mee,
    -- dus dit is een volle verse stapel.
    else t.starting_stack
  end;

  return new;
end;
$$;

drop trigger if exists buyins_chip_delta on buyins;
create trigger buyins_chip_delta
  before insert on buyins
  for each row execute function public.set_buyin_chip_delta();

-- ---------------------------------------------------------------------------
-- 2. Wat er al geboekt is
-- ---------------------------------------------------------------------------
-- Bestaande rijen krijgen wat er destijds gebeurde, en niet wat er vandaag zou
-- gebeuren: tot 0050 legde een rebuy wél een volle startstapel bij. Een oude
-- avond hoort achteraf niet van cijfers te veranderen.

update buyins b
set chips_delta = case b.kind
  when 'addon' then coalesce(t.addon_stack, t.starting_stack)
  else t.starting_stack
end
from tournaments t
where t.id = b.tournament_id
  and b.chips_delta is null;

-- ---------------------------------------------------------------------------
-- 3. Het getal zelf
-- ---------------------------------------------------------------------------
-- Voor de zaalklok en het dealpaneel. Leesbaar voor wie het tornooi mag zien —
-- dit is een totaal en geen bedrag, en het staat op het scherm in de zaal.

create or replace function public.chips_in_play(p_tournament_id uuid)
returns int
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(sum(b.chips_delta), 0)::int
  from buyins b
  where b.tournament_id = p_tournament_id
    and not b.is_void
    and public.can_view_tournament(p_tournament_id);
$$;

comment on function public.chips_in_play(uuid) is
  'Hoeveel chips er in spel horen te zijn, uit het geldregister en niet uit wat spelers doorgeven. IJkpunt bij het tellen aan de finaletafel.';

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function public.chips_in_play(uuid) to authenticated;
  end if;
  if exists (select 1 from pg_roles where rolname = 'anon') then
    grant execute on function public.chips_in_play(uuid) to anon;
  end if;
end $$;
