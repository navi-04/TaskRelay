import { authApp, handle, json, readBody } from '@/lib/http';
import { deleteLabel, updateLabel } from '@/lib/services/labels';
import { idStr, labelPatch } from '@/lib/validation';

type Ctx = { params: Promise<{ id: string }> };

export const PATCH = (req: Request, { params }: Ctx) =>
  handle(async () => {
    const { ctx } = await authApp(req);
    return json(await updateLabel(ctx, idStr.parse((await params).id), await readBody(req, labelPatch)));
  });

/** Deleting a label detaches it from tasks; the last label of a kind can't be deleted. */
export const DELETE = (req: Request, { params }: Ctx) =>
  handle(async () => {
    const { ctx } = await authApp(req);
    await deleteLabel(ctx, idStr.parse((await params).id));
    return json({ ok: true });
  });
