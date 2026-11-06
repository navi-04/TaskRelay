import { authApp, handle, json, readBody } from '@/lib/http';
import { setDay } from '@/lib/services/tasks';
import { dateStr, dayPut, idStr } from '@/lib/validation';

type Ctx = { params: Promise<{ id: string; date: string }> };

/** PUT sets the state of one task on one day: {status: done|skipped|open, note?, completed_at?}. Idempotent. */
export const PUT = (req: Request, { params }: Ctx) =>
  handle(async () => {
    const { ctx } = await authApp(req);
    const p = await params;
    return json(await setDay(ctx, idStr.parse(p.id), dateStr.parse(p.date), await readBody(req, dayPut)));
  });
