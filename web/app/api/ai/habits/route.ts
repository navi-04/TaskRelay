import { resolveDate } from '@/lib/ai';
import { aiJson, aiRoute, queryInt } from '@/lib/http';
import { listHabits } from '@/lib/services/habits';

/** Every active repeating task with streaks, rates and a 7-day strip. Optional ?date=today and ?days=90. */
export const GET = (req: Request) =>
  aiRoute(req, async (ctx, url) => aiJson(await listHabits(ctx, resolveDate(ctx, url.searchParams.get('date') ?? 'today'), queryInt(url, 'days', 7, 365, 90))));
