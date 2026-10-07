-- Pokerleague — een rebuy mag niet geweigerd worden om een verouderde telling
--
-- **Wat er misging.** Migratie 0050 zette er een slot op: weigeren als de
-- speler méér chips heeft dan de startstapel, want dan zou een rebuy zijn
-- stapel verkleinen. Dat klonk voorzichtig en was het niet.
--
-- Een speler die vooraf inschrijft begint bij Cutoff met 45.000 — startstapel
-- 40.000 plus 5.000 bonus. Dat getal blijft in het systeem staan tot iemand
-- het bijwerkt, en bijna niemand werkt het bij. Speelt hij zich blut en drukt
-- de floor op rebuy, dan vergelijkt het slot die verouderde 45.000 met de
-- startstapel van 40.000 en weigert. De stapel blijft staan, en op een lange
-- spelerslijst staat de foutmelding bovenaan het scherm waar je op een
-- telefoon niet kijkt. Wat je ziet: je drukt op rebuy en er gebeurt niets.
--
-- Dus het slot raakte precies de spelers die vooraf inschreven. Wie aan de
-- deur kwam en op 40.000 stond, kon wél rebuyen.
--
-- **Waarom het slot helemaal weg kan en niet alleen bijgesteld.** De aanname
-- eronder was dat `chip_count` weet hoeveel iemand heeft. Dat weet het niet:
-- het is de laatste telling die iemand doorgaf, en bij een speler die net
-- blut ging is die per definitie verouderd. Een beslissing bouwen op een
-- getal dat op dat moment altijd fout is, levert geen veiligheid op.
--
-- Een rebuy betekent: deze speler is blut en koopt opnieuw in. De stapel gaat
-- naar de startstapel, zonder de bonus van de voorinschrijving — die gold
-- voor het begin van de avond en komt niet terug.
--
-- **En de bescherming die wél werkt, bestaat al.** `stack_before_reentry`
-- bewaart wat er vóór de inkoop lag, dus een misklik draai je terug met
-- "inkoop ongedaan maken" en de oude stapel komt terug. Dat is een vangnet
-- dat werkt zonder iets tegen te houden dat wél mag.

create or replace function public.floor_rebuy(
  p_tournament_player_id uuid,
  p_kind                 buyin_kind default 'reentry'
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  tp    tournament_players%rowtype;
  t     tournaments%rowtype;
  v_pot int;
  v_fee int;
begin
  select * into tp from tournament_players where id = p_tournament_player_id;
  if not found then
    raise exception 'Deelnemer bestaat niet';
  end if;
  select * into t from tournaments where id = tp.tournament_id;

  if not public.is_service_context()
     and not public.has_club_role(tp.club_id, array['owner','admin','floor']::club_role[]) then
    raise exception 'Geen rechten' using errcode = 'insufficient_privilege';
  end if;

  if p_kind = 'buyin' then
    raise exception 'Gebruik floor_add_entry voor de eerste inkoop' using errcode = 'check_violation';
  end if;

  -- Hier stond het slot op de verouderde telling. Zie de kop van dit bestand.

  if p_kind = 'addon' then
    v_pot := coalesce(t.addon_cents, t.buyin_cents);
    v_fee := coalesce(t.addon_fee_cents, 0);
  else
    -- Rebuy én re-entry volgen dezelfde afspraak: je koopt opnieuw in.
    v_pot := coalesce(t.rebuy_cents, t.buyin_cents);
    v_fee := coalesce(t.rebuy_fee_cents, t.fee_cents);
  end if;

  insert into buyins (
    club_id, tournament_id, tournament_player_id, player_id,
    kind, amount_cents, fee_cents, bounty_cents, recorded_by
  ) values (
    tp.club_id, tp.tournament_id, tp.id, tp.player_id,
    p_kind, v_pot, v_fee,
    case when t.bounty_mode = 'none' or p_kind = 'addon' then 0 else t.bounty_cents end,
    auth.uid()
  );

  update tournament_players
  set status          = case when p_kind = 'reentry' then 'active' else status end,
      finish_position = case when p_kind = 'reentry' then null else finish_position end,
      eliminated_at   = case when p_kind = 'reentry' then null else eliminated_at end,
      -- Wat er vóór deze inkoop lag, bewaren we ook bij een rebuy. Dat is het
      -- vangnet bij een misklik: `floor_undo_last_buyin` zet het terug.
      stack_before_reentry = case
                               when p_kind in ('reentry', 'rebuy') then chip_count
                               else stack_before_reentry
                             end,
      chip_count      = case
                          -- Een verse stapel, zonder de bonus van de
                          -- voorinschrijving: die gold voor het begin.
                          when p_kind in ('reentry', 'rebuy') then t.starting_stack
                          else coalesce(chip_count, 0) + coalesce(t.addon_stack, t.starting_stack)
                        end
  where id = tp.id;

  if p_kind = 'reentry' and tp.finish_position is not null then
    perform public.renumber_finish_positions(tp.tournament_id);
  end if;
end;
$$;

comment on function public.floor_rebuy(uuid, buyin_kind) is
  'Een nieuwe inkoop voor wie al meedeed. Rebuy en re-entry zetten de stapel op de startstapel zonder voorinschrijfbonus; een addon telt erbij op. Weigert nooit op basis van de laatst doorgegeven telling — die is bij een blutte speler altijd verouderd. Een misklik draai je terug met floor_undo_last_buyin.';
