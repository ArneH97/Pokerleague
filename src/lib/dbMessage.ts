import type { Key, T } from '@/lib/i18n/dictionaries'

/**
 * De taal van de database.
 *
 * De regels van dit product staan in PostgreSQL en niet in de browser — dat
 * is met opzet: een controle die in de database staat geldt ook voor de
 * tweede tab, voor een verlopen scherm en voor iemand die met curl langskomt.
 * De keerzijde is dat de foutmeldingen daar in het Nederlands staan, want een
 * `raise exception` weet niet wie er kijkt.
 *
 * Dat viel niet op zolang alle floors Nederlandstalig waren. Bij de eerste
 * Vlaamse club met een Franstalige floor stond de hele app in het Frans en
 * kwam er bij een foute handeling ineens "Geen rechten om spelers toe te
 * voegen" uit. Dat is precies het moment waarop iemand een taal nodig heeft
 * die hij begrijpt.
 *
 * Vandaar deze tabel: van de tekst die de database geeft naar een sleutel uit
 * het woordenboek. Vertalen aan de rand, waar de taal van de kijker bekend
 * is, in plaats van de database te laten raden.
 *
 * **Waarom op tekst en niet op foutcode.** SQLSTATE zegt te weinig: alle
 * rechtenfouten delen dezelfde code, en `check_violation` dekt zowel "geen
 * geldig mailadres" als "je bent te jong". De tekst is wat onderscheidt. Ze
 * staat vast in de migraties en verandert niet zonder dat wij het doen.
 *
 * Wat er niet in staat, valt terug op de oorspronkelijke tekst. Een
 * onvertaalde melding is vervelend; een verdwenen melding is erger.
 */

/** Van de Nederlandse tekst uit de database naar een sleutel. */
const TABLE: [RegExp, Key][] = [
  // Rechten. Alle varianten van "Geen rechten om ..." vallen samen: voor wie
  // het scherm bedient maakt het niet uit wélke handeling geweigerd werd.
  [/^Geen rechten/i, 'db.noRights'],
  [/row-level security/i, 'db.noRights'],
  [/^Niet aangemeld/i, 'db.notSignedIn'],
  [/account dat niet meer bestaat/i, 'login.stale'],

  // Het tornooi zelf.
  [/^Tornooi .*bestaat niet|^Tornooi bestaat niet/i, 'db.noTournament'],
  [/^Deelnemer bestaat niet/i, 'db.noEntry'],
  [/^Dit tornooi is (al )?afgelopen/i, 'db.tournamentOver'],
  [/^Blindstructuur bestaat niet|^Bronstructuur niet gevonden/i, 'db.noStructure'],
  [/^Een structuur moet minstens/i, 'db.structureNeedsLevel'],
  [/^Een platformsjabloon/i, 'db.templateReadOnly'],
  [/^Aanvraag bestaat niet/i, 'db.noRequest'],

  // Spelers toevoegen aan de deur.
  [/^Geef een naam op/i, 'db.nameRequired'],
  [/^Geef een mailadres op/i, 'db.emailOrReason'],
  [/^Dat lijkt geen geldig mailadres/i, 'db.badEmail'],
  [/^Dit account heeft geen mailadres/i, 'db.accountNoEmail'],
  [/minimumleeftijd is/i, 'db.tooYoung'],
  [/^Je moet 18 jaar/i, 'db.under18'],
  [/geboortedatum klopt niet/i, 'db.badBirthdate'],

  // Geld en stapels.
  [/re-entry\/rebuy per tornooi/i, 'db.maxReentries'],
  [/^Er is geen inkoop om terug te draaien/i, 'db.nothingToUndo'],
  [/^Gebruik floor_add_entry/i, 'db.useAddEntry'],
  [/^Een bedrag kan niet negatief/i, 'db.negativeAmount'],
  [/^Geen bedragen opgegeven|^De bedragen in het voorstel zijn leeg/i, 'db.noAmounts'],
  [/^Onmogelijk chipaantal/i, 'db.badChipCount'],
  [/alleen je eigen chipaantal/i, 'db.ownChipsOnly'],
  [/niet meer actief in dit tornooi/i, 'db.notActiveAnymore'],

  // De deal aan de finaletafel.
  [/^Een deal heeft minstens twee/i, 'db.dealNeedsTwo'],
  [/^De verdeling telt op tot/i, 'db.dealSumMismatch'],
  [/^Er ligt geen voorstel op tafel/i, 'db.noDealOnTable'],
]

/**
 * De melding van de database in de taal van wie kijkt.
 *
 * Geef er de fout in die supabase-js teruggeeft; wat eruit komt is klaar om
 * op het scherm te zetten.
 */
export function dbMessage(
  err: { message?: string | null; code?: string | null } | null | undefined,
  t: T,
): string {
  const raw = err?.message?.trim() ?? ''
  if (!raw) return t('common.error')

  // 42501 is de rechtenfout van PostgreSQL zelf, zonder eigen tekst.
  if (err?.code === '42501') return t('db.noRights')

  for (const [pattern, key] of TABLE) {
    if (pattern.test(raw)) return t(key)
  }
  return raw
}
