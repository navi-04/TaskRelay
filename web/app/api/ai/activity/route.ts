import { aiJson, aiRoute, queryInt } from '@/lib/http';
import { listActivity } from '@/lib/services/activity';

/** What AI assistants changed recently, newest first. ?limit=50&before=<id> for the next page. */
export const GET = (req: Request) =>
  aiRoute(req, async (ctx, url) => {
    const before = url.searchParams.get('before');
    return aiJson(await listActivity(ctx, queryInt(url, 'limit', 1, 100, 50), before ? queryInt(url, 'before', 1, Number.MAX_SAFE_INTEGER, 0) : undefined));
  });
