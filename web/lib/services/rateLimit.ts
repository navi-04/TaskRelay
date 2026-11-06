import type { Client } from '@libsql/client';
import { tooMany } from '../errors';

// Fixed-window counters in the database: serverless instances share no memory, so the DB is the shared state.

/** Seconds until the window frees up if `key` is at/over `limit`, else 0. Read-only. */
export async function retryAfter(db: Client, key: string, limit: number, windowSec: number, now: Date): Promise<number> {
  const rs = await db.execute({ sql: 'SELECT n, window_start FROM rate_limits WHERE key = ?', args: [key] });
  if (rs.rows.length === 0) return 0;
  const windowEnd = Date.parse(String(rs.rows[0].window_start)) + windowSec * 1000;
  if (now.getTime() >= windowEnd) return 0;
  return Number(rs.rows[0].n) >= limit ? Math.ceil((windowEnd - now.getTime()) / 1000) : 0;
}

/** Count one event for `key`; the window restarts when the previous one has expired. Returns the new count. */
export async function hit(db: Client, key: string, windowSec: number, now: Date): Promise<number> {
  const rs = await db.execute({
    sql: `INSERT INTO rate_limits (key, n, window_start) VALUES (:key, 1, :now)
          ON CONFLICT(key) DO UPDATE SET
            n = CASE WHEN window_start <= :cutoff THEN 1 ELSE n + 1 END,
            window_start = CASE WHEN window_start <= :cutoff THEN :now ELSE window_start END
          RETURNING n`,
    args: { key, now: now.toISOString(), cutoff: new Date(now.getTime() - windowSec * 1000).toISOString() },
  });
  return Number(rs.rows[0].n);
}

export async function clear(db: Client, key: string): Promise<void> {
  await db.execute({ sql: 'DELETE FROM rate_limits WHERE key = ?', args: [key] });
}

/** Count an event and throw 429 once `limit` is exceeded within the window. */
export async function enforce(db: Client, key: string, limit: number, windowSec: number, now: Date): Promise<void> {
  const n = await hit(db, key, windowSec, now);
  if (n > limit) throw tooMany(windowSec);
}
