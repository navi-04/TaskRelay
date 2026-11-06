// Runs as the first step of `npm run build`.
//
// On a Vercel PRODUCTION build it applies any pending migrations to the production database before the new code can go
// live, so the code and the schema can never be out of order. Migrations are additive (old code ignores new columns),
// so the previous deployment keeps serving safely while this runs; if a migration fails the build fails and the previous
// deployment stays live.
//
// Everywhere else (local builds, preview deployments) it does nothing: previews must never change the production database.
import { openDb } from '../lib/db';
import { migrate } from '../lib/migrate';

async function main() {
  if (process.env.VERCEL_ENV !== 'production') {
    console.log(`migrations skipped (VERCEL_ENV=${process.env.VERCEL_ENV ?? 'not on Vercel'}); run "npm run migrate" to apply them by hand`);
    return;
  }
  const db = await openDb(process.env.TURSO_DATABASE_URL, process.env.TURSO_AUTH_TOKEN);
  const ran = await migrate(db);
  console.log(ran.length ? `migrations applied: ${ran.join(', ')}` : 'migrations: database is up to date');
}

main().catch((e) => {
  console.error('migration failed, stopping the build:', e instanceof Error ? e.message : e);
  process.exit(1);
});
