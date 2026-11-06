import { getDb } from '@/lib/db';
import { handle, json } from '@/lib/http';

export const dynamic = 'force-dynamic';

/** Liveness + database reachability. Reveals nothing else. */
export const GET = () =>
  handle(async () => {
    const db = await getDb();
    await db.execute('SELECT 1');
    return json({ ok: true });
  });
