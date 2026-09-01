-- Pokerleague — een inschrijving weer van de lijst halen
--
-- Er stond al in de policies dat staf dit mag, maar er was geen weg om het te
-- doen. Dat is precies het soort halve functie waar je op de avond zelf tegen
-- de muur loopt: iemand die belt dat hij niet komt, een testinschrijving van
-- jezelf, of twee keer dezelfde man onder twee mailadressen — en de lijst
-- klopt niet meer terwijl je er wel op rekent voor het aantal tafels.
--
-- **Intrekken en niet verwijderen.** De rij blijft staan met een tijdstip in
-- `cancelled_at`. Dat kost niets en het scheelt op een avond dat iemand
-- terugkomt op zijn beslissing: schrijft hij zich later opnieuw in, dan pikt
-- `rsvp_for_tournament` dezelfde rij weer op in plaats van te struikelen over
-- de unieke sleutel. En achteraf is nog te zien hoeveel mensen zich
-- inschreven en weer afhaakten — dat cijfer wil je kennen voor de volgende
-- keer.

create or replace function public.cancel_rsvp(
  p_tournament_id uuid,
  p_player_id     uuid
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_club uuid;
  v_n    int;
begin
  select club_id into v_club from tournaments where id = p_tournament_id;
  if v_club is null then
    return false;
  end if;

  if not public.is_service_context()
     and not public.has_club_role(v_club, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten op de inschrijvingen van deze club'
      using errcode = 'insufficient_privilege';
  end if;

  update tournament_registrations
  set cancelled_at = now()
  where tournament_id = p_tournament_id
    and player_id = p_player_id
    and cancelled_at is null;

  get diagnostics v_n = row_count;
  return v_n > 0;
end;
$$;

comment on function public.cancel_rsvp(uuid, uuid) is
  'Haalt iemand weer van de lijst met vooraf ingeschrevenen. Alleen staf. De rij blijft bestaan met een tijdstip, zodat opnieuw inschrijven gewoon werkt.';

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    revoke all on function public.cancel_rsvp(uuid, uuid) from public;
    grant execute on function public.cancel_rsvp(uuid, uuid) to authenticated, service_role;
  end if;
end $$;
