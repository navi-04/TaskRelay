import { resolveDate } from '@/lib/ai';
import { aiJson, aiRoute } from '@/lib/http';
import { weeklyReview } from '@/lib/services/review';

/** A week in review (default: the last 7 days). ?week_start=YYYY-MM-DD (or "today"/"yesterday") picks another week. */
export const GET = (req: Request) =>
  aiRoute(req, async (ctx, url) => {
    const ws = url.searchParams.get('week_start');
    return aiJson(await weeklyReview(ctx, ws ? resolveDate(ctx, ws) : undefined));
  });
