import { authApp, handle, json, readBody } from '@/lib/http';
import { setTop } from '@/lib/services/focus';
import { dayView } from '@/lib/services/views';
import { dateStr, topPut } from '@/lib/validation';

type Params = { params: Promise<{ date: string }> };

/** PUT /days/:date/top {task_ids: [up to 3]} - replace that day's Top 3 (order = priority). Returns the day. */
export const PUT = (req: Request, { params }: Params) =>
  handle(async () => {
    const { ctx } = await authApp(req);
    const date = dateStr.parse((await params).date);
    await setTop(ctx, date, (await readBody(req, topPut)).task_ids);
    return json(await dayView(ctx, date));
  });
