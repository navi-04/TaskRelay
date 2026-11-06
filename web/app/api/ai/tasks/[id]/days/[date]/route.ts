import { resolveDate, withLabelNames } from '@/lib/ai';
import { aiJson, aiRoute, readBody } from '@/lib/http';
import { setDay } from '@/lib/services/tasks';
import { dayPut, idStr } from '@/lib/validation';

type Params = { params: Promise<{ id: string; date: string }> };

/** PUT {status: done|skipped|open, note?} for one task on one day (today|tomorrow|yesterday|YYYY-MM-DD). Safe to repeat. */
export const PUT = (req: Request, { params }: Params) =>
  aiRoute(req, async (ctx) => {
    const p = await params;
    const task = await setDay(ctx, idStr.parse(p.id), resolveDate(ctx, p.date), await readBody(req, dayPut));
    return aiJson((await withLabelNames(ctx, [task]))[0]);
  });
