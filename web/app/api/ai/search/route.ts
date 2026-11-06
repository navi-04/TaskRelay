import { withLabelNames } from '@/lib/ai';
import { aiJson, aiRoute, queryInt, querySearch } from '@/lib/http';
import { searchTasks, SEARCH_MAX_LIMIT } from '@/lib/services/search';

/** Find tasks by title or notes across all dates: ?q=invoice&limit=20&offset=0 */
export const GET = (req: Request) =>
  aiRoute(req, async (ctx, url) => {
    const q = querySearch(url);
    const { items, has_more } = await searchTasks(ctx, q, queryInt(url, 'limit', 1, SEARCH_MAX_LIMIT, 20), queryInt(url, 'offset', 0, 100_000, 0));
    return aiJson({ query: q, has_more, tasks: await withLabelNames(ctx, items) });
  });
