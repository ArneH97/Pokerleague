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
| Klokweergave en floor-UI | volgt |
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

Draai de drie migraties in volgorde tegen je Supabase-project, via de SQL
Editor of met de CLI:

```bash
export DATABASE_URL="postgresql://postgres:[wachtwoord]@db.[ref].supabase.co:5432/postgres"
npm run db:reset
```

### Tests

```bash
npm test          # kloklogica (TypeScript)
npm run db:test   # engine: payouts, punten, compliance, volledig tornooi
```

`db:test` draait binnen een transactie die aan het eind terugrolt, dus je kan
hem veilig op een database met data loslaten.

## Structuur

```
supabase/migrations/   0001 schema · 0002 functies · 0003 RLS
supabase/tests/        droogloop van een volledig tornooi
src/lib/tournament/    kloklogica (puur, framework-onafhankelijk)
docs/datamodel.md      waarom het schema is zoals het is
```

Lees `docs/datamodel.md` voor de twee ontwerpbeslissingen die later niet meer
te wijzigen zijn: platformbrede speleridentiteit en `club_id` op elke tabel.

## Voor de openingsavond

De klok is die avond het enige wat écht niet mag falen. Doe minstens één
volledige droogloop met echte mensen, en zorg dat er een tweede laptop met een
gratis klok klaarstaat als plan B.
