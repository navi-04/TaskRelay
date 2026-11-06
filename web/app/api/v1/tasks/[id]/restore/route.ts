import { authApp, handle, json } from '@/lib/http';
import { restoreTask } from '@/lib/services/tasks';
import { idStr } from '@/lib/validation';

type Params = { params: Promise<{ id: string }> };

/** POST /tasks/:id/restore - undo a delete (within 30 days). Safe to repeat. */
export const POST = (req: Request, { params }: Params) =>
  handle(async () => {
    const { ctx } = await authApp(req);
    return json(await restoreTask(ctx, idStr.parse((await params).id)));
  });
