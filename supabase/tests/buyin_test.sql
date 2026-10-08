-- Tests voor de buy-in in de puntentelling.
--
-- Twee dingen moeten kloppen en ze trekken aan elkaar, net als bij de
-- exponent. Een duurdere avond moet merkbaar zwaarder wegen. En een club die
-- er niets over instelt, mag er niets van merken — want elke club op dit
-- platform heeft punten in zijn geschiedenis staan die niet achteraf mogen
-- verschuiven.

begin;

do $$
declare
  v_league jsonb := '{"multiplier":10,"exponent":0.75,"buyin_ref":30,"buyin_weight":0.5}'::jsonb;
  v_zonder jsonb := '{"multiplier":10,"exponent":0.75}'::jsonb;
  v_15 numeric; v_30 numeric; v_50 numeric; v_100 numeric;
  v_duur numeric; v_goedkoop numeric;
begin
  -- ---------------------------------------------- wie niets instelt, verandert niets
  assert public.calc_points('sqrt_ratio', v_zonder, 1, 20, 0, 3000)
       = public.calc_points('sqrt_ratio', v_zonder, 1, 20, 0, 5000),
    'zonder ijkpunt hoort de inleg niet mee te tellen';
  assert public.calc_points('sqrt_ratio', '{"multiplier":10}'::jsonb, 1, 20, 0, 9999)
       = round(10 * sqrt(20::numeric), 0),
    'de oudste vorm van de formule gaf iets anders';
  raise notice 'OK  zonder buyin_ref rekent sqrt_ratio precies zoals vroeger';

  -- -------------------------------------------------- en met ijkpunt weegt hij mee
  v_15  := public.calc_points('sqrt_ratio', v_league, 1, 20, 0, 1500);
  v_30  := public.calc_points('sqrt_ratio', v_league, 1, 20, 0, 3000);
  v_50  := public.calc_points('sqrt_ratio', v_league, 1, 20, 0, 5000);
  v_100 := public.calc_points('sqrt_ratio', v_league, 1, 20, 0, 10000);

  -- Dit zijn de getallen waarop de keuze gemaakt is. Staan ze hier niet, dan
  -- is de league iets anders dan er is afgesproken.
  assert v_15  = 32, format('€15 hoort 32 punten te geven, gaf %s', v_15);
  assert v_30  = 45, format('€30 hoort 45 punten te geven, gaf %s', v_30);
  assert v_50  = 58, format('€50 hoort 58 punten te geven, gaf %s', v_50);
  assert v_100 = 82, format('€100 hoort 82 punten te geven, gaf %s', v_100);
  raise notice 'OK  de winnaar krijgt 32 / 45 / 58 / 82 punten bij €15 / €30 / €50 / €100';

  -- Een duurdere avond telt meer, maar een goedkope avond blijft de moeite:
  -- wie alleen de dertig-eurotornooien speelt moet nog kunnen meedoen.
  assert v_50 > v_30 * 1.2, 'vijftig euro woog niet merkbaar zwaarder dan dertig';
  assert v_50 < v_30 * 1.5, 'vijftig euro woog zo zwaar dat de goedkope avond zinloos wordt';
  raise notice 'OK  €50 is % procent meer waard dan €30', round((v_50 / v_30 - 1) * 100);

  -- ------------------------------------------------------- en de factor is geklemd
  -- Eén avond van vijfhonderd euro mag zwaarder wegen dan een gewone avond,
  -- maar niet zwaarder dan vier gewone avonden samen.
  v_duur := public.calc_points('sqrt_ratio', v_league, 1, 20, 0, 50000);
  assert v_duur = round(10 * sqrt(20::numeric) * 2, 0),
    format('een avond van €500 werd niet op twee keer afgetopt: %s', v_duur);
  assert public.calc_points('sqrt_ratio', v_league, 1, 20, 0, 100000) = v_duur,
    'boven de bovengrens maakte duurder nog steeds verschil';

  v_goedkoop := public.calc_points('sqrt_ratio', v_league, 1, 20, 0, 200);
  assert v_goedkoop = round(10 * sqrt(20::numeric) / 2, 0),
    format('een avond van €2 werd niet op de ondergrens gezet: %s', v_goedkoop);
  assert public.calc_points('sqrt_ratio', v_league, 1, 20, 0, 1) = v_goedkoop,
    'onder de ondergrens maakte goedkoper nog steeds verschil';
  raise notice 'OK  de weging blijft tussen een half en twee keer het ijkpunt';

  -- ------------------------------------------- gewicht nul is hetzelfde als niets
  assert public.calc_points('sqrt_ratio',
           '{"multiplier":10,"exponent":0.75,"buyin_ref":30,"buyin_weight":0}'::jsonb, 1, 20, 0, 5000)
       = public.calc_points('sqrt_ratio', v_zonder, 1, 20, 0, 5000),
    'met gewicht nul hoorde de inleg geen verschil te maken';
  raise notice 'OK  met gewicht nul telt de inleg niet mee';

  -- --------------------------------------- de plaats blijft doen wat ze deed
  -- De weging vermenigvuldigt de hele avond; ze mag de verhouding tussen de
  -- plaatsen niet verschuiven, anders betekent de exponent iets anders op een
  -- dure avond dan op een goedkope.
  --
  -- Eerste tegen vijfde en niet tegen laatste: punten worden op hele getallen
  -- afgerond, en onderaan het veld is één punt al tien procent. Daar meet je
  -- de afronding en niet de formule.
  assert abs(
      public.calc_points('sqrt_ratio', v_league, 1, 20, 0, 5000)
        / public.calc_points('sqrt_ratio', v_league, 5, 20, 0, 5000)
    - public.calc_points('sqrt_ratio', v_league, 1, 20, 0, 3000)
        / public.calc_points('sqrt_ratio', v_league, 5, 20, 0, 3000)
    ) < 0.1,
    'de verhouding tussen de plaatsen verschoof met de inleg mee';
  raise notice 'OK  de inleg schaalt de hele avond, niet de verhoudingen binnen de avond';

  -- ------------------------------------------- en de andere formules blijven
  assert public.calc_points('pokerstars', '{"multiplier":10}'::jsonb, 1, 20, 0, 3000)
       = round(10 * sqrt(20::numeric) * log(10, 1 + 30), 0),
    'pokerstars veranderde mee';
  assert public.calc_points('linear', '{"base":100,"decrement":5}'::jsonb, 3, 20, 0, 5000) = 90,
    'linear veranderde mee';
  raise notice 'OK  pokerstars, linear en fixed_table blijven onaangeroerd';
end $$;

rollback;
