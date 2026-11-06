import { authApp, handle, json, queryDate } from '@/lib/http';
import { weeklyReview } from '@/lib/services/review';

/** GET /review?week_start=YYYY-MM-DD - a week in review (default: the last 7 days), with a ready-made planning prompt. */
export const GET = (req: Request) =>
  handle(async () => {
    const { ctx } = await authApp(req);
    return json(await weeklyReview(ctx, queryDate(new URL(req.url), 'week_start')));
  });
