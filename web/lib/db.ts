import type { Client } from '@libsql/client';

let shared: Promise<Client> | undefined;

/** The process-wide client (one per serverless instance). */
export function getDb(): Promise<Client> {
  shared ??= openDb(process.env.TURSO_DATABASE_URL, process.env.TURSO_AUTH_TOKEN);
  return shared;
}

/**
 * `file:` and `:memory:` URLs (tests, `next dev`) need the Node client; anything else
 * (Turso) uses the HTTP client, which is the one that works on Vercel's runtimes.
 */
export async function openDb(url?: string, authToken?: string): Promise<Client> {
  if (!url) throw new Error('TURSO_DATABASE_URL is not set');
  const local = url === ':memory:' || url.startsWith('file:');
  const mod = local ? await import('@libsql/client') : await import('@libsql/client/web');
  return mod.createClient({ url, authToken });
}
