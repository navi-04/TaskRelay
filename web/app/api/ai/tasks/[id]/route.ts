import { resolveBodyDates, resolveDate, resolveLabelNames, withLabelNames } from '@/lib/ai';
import { aiJson, aiRoute, readBody } from '@/lib/http';
import { deleteTask, getTask, updateTask } from '@/lib/services/tasks';
import { deleteScope, idStr, taskPatch } from '@/lib/validation';
import { z } from 'zod';

type Params = { params: Promise<{ id: string }> };

export const GET = (req: Request, { params }: Params) =>
  aiRoute(req, async (ctx, url) => {
    const id = idStr.parse((await params).id);
    const date = url.searchParams.get('date');
    const task = await getTask(ctx, id, date ? resolveDate(ctx, date) : undefined);
    return aiJson((await withLabelNames(ctx, [task]))[0]);
  });

export const PATCH = (req: Request, { params }: Params) =>
  aiRoute(req, async (ctx) => {
    const id = idStr.parse((await params).id);
    const raw = await readBody(req, z.record(z.string(), z.unknown()));
    const body = await resolveLabelNames(ctx, resolveBodyDates(ctx, raw));
    const task = await updateTask(ctx, id, taskPatch.parse(body));
    return aiJson((await withLabelNames(ctx, [task]))[0]);
  });

/** Soft delete only: the row is kept with deleted_at set. scope=all (default) | day:D | from:D. */
export const DELETE = (req: Request, { params }: Params) =>
  aiRoute(req, async (ctx, url) => {
    const id = idStr.parse((await params).id);
    const scope = deleteScope.parse(url.searchParams.get('scope') ?? 'all');
    await deleteTask(ctx, id, scope);
    return aiJson({ ok: true, deleted: id, scope });
  });
