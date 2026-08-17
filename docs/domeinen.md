# Adressen: hoe een club online komt

Eén app, veel adressen. Wat een bezoeker intypt bepaalt in welke clubomgeving
hij terechtkomt; de proxy schrijft dat intern door naar `/c/<slug>/…`. De club
ziet dus `app.cutoff.be/floor/123` en niet `pokerleague.be/c/cutoff/floor/123`.

Er zijn twee soorten clubadressen. Ze sluiten elkaar niet uit — een club begint
op het eerste en verhuist naar het tweede wanneer het hem uitkomt.

---

## 1. `cutoff.pokerleague.be` — werkt meteen

Dit is het pad waar niemand iets voor hoeft te doen. De naam vóór de punt ís
de slug van de club, dus zodra een club in de database staat is hij bereikbaar.
Geen opzoeking, geen instelling, geen wachten op DNS van iemand anders.

**Eenmalig, door jou:**

| Waar | Wat |
|---|---|
| DNS van pokerleague.be | `*` CNAME → `cname.vercel-dns.com` |
| Vercel → Domains | `*.pokerleague.be` toevoegen |

Daarna is elke volgende club gratis: `aalst.pokerleague.be`, `gent.pokerleague.be`,
wat de slug ook is.

Namen die nooit als club gelezen worden staan in `src/lib/hosts.ts`: `www`,
`api`, `mail`, `admin`, `status` en een handvol andere. Wil je later een echte
`status.pokerleague.be`, dan botst die dus niet met een club.

---

## 2. `app.cutoff.be` — het eigen domein van de club

Mooier op een affiche, en een club die betaalt voor zijn eigen platform
verwacht zijn eigen adres. Het kost aan beide kanten één handeling.

**De club doet:**

| Type | Naam | Waarde |
|---|---|---|
| CNAME | `app` | `cname.vercel-dns.com` |

**Jij doet:**

1. Vercel → Settings → Domains → `app.cutoff.be` toevoegen. Vercel regelt het
   certificaat zodra de CNAME actief is; reken op minuten, niet op dagen.
2. Het domein in de database zetten:

   ```sql
   update clubs set custom_domain = 'app.cutoff.be' where slug = 'cutoff';
   ```

Meer is er niet. Het subdomein op pokerleague.be blijft gewoon werken, dus een
link die iemand vorig jaar bewaarde blijft geldig.

---

## Waarom niet alleen het eigen domein

Omdat je dan bij elke nieuwe club afhankelijk bent van iemand anders zijn DNS.
Een club die vanavond wil beginnen kan dat niet als er eerst een CNAME moet
propageren bij een provider waar de voorzitter het wachtwoord van kwijt is. Het
subdomein neemt die afhankelijkheid weg; het eigen domein is dan een
verbetering achteraf in plaats van een voorwaarde vooraf.

---

## Wat er per club nog meer ingesteld wordt

Het adres is één ding; dit is de rest van wat een nieuwe club nodig heeft. Nu
nog met SQL — een instellingenscherm bestaat nog niet.

| Instelling | Waar | Standaard |
|---|---|---|
| Slug, naam, gemeente | `clubs` | — |
| Taal van de clubomgeving | `clubs.locale` | `nl` |
| Tijdzone | `clubs.timezone` | `Europe/Brussels` |
| Munt | `clubs.currency` | `EUR` |
| Logo en beeldmerk | `clubs.logo_url`, `clubs.mark_url` | leeg |
| Huisstijlkleur en vlakken | `clubs.primary_color`, `clubs.settings.theme` | platformthema |
| Namen op de publieke pagina's | `clubs.public_names` | uit |
| Gedoogbeleid | `clubs.compliance` | Belgische limieten, `warn` |
| Eigen domein | `clubs.custom_domain` | leeg |
| Blindstructuur, prijzenverdeling, puntensysteem, seizoen | eigen tabellen | platformsjablonen |

`supabase/seed_cutoff.sql` doet dit alles voor Cutoff en is het beste
vertrekpunt voor een tweede club: kopiëren, de bovenste regels aanpassen,
draaien.

---

## Lokaal testen

`cutoff.localhost:3000` werkt zonder je hosts-bestand aan te raken — browsers
sturen alles onder `.localhost` vanzelf naar je eigen machine. Zo kan je de
platformkant en de clubkant naast elkaar openen in twee tabbladen.
