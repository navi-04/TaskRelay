import { authApp, handle, json, queryInt } from '@/lib/http';
import { listActivity } from '@/lib/services/activity';

/** GET /activity?limit=&before= - what an AI assistant changed (newest first); pass `next_before` as `before` for the next page. */
export const GET = (req: Request) =>
  handle(async () => {
    const { ctx } = await authApp(req);
    const url = new URL(req.url);
    const before = url.searchParams.get('before');
    return json(await listActivity(ctx, queryInt(url, 'limit', 1, 100, 50), before ? queryInt(url, 'before', 1, Number.MAX_SAFE_INTEGER, 0) : undefined));
  });
