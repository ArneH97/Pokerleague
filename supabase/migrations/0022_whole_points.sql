-- Pokerleague — punten in hele getallen
--
-- Een klassement met 43,27 punten erin leest als een berekening, niet als een
-- stand. Niemand rekent na of dat 43,27 of 43,3 hoort te zijn, en de komma
-- suggereert een precisie die er niet is: de formule vertrekt van een
-- wortelverhouding, dus die twee decimalen zijn ruis en geen informatie.
--
-- Afronden gebeurt hier bij de bron en niet in het scherm. Dat is het verschil
-- dat telt: rondt alleen het scherm af, dan tonen drie avonden van 10,5 punten
-- elk 11, terwijl het totaal 31,5 is en als 32 verschijnt. Elf plus elf plus
-- elf is geen tweeëndertig, en dát is het soort tabel waar iemand na afloop
-- over begint.
--
-- Door de punten per tornooi als geheel getal weg te schrijven klopt elke som
-- die je erop loslaat: het seizoenstotaal, het jaartotaal, de beste-N-regel.
--
-- De kolom blijft numeric(8,2). Het type veranderen zou elke bestaande rij en
-- elke view raken voor een winst die er niet is; wat erin komt is voortaan
-- gewoon altijd rond.

-- ---------------------------------------------------------------------------
-- 1. De formule rondt af op hele punten
-- ---------------------------------------------------------------------------

create or replace function public.calc_points(
  p_method      ranking_method,
  p_params      jsonb,
  p_position    int,
  p_entries     int,
  p_knockouts   int default 0,
  p_buyin_cents int default 0,
  p_bonus_ko    numeric default 0,
  p_bonus_entry numeric default 0
)
returns numeric
language plpgsql
immutable
as $$
declare
  v_pts   numeric := 0;
  v_tbl   jsonb;
  v_mult  numeric;
  v_base  numeric;
  v_dec   numeric;
  v_floor numeric;
begin
  if p_position is null or p_position < 1 or p_entries is null or p_entries < 1 then
    return 0;
  end if;

  case p_method
    when 'fixed_table' then
      v_tbl := coalesce(p_params->'table', '[]'::jsonb);
      if p_position <= jsonb_array_length(v_tbl) then
        v_pts := (v_tbl->>(p_position - 1))::numeric;
      else
        v_pts := coalesce((p_params->>'tail')::numeric, 0);
      end if;

    when 'linear' then
      v_base  := coalesce((p_params->>'base')::numeric, 100);
      v_dec   := coalesce((p_params->>'decrement')::numeric, 5);
      v_floor := coalesce((p_params->>'floor')::numeric, 1);
      v_pts   := greatest(v_base - (p_position - 1) * v_dec, v_floor);

    when 'sqrt_ratio' then
      v_mult := coalesce((p_params->>'multiplier')::numeric, 10);
      v_pts  := v_mult * sqrt(p_entries::numeric) / sqrt(p_position::numeric);

    when 'pokerstars' then
      v_mult := coalesce((p_params->>'multiplier')::numeric, 10);
      v_pts  := v_mult
                * (sqrt(p_entries::numeric) / sqrt(p_position::numeric))
                * log(10, 1 + (p_buyin_cents::numeric / 100.0));
  end case;

  v_pts := v_pts + (coalesce(p_knockouts, 0) * coalesce(p_bonus_ko, 0)) + coalesce(p_bonus_entry, 0);

  -- Hele punten. Een club die met halve punten werkt via een eigen tabel
  -- verliest die halve punten hier bewust: één regel voor het hele platform
  -- is duidelijker dan een instelling waarvan niemand weet dat ze bestaat.
  return round(greatest(v_pts, 0), 0);
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Wat er al in staat rechttrekken
-- ---------------------------------------------------------------------------
-- Anders staan er tot het einde van het seizoen twee soorten rijen naast
-- elkaar en klopt de optelling van een klassement over meerdere maanden nog
-- altijd niet.

update tournament_results
set points = round(points, 0)
where points <> round(points, 0);
