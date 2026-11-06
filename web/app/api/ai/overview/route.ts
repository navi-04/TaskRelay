import { withLabelNames } from '@/lib/ai';
import { aiJson, aiRoute } from '@/lib/http';
import { overview } from '@/lib/services/views';

/** One read that answers "how is my day going": today, overdue, capacity vs limit, streak, week. */
export const GET = (req: Request) =>
  aiRoute(req, async (ctx) => {
    const o = await overview(ctx);
    return aiJson({
      ...o,
      tasks: await withLabelNames(ctx, o.tasks),
      overdue: o.overdue && { count: o.overdue.count, items: await withLabelNames(ctx, o.overdue.items) },
    });
  });
