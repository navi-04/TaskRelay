import { authApp, handle, json } from '@/lib/http';
import { deleteAllTasks } from '@/lib/services/auth';

/** Delete every task and per-day record. The account, labels and settings are kept. */
export const DELETE = (req: Request) =>
  handle(async () => {
    const { ctx } = await authApp(req);
    await deleteAllTasks(ctx.db, ctx.userId);
    return json({ ok: true });
  });
