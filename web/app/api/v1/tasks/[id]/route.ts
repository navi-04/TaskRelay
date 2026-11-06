import { authApp, handle, json, queryDate, readBody } from '@/lib/http';
import { deleteTask, getTask, updateTask } from '@/lib/services/tasks';
import { deleteScope, idStr, taskPatch } from '@/lib/validation';

type Ctx = { params: Promise<{ id: string }> };

/** GET /tasks/:id?date= -> the task as seen on that day (default: its due date). */
export const GET = (req: Request, { params }: Ctx) =>
  handle(async () => {
    const { ctx } = await authApp(req);
    const id = idStr.parse((await params).id);
    return json(await getTask(ctx, id, queryDate(new URL(req.url), 'date')));
  });

/** PATCH edits the whole series for a recurring task. */
export const PATCH = (req: Request, { params }: Ctx) =>
  handle(async () => {
    const { ctx } = await authApp(req);
    const id = idStr.parse((await params).id);
    return json(await updateTask(ctx, id, await readBody(req, taskPatch)));
  });

/** DELETE /tasks/:id?scope=all|day:D|from:D (default all). */
export const DELETE = (req: Request, { params }: Ctx) =>
  handle(async () => {
    const { ctx } = await authApp(req);
    const id = idStr.parse((await params).id);
    const scope = deleteScope.parse(new URL(req.url).searchParams.get('scope') ?? 'all');
    await deleteTask(ctx, id, scope);
    return json({ ok: true });
  });
