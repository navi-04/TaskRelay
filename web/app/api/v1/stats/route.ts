import { authApp, handle, json, queryDate } from '@/lib/http';
import { statsView } from '@/lib/services/views';

/** GET /stats?from=&to= (max 62 days; default the last 7 days) -> per-day totals, streak, rolling week. */
export const GET = (req: Request) =>
  handle(async () => {
    const { ctx } = await authApp(req);
    const url = new URL(req.url);
    return json(await statsView(ctx, queryDate(url, 'from'), queryDate(url, 'to')));
  });
