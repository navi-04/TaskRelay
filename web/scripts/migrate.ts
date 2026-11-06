// Usage: npm run migrate   (reads TURSO_DATABASE_URL / TURSO_AUTH_TOKEN from .env.local)
import { openDb } from '../lib/db';
import { migrate } from '../lib/migrate';

async function main() {
  // .env.local wins over .env (as in Next.js); variables already in the environment win over both.
  for (const file of ['.env.local', '.env']) {
    try {
      process.loadEnvFile(file);
    } catch {
      // file not present
    }
  }
  const db = await openDb(process.env.TURSO_DATABASE_URL, process.env.TURSO_AUTH_TOKEN);
  const ran = await migrate(db);
  console.log(ran.length ? `applied: ${ran.join(', ')}` : 'database is up to date');
}

main().catch((e) => {
  console.error('migration failed:', e instanceof Error ? e.message : e);
  process.exit(1);
});
