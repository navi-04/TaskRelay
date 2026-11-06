import { authApp, handle, json, queryInt, querySearch } from '@/lib/http';
import { enforce } from '@/lib/services/rateLimit';
import { searchTasks, SEARCH_MAX_LIMIT } from '@/lib/services/search';

/** GET /search?q=&limit=&offset= - title/notes search across every date (a scan, so 30 per minute). */
export const GET = (req: Request) =>
  handle(async () => {
    const { ctx } = await authApp(req);
    const url = new URL(req.url);
    const q = querySearch(url);
    await enforce(ctx.db, `search:${ctx.userId}`, 30, 60, ctx.now());
    const result = await searchTasks(ctx, q, queryInt(url, 'limit', 1, SEARCH_MAX_LIMIT, 20), queryInt(url, 'offset', 0, 100_000, 0));
    return json({ query: q, ...result });
  });
