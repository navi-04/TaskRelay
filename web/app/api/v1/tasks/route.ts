import { authApp, handle, json, queryDate, readBody, todayOf } from '@/lib/http';
import { createTask } from '@/lib/services/tasks';
import { dayView } from '@/lib/services/views';
import { taskCreate } from '@/lib/validation';

/** GET /tasks?date=YYYY-MM-DD (default: today) -> that day's tasks, totals, and overdue list when the day is today. */
export const GET = (req: Request) =>
  handle(async () => {
    const { ctx } = await authApp(req);
    const date = queryDate(new URL(req.url), 'date') ?? todayOf(ctx);
    return json(await dayView(ctx, date));
  });

/** POST /tasks: the client supplies the id, so retrying a create is safe. */
export const POST = (req: Request) =>
  handle(async () => {
    const { ctx } = await authApp(req);
    return json(await createTask(ctx, await readBody(req, taskCreate)), 201);
  });
