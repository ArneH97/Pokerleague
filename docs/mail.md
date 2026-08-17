# Mail: hoe pokerleague.be verstuurt

Accounts voor spelers draaien op mail. Registreren, je profiel opeisen,
wachtwoord vergeten, een uitnodiging van de floor — allemaal een bericht met
een link erin. Komt die mail niet aan, dan bestaat de spelerskant niet.

---

## Waarom dit eerst moet

De ingebouwde verzender van Supabase doet **twee berichten per uur**, en
alleen naar adressen van je eigen team. Dat is met opzet: hij is bedoeld om
mee te proberen, niet om mee te draaien. Er staat geen enkele garantie op
bezorging of beschikbaarheid tegenover.

Dertig mensen die zich op de openingsavond registreren gaan daar niet door.

Zodra er een eigen verzender aan hangt zet Supabase de limiet op **30 per
uur**, en die kan je zelf hoger zetten onder *Rate Limits* in het dashboard.
Doe dat vóór 6 september.

---

## Het domein: send.pokerleague.be

Resend zet zijn eigen records altijd op een `send.`-laag onder het domein dat
je opgeeft — ook zijn MX. Er was dus nooit gevaar dat hij met de MX van Google
Workspace op je hoofddomein zou botsen; die vrees uit een eerdere versie van
dit document was ongegrond.

Gekozen is `send.pokerleague.be`. Resend maakt daar zelf nog een laag onder,
dus de records komen op `send.send.pokerleague.be` te staan en er wordt
verstuurd vanaf `no-reply@send.pokerleague.be`.

Was ook mogelijk geweest: gewoon `pokerleague.be` opgeven. Dan waren de records
op `send.pokerleague.be` beland en had de afzender `no-reply@pokerleague.be`
kunnen zijn — iets herkenbaarder voor een ontvanger. Wil je later alsnog
overstappen: domein bijzetten in Resend, de nieuwe records erbij, afzender in
Supabase aanpassen. Het oude mag daarna weg.

---

## Wat jij doet

### 1. Resend

1. Account maken op resend.com.
2. **Domains → Add Domain** → `send.pokerleague.be`.
3. Hij toont dan drie records. Voor `send.pokerleague.be` zien de namen er zo
   uit — let op de dubbele `send`, dat is Resends eigen laag:

   | Type | Naam | Inhoud |
   |---|---|---|
   | TXT | `resend._domainkey.send` | de lange `p=MIGfMA…`-waarde |
   | MX | `send.send` | `feedback-smtp.…amazonses.com`, prioriteit 10 |
   | TXT | `send.send` | `v=spf1 include:amazonses.com ~all` |

   Klap de afgekorte waarden open en kopieer ze voluit; de puntjes in het
   midden zijn een afkorting van het scherm.
4. **API Keys → Create API Key**. Bewaar hem meteen; hij is daarna niet meer
   te lezen.

### 2. EasyHost

De records uit stap 3 invoeren bij pokerleague.be. Let op de naamgeving: waar
Resend `send` zegt, bedoelt hij het label onder pokerleague.be — dus in het
EasyHost-veld vul je `send` in en niet `send.pokerleague.be`, anders krijg je
`send.pokerleague.be.pokerleague.be`.

Terug in Resend op **Verify** klikken. Dat duurt meestal minuten.

### 3. Supabase

**Authentication → SMTP Settings → Enable Custom SMTP**, en dan:

| Veld | Waarde |
|---|---|
| Host | `smtp.resend.com` |
| Port | `465` |
| Username | `resend` |
| Password | je API-sleutel uit stap 1.4 |
| Sender email | `no-reply@send.pokerleague.be` |
| Sender name | `PokerLeague` |

Daarna onder **Rate Limits** het aantal mails per uur omhoog. Vijftig is ruim
voor een openingsavond.

---

## Nog iets: je SPF klopt niet met je mail

Los van bovenstaande. Vandaag staat er op pokerleague.be:

```
v=spf1 mx a include:_spf.relay.mailprotect.be ~all
```

Maar je MX wijst naar `smtp.google.com`. Google staat dus nergens in je SPF.
Zolang je niets verstuurt vanaf `@pokerleague.be` merk je dat niet — maar de
eerste keer dat je dat wél doet, belandt die mail bij een deel van de
ontvangers in spam.

Verstuur je alleen nog via Google Workspace, dan hoort er dit te staan:

```
v=spf1 include:_spf.google.com ~all
```

Gebruik je mailprotect nog voor iets, laat die dan staan en zet Google erbij:

```
v=spf1 include:_spf.google.com include:_spf.relay.mailprotect.be ~all
```

Dit raakt de applicatie niet — die verstuurt straks vanaf `send.` en heeft
zijn eigen SPF. Het gaat om je gewone clubpost.

Je DMARC staat op `p=none`, wat betekent: rapporteren maar niets weigeren. Dat
is de juiste stand zolang je aan het verhuizen bent. Zet hem pas strenger als
alles een paar weken zonder klachten draait.

---

## Wat ik doe zodra dit staat

De uitnodigingen die de floor aanmaakt staan al in een wachtrij
(`player_invites`, met `sent_at` en `last_error`). Er ontbreekt alleen nog het
stuk dat die wachtrij leegmaakt en de mails werkelijk verstuurt. Dat bouw ik
zodra de sleutel er is — tot dan werkt registreren gewoon via Supabase zelf,
wat genoeg is om alles te testen.
