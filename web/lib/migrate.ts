import type { Client, InStatement } from '@libsql/client';
import { readdir, readFile } from 'node:fs/promises';
import path from 'node:path';

/** Split a migration file into statements. Migrations are plain DDL: no triggers, no `;` in strings. */
export function splitStatements(sql: string): string[] {
  const withoutComments = sql
    .split('\n')
    .filter((line) => !line.trim().startsWith('--'))
    .join('\n');
  return withoutComments
    .split(/;\s*(?:\n|$)/)
    .map((s) => s.trim())
    .filter(Boolean);
}

/**
 * Apply any `db/migrations/*.sql` not yet recorded in `schema_migrations`, each in one
 * atomic batch. Run from a script before deploy, never from a request. Returns the names applied.
 */
export async function migrate(db: Client, dir = path.join(process.cwd(), 'db', 'migrations')): Promise<string[]> {
  await db.execute('CREATE TABLE IF NOT EXISTS schema_migrations (name TEXT PRIMARY KEY, applied_at TEXT NOT NULL) STRICT');
  const applied = new Set((await db.execute('SELECT name FROM schema_migrations')).rows.map((r) => String(r.name)));
  const files = (await readdir(dir)).filter((f) => f.endsWith('.sql')).sort();

  const ran: string[] = [];
  for (const file of files) {
    if (applied.has(file)) continue;
    const statements: InStatement[] = splitStatements(await readFile(path.join(dir, file), 'utf8'));
    statements.push({
      sql: 'INSERT INTO schema_migrations (name, applied_at) VALUES (?, ?)',
      args: [file, new Date().toISOString()],
    });
    await db.batch(statements, 'write');
    ran.push(file);
  }
  return ran;
}
