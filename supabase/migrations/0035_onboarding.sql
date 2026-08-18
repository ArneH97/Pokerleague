-- Pokerleague — de eerste vijf minuten van een speler
--
-- Wie zijn mailadres bevestigt, komt binnen op een platform dat hij niet kent
-- en waar nog niets van hem staat. Tot nu belandde hij op zijn profielpagina:
-- nul avonden, nul clubs, nul prijzengeld. Technisch juist en menselijk
-- waardeloos — het ziet eruit alsof er iets misging.
--
-- Er zijn precies twee dingen die op dat moment nodig zijn, en ze zijn allebei
-- iets wat alleen híj kan invullen:
--
--   * **bij welke clubs hoort hij.** Zonder dat is het platform leeg, en het
--     is de enige vraag waarvan het antwoord meteen iets oplevert.
--   * **wat mag er van hem te zien zijn.** Dat is een toestemming, en die vraag
--     hoort gesteld te worden voordat er iets te tonen valt — niet weggestopt
--     in een instellingenscherm dat hij nooit opent.
--
-- Eén veld volstaat om te weten of dat gebeurd is.

alter table players
  add column if not exists onboarded_at timestamptz;

comment on column players.onboarded_at is
  'Wanneer deze speler het welkomstscherm doorlopen heeft. Leeg betekent: stuur hem daar eerst naartoe. Bewust een tijdstip en geen boolean — zo weet je later ook wanneer iemand binnenkwam, en kan je zien of een wijziging aan dat scherm iets veranderde.';

create or replace function public.finish_onboarding()
returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  update players
  set onboarded_at = coalesce(onboarded_at, now())
  where auth_user_id = auth.uid() and merged_into_id is null
$$;

comment on function public.finish_onboarding() is
  'Vinkt het welkomstscherm af. Coalesce en geen simpele toewijzing: wie het scherm later nog eens opent, hoort niet plots een nieuwe begindatum te krijgen.';

-- `my_player` geeft dit veld nog niet terug, en de startpagina moet het weten
-- zonder een tweede query. Dezelfde kolommen als in 0026, met één erbij.
--
-- Eerst weggooien, niet vervangen: `create or replace` weigert zodra het
-- rijtype verandert, en een kolom toevoegen aan een `returns table` is precies
-- dat. Zonder deze regel loopt de migratie stuk op een fout die niets zegt
-- over wat er aan de hand is.

drop function if exists public.my_player();

create or replace function public.my_player()
returns table (
  id             uuid,
  display_name   text,
  first_name     text,
  last_name      text,
  username       text,
  email          text,
  locale         text,
  public_listing boolean,
  public_profile boolean,
  onboarded_at   timestamptz,
  clubs_count    int,
  results_count  int
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    p.id, p.display_name, p.first_name, p.last_name, p.username, p.email,
    p.locale, p.public_listing, p.public_profile, p.onboarded_at,
    (select count(*)::int from club_players cp where cp.player_id = p.id),
    (select count(*)::int from tournament_results r where r.player_id = p.id)
  from players p
  where p.auth_user_id = auth.uid() and p.merged_into_id is null
$$;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function public.finish_onboarding() to authenticated;
    grant execute on function public.my_player()         to authenticated;
  end if;
end $$;
