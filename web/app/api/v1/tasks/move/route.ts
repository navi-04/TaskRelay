import { authApp, handle, json, readBody } from '@/lib/http';
import { moveTasks } from '@/lib/services/tasks';
import { movePost } from '@/lib/validation';

/** Move open one-off tasks (up to 50) to another day, e.g. "move all overdue to today". */
export const POST = (req: Request) =>
  handle(async () => {
    const { ctx } = await authApp(req);
    const { ids, to } = await readBody(req, movePost);
    return json(await moveTasks(ctx, ids, to));
  });
