-- Pokerleague — alle testaccounts weg, de staf blijft
--
-- **Eerst het antwoord op je vraag: het is één tabel.** Er is geen aparte
-- ledentabel naast een beheerderstabel. Elk account — jouw beheerdersaccount
-- van Cutoff en elke speler die zich registreert — staat in `auth.users`. Wat
-- ze uit elkaar houdt is niet wáár ze staan maar wat eraan hangt:
--
--   * `club_members` koppelt een account aan een club met een rol. Dat is
--     wat iemand tot staf maakt.
--   * `players` is het spelersprofiel, met `auth_user_id` als koppeling.
--
-- Dus wordt hier niet op tabel geselecteerd maar op rol: **alles wat in
-- `club_members` staat blijft, de rest gaat.** Dat is meteen de veiligste
-- regel — vergeet je later een tweede beheerder toe te voegen aan die lijst,
-- dan verliest die zijn account, en dat merk je meteen in plaats van stil.
--
-- Wat er verder gebeurt, en waarom:
--
--   * Een spelersprofiel verdwijnt níét automatisch met zijn account. De
--     verwijzing staat op `on delete set null`, met opzet: aan zo'n profiel
--     hangt speelhistorie, en die hoort niet te sneuvelen omdat iemand zijn
--     account opzegt. Vandaar dat stap 3 apart opruimt wat daarna nergens
--     meer bij hoort.
--   * `link_state` moet mee terug. Een profiel dat 'claimed' blijft staan
--     zonder account is een leugen: het systeem denkt dan dat die persoon
--     zijn profiel al opgeëist heeft en zal hem nooit meer een uitnodiging
--     sturen.
--
-- Dit script is met opzet luidruchtig: het toont eerst wat er staat, doet dan
-- zijn werk, en toont daarna wat er over is.

-- ---------------------------------------------------------------------------
-- Vooraf: wat gaat er weg?
-- ---------------------------------------------------------------------------

select
  (select count(*) from auth.users)                                   as accounts_nu,
  (select count(distinct user_id) from club_members)                  as blijft_staf,
  (select count(*) from auth.users u
     where not exists (select 1 from club_members m where m.user_id = u.id)) as gaat_weg,
  (select count(*) from players)                                      as spelersprofielen,
  (select count(*) from tournament_results)                           as uitslagen;

-- Wie er blijft, met naam en toenaam. Kijk deze lijst na vóór je verder gaat:
-- staat jouw beheerdersaccount er niet bij, dan is het niet als staf gekoppeld
-- en zou het straks verdwijnen.
select u.email, string_agg(c.slug || ' (' || m.role || ')', ', ') as rollen
from auth.users u
join club_members m on m.user_id = u.id
join clubs c        on c.id = m.club_id
group by u.email
order by u.email;

-- ---------------------------------------------------------------------------
-- Het opruimen zelf
-- ---------------------------------------------------------------------------

do $$
declare
  v_staf     int;
  v_weg      int;
  v_los      int;
  v_profiel  int;
  v_invites  int;
begin
  select count(distinct user_id) into v_staf from club_members;

  if v_staf = 0 then
    raise exception 'Stop: er staat geen enkel stafaccount in club_members. Dan zou dit script álles wissen.';
  end if;

  -- 1. De accounts. Alles wat geen rol heeft bij een club.
  delete from auth.users u
  where not exists (select 1 from club_members m where m.user_id = u.id);
  get diagnostics v_weg = row_count;

  -- 2. De profielen die hun account kwijt zijn, terugzetten naar de toestand
  --    van vóór het opeisen. Anders denkt het systeem dat ze al een account
  --    hebben en krijgen ze nooit meer een uitnodiging.
  update players
  set link_state = (case when email is null then 'shadow' else 'invited' end)::player_link_state,
      onboarded_at     = null,
      stats_consent_at = null
  where auth_user_id is null
    and link_state = 'claimed';
  get diagnostics v_los = row_count;

  -- 3. Profielen die nergens meer bij horen. Wie nog lid is van een club of
  --    ergens een uitslag heeft staan, blijft — dezelfde regel als in
  --    cutoff_leegmaken.sql, en om dezelfde reden: een uitslag zonder speler
  --    is erger dan een speler te veel.
  delete from players p
  where p.auth_user_id is null
    and not exists (select 1 from club_players       cp where cp.player_id = p.id)
    and not exists (select 1 from tournament_results r  where r.player_id  = p.id)
    and not exists (select 1 from tournament_players tp where tp.player_id = p.id);
  get diagnostics v_profiel = row_count;

  -- 4. Uitnodigingen die naar een verdwenen profiel wezen zijn met dat profiel
  --    mee gecascadeerd. Wat overblijft en al afgevinkt stond, hoort weer open
  --    te staan: dat vinkje betekende "heeft een account", en dat klopt niet
  --    meer.
  update player_invites i
  set accepted_at = null, sent_at = null, attempts = 0, last_error = null
  from players p
  where p.id = i.player_id and p.auth_user_id is null and i.accepted_at is not null;
  get diagnostics v_invites = row_count;

  raise notice 'Opgeruimd: % accounts weg, % stafaccounts blijven, % profielen losgekoppeld, % profielen verwijderd, % uitnodigingen heropend.',
    v_weg, v_staf, v_los, v_profiel, v_invites;
end $$;

-- ---------------------------------------------------------------------------
-- Achteraf: wat staat er nu?
-- ---------------------------------------------------------------------------

select
  (select count(*) from auth.users)          as accounts_over,
  (select count(*) from players)             as spelersprofielen,
  (select count(*) from players where auth_user_id is not null) as met_account,
  (select count(*) from club_players)        as clublidmaatschappen,
  (select count(*) from tournament_results)  as uitslagen_bewaard;

select u.email, string_agg(c.slug || ' (' || m.role || ')', ', ') as rollen
from auth.users u
left join club_members m on m.user_id = u.id
left join clubs c        on c.id = m.club_id
group by u.email
order by u.email;
