/**
 * Plakt de migraties aan elkaar tot supabase/setup.sql, zodat je in de
 * Supabase SQL Editor één keer hoeft te plakken in plaats van drie keer.
 *
 * De migraties in supabase/migrations/ blijven de bron. Draai dit script
 * opnieuw na elke wijziging: `npm run db:bundle`.
 */
import { readdirSync, readFileSync, writeFileSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const dir = join(root, 'supabase', 'migrations')
const out = join(root, 'supabase', 'setup.sql')

const files = readdirSync(dir).filter((f) => f.endsWith('.sql')).sort()

const header = `-- ClubStack — volledige database-opzet
--
-- GEGENEREERD BESTAND. Bewerk supabase/migrations/*.sql en draai
-- \`npm run db:bundle\` opnieuw.
--
-- Plak dit in de SQL Editor van Supabase en draai het in één keer.
-- Draait op een lege database; bestaande tabellen worden niet aangeraakt
-- maar zullen wel een foutmelding geven.
--
-- Onderdelen: ${files.join(' · ')}

`

const body = files
  .map((f) => {
    const sep = '-- '.padEnd(76, '=')
    return `${sep}\n-- ${f}\n${sep}\n\n${readFileSync(join(dir, f), 'utf8').trim()}\n`
  })
  .join('\n')

writeFileSync(out, header + body)
console.log(`supabase/setup.sql geschreven (${files.length} migraties, ${(header + body).length} tekens)`)
