-- Pokerleague — namen tonen op de publieke pagina's van Cutoff
--
-- Standaard tonen de publieke pagina's van een club gebruikersnamen en geen
-- echte namen. Dat is de veilige kant: een naam is een persoonsgegeven, en
-- op pokerleague.be — waar clubs en spelers elkaar niet kennen — blijft die
-- regel ook gewoon staan.
--
-- Op de eigen pagina's van een club ligt het anders. Daar staan de mensen die
-- die avond aan tafel zaten, en een uitslag met "Speler a3f2" erop is voor
-- niemand bruikbaar. Draai je dit, dan verklaar je dat Cutoff die toestemming
-- heeft — via het clubreglement of het aanmeldformulier. Dat is een keuze van
-- de club en daarom staat ze niet standaard aan.
--
-- Terugdraaien kan altijd: zet true op false en draai opnieuw. Er gaat niets
-- verloren; de pagina's tonen dan weer gebruikersnamen.

update clubs set public_names = true where slug = 'cutoff';

select slug, name, public_names from clubs where slug = 'cutoff';
