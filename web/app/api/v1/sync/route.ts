import { authApp, handle, json, queryInt } from '@/lib/http';
import { enforce } from '@/lib/services/rateLimit';
import { buildSync, SYNC_DEFAULT_DAYS, SYNC_MAX_DAYS, syncEtag } from '@/lib/services/sync';
import { todayFor } from '@/lib/time';

/**
 * GET /sync?days=14 - the phone feed (alarms for the next days, today's numbers, reminder settings) in one call.
 * Send the last ETag as If-None-Match: when nothing changed this is a 304 that costs ~2 row reads.
 */
export const GET = (req: Request) =>
  handle(async () => {
    const { ctx, user } = await authApp(req);
    const days = queryInt(new URL(req.url), 'days', 1, SYNC_MAX_DAYS, SYNC_DEFAULT_DAYS);
    const etag = syncEtag(user.data_version, todayFor(ctx.now(), ctx.tz), days);
    const headers = { ETag: etag, 'Cache-Control': 'no-store' };

    if (req.headers.get('if-none-match') === etag) return new Response(null, { status: 304, headers });

    await enforce(ctx.db, `sync:${ctx.userId}`, 120, 3600, ctx.now()); // only full payloads count
    return json(await buildSync(ctx, days, etag), 200, headers);
  });
