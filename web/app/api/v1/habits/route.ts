import { authApp, handle, json, queryDate, queryInt, todayOf } from '@/lib/http';
import { listHabits } from '@/lib/services/habits';

/** GET /habits?date=&days=90 (7-365) - streak, best streak, rates and a 7-day strip for every active repeating task. */
export const GET = (req: Request) =>
  handle(async () => {
    const { ctx } = await authApp(req);
    const url = new URL(req.url);
    return json(await listHabits(ctx, queryDate(url, 'date') ?? todayOf(ctx), queryInt(url, 'days', 7, 365, 90)));
  });
