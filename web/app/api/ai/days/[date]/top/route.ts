import { resolveDate, withLabelNames } from '@/lib/ai';
import { aiJson, aiRoute, readBody } from '@/lib/http';
import { setTop } from '@/lib/services/focus';
import { dayView } from '@/lib/services/views';
import { topPut } from '@/lib/validation';

type Params = { params: Promise<{ date: string }> };

/** PUT {task_ids: [up to 3]} for a day (today|tomorrow|yesterday|YYYY-MM-DD): replaces that day's Top 3; [] clears it. */
export const PUT = (req: Request, { params }: Params) =>
  aiRoute(req, async (ctx) => {
    const date = resolveDate(ctx, (await params).date);
    await setTop(ctx, date, (await readBody(req, topPut)).task_ids);
    const view = await dayView(ctx, date);
    const top = (await withLabelNames(ctx, view.tasks.filter((t) => t.top_position != null))).sort((a, b) => a.top_position! - b.top_position!);
    return aiJson({ date, top });
  });
