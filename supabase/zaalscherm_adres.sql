-- Het adres voor de tv in de zaal.
--
-- Draai dit ná migratie 0070. Het verandert niets; het leest alleen de
-- sleutel van de club en zet het volledige adres voor je klaar.
--
-- Dat adres tik je één keer in op de tv en bewaar je daar als favoriet. Het
-- noemt geen tornooi: de pagina zoekt zelf de avond die bezig is, en staat er
-- niets op het programma dan wacht ze rustig. Je mag het scherm dus de hele
-- dag laten aanstaan.

select
  c.name                                   as club,
  c.screen_key                             as sleutel,
  case
    when c.custom_domain is not null
      then 'https://' || c.custom_domain || '/zaal?k=' || c.screen_key
    else 'https://' || c.slug || '.pokerleague.be/zaal?k=' || c.screen_key
  end                                      as adres_voor_de_tv,
  'https://pokerleague.be/c/' || c.slug || '/zaal?k=' || c.screen_key
                                           as adres_zonder_eigen_domein
from clubs c
where c.slug = 'cutoff';

-- Sleutel kwijt of in verkeerde handen? Dit zet er een nieuwe. Let op: elke
-- tv die het oude adres bewaard heeft, valt daarna stil tot je het nieuwe
-- adres intikt.
--
-- select public.club_reset_screen_key(id) from clubs where slug = 'cutoff';
