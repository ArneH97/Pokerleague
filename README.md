# ClubStack

Platform voor pokerclubs: clubbeheer, tornooiklok, ledenbestand en een
spelersingang met resultaten en rankings. Multi-tenant vanaf de eerste regel —
Cutoff Poker Club is de eerste club, niet de enige.

*Werknaam. Hernoemen kan zolang er nog geen domein aan hangt.*

## Status

| Onderdeel | Staat |
|---|---|
| Datamodel + migraties | klaar, getest tegen Postgres 16 |
| Compliance-register (gedoogbeleid KSC) | klaar, afgedwongen in de database |
| Payouts, punten, seizoensklassement | klaar, getest |
| Kloklogica | klaar, 17 tests |
| Zaalweergave + floor-bediening | klaar, realtime |
| Aanmelden | klaar (e-mail + wachtwoord) |
| Spelers registreren, inkopen, uitschakelen | volgt |
| Clubdashboard | volgt |
| Spelersingang | volgt, achter een flag |

Doel voor **6 september 2026**: de engine draait op de openingsavond van Cutoff.

## Opzetten

```bash
npm install
cp .env.example .env.local     # vul je Supabase-gegevens in
npm run dev
```

### Database

Draai in de SQL Editor van Supabase, in deze volgorde:

1. `supabase/setup.sql` — schema, functies, RLS en realtime in één keer
2. `supabase/seed_cutoff.sql` — Cutoff, blindstructuur, seizoen en een tornooi

Pas vóór stap 2 het e-mailadres bovenaan dat bestand aan, en maak die
gebruiker eerst aan onder **Authentication → Users**. Zonder die koppeling
ben je na het aanmelden aan geen enkele club verbonden en zie je een leeg
scherm.

Beide scripts mag je opnieuw draaien; `seed_cutoff.sql` werkt bestaande
gegevens bij in plaats van te verdubbelen. `setup.sql` niet — die verwacht een
lege database.

### Schermen

| URL | Waarvoor |
|---|---|
| `/` | overzicht van tornooien |
| `/klok/<id>` | zaalweergave voor beamer of tv, zonder knoppen |
| `/floor/<id>` | bediening: starten, pauzeren, levels, tijd bijsturen |

Het tornooi-id staat in de uitvoer van `seed_cutoff.sql`, of je klikt door
vanaf de startpagina.

### Tests

```bash
npm test          # kloklogica (TypeScript)
npm run db:test   # engine: payouts, punten, compliance, tijdzones, autorisatie
```

`db:test` draait binnen een transactie die aan het eind terugrolt, dus je kan
hem veilig op een database met data loslaten.

## Structuur

```
supabase/migrations/   0001 schema · 0002 functies · 0003 RLS · 0004 realtime
supabase/setup.sql     gegenereerd; alles samen, voor de SQL Editor
supabase/tests/        droogloop van een volledig tornooi
src/lib/tournament/    kloklogica (puur, framework-onafhankelijk)
src/lib/supabase/      clients voor browser en server
src/components/        zaalweergave en floor-bediening
docs/datamodel.md      waarom het schema is zoals het is
```

Na een wijziging in `supabase/migrations/` draai je `npm run db:bundle` om
`setup.sql` opnieuw te genereren.

## Hoe de klok werkt

De database bewaart geen aftellende teller, maar het moment waarop het huidige
level begon en de al opgebouwde tijd. De resterende tijd is altijd een
berekening tegen servertijd. Daardoor overleeft de klok een refresh, een tweede
scherm dat later aansluit, en een laptop die in slaap valt — en rollen verlopen
levels vanzelf door als de floor vergeet te klikken.

De schermen synchroniseren via Supabase Realtime, met een trage polling van
20 seconden eronder als vangnet voor zaalwifi. Beide schermen corrigeren hun
eigen klokafwijking tegen `/api/time`, zodat twee apparaten niet uit elkaar
lopen.

## Voor de openingsavond

De klok is die avond het enige wat écht niet mag falen. Doe minstens één
volledige droogloop met echte mensen, en zorg dat er een tweede laptop met een
gratis klok klaarstaat als plan B.
