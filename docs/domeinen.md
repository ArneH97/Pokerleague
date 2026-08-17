# Adressen: hoe een club online komt

Eén app, veel adressen. Wat een bezoeker intypt bepaalt in welke clubomgeving
hij terechtkomt; `src/proxy.ts` schrijft dat intern door naar `/c/<slug>/…`. De
club ziet dus `cutoff.pokerleague.be/floor/123` en niet
`pokerleague.be/c/cutoff/floor/123`.

## Hoe het vandaag staat

| | |
|---|---|
| Hosting | Vercel, project **pokerleague** |
| DNS van pokerleague.be | EasyHost (`ns1/ns2/ns3.easyhost.be`) |
| Apex | A-record → `216.198.79.1`, en Vercel stuurt hem 308 door naar www |
| Canoniek adres | `www.pokerleague.be` |
| **CNAME-doel van dit project** | **`971b460f0e7a5f2a.vercel-dns-017.com`** |
| Mail | MX naar Google Workspace; autoconfig/autodiscover/SRV nog naar mailprotect (EasyHost) |

Die CNAME-waarde is per project en per account. Ze staat op de domeinkaart in
Vercel; neem hem daar over en gok hem niet.

---

## Een club online zetten

Twee handelingen, samen twee minuten. Doe ze in deze volgorde: dan weet Vercel
dat het domein eraan komt en vraagt het certificaat zichzelf aan zodra DNS
meewerkt.

**1. Vercel** → project `pokerleague` → Settings → Domains → **Add Existing** →
`cutoff.pokerleague.be`. Hij zegt eerst *Invalid Configuration*; dat hoort zo.

**2. EasyHost** → pokerleague.be → Beheer DNS → CNAME-records beheren →
toevoegen:

| Type | Naam | Waarde |
|---|---|---|
| CNAME | `cutoff` | `971b460f0e7a5f2a.vercel-dns-017.com` |

Terug in Vercel op **Refresh** klikken. Binnen een paar minuten staat er
*Valid Configuration* en werkt `cutoff.pokerleague.be`.

Meer is er niet. In de database hoeft niets: de naam vóór de punt ís de slug,
en `src/lib/hosts.ts` leidt die af zonder opzoeking.

---

## Een club met een eigen domein

`app.cutoff.be` in plaats van (of naast) het subdomein. Mooier op een affiche.
Drie handelingen in plaats van twee.

**1. Vercel** → Add Existing → `app.cutoff.be`.

**2. DNS van cutoff.be** — bij de club of bij jou:

| Type | Naam | Waarde |
|---|---|---|
| CNAME | `app` | `971b460f0e7a5f2a.vercel-dns-017.com` |

**3. De database**, want `app.cutoff.be` zegt niets over wélke club het is:

```sql
update clubs set custom_domain = 'app.cutoff.be' where slug = 'cutoff';
```

Zie `supabase/clubdomein_zetten.sql`. Beide adressen blijven daarna werken, dus
een link die iemand bewaarde blijft geldig.

---

## Waarom geen jokerteken

`*.pokerleague.be` zou elke nieuwe club meteen bereikbaar maken zonder dat er
iemand nog een record moet zetten. Verleidelijk, en het is wat ik eerst
voorstelde — maar het kan niet zonder de nameservers van pokerleague.be naar
Vercel te verhuizen. Vercel moet zelf DNS-uitdagingen kunnen beantwoorden om
een wildcard-certificaat te krijgen; een `*` CNAME bij EasyHost is niet genoeg.

Die verhuizing betekent dat alle records hierboven opnieuw aangemaakt moeten
worden bij Vercel: de MX naar Google, SPF, DMARC, de autodiscover- en
SRV-records. Eén vergeten regel en de mail van pokerleague.be ligt eruit.

Voor die prijs koop je dat je per club één CNAME uitspaart. Bij één club is dat
geen ruil. Bij tien clubs wordt het interessant, en dan is het een middag werk
die je rustig plant — niet iets wat je drie weken voor een opening doet.

---

## Wat er per club nog meer ingesteld wordt

Het adres is één ding; dit is de rest. Nu nog met SQL — een instellingenscherm
bestaat nog niet.

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

## Namen die nooit een club worden

`www`, `app`, `api`, `admin`, `auth`, `mail`, `smtp`, `ftp`, `status`, `docs`,
`blog`, `cdn`, `static`, `assets`, `staging`, `test`. Staan in
`src/lib/hosts.ts`. Wil je later een echte `status.pokerleague.be`, dan botst
die dus niet met een club die toevallig zo heet.

Let op: er staat al een `ftp.pokerleague.be` A-record bij EasyHost, nog van de
webhosting. Dat mag weg als je geen FTP gebruikt — het staat op de lijst
hierboven, dus kwaad kan het niet.

---

## Lokaal testen

`cutoff.localhost:3000` werkt zonder je hosts-bestand aan te raken — browsers
sturen alles onder `.localhost` vanzelf naar je eigen machine. Zo kan je de
platformkant en de clubkant naast elkaar openen in twee tabbladen.
