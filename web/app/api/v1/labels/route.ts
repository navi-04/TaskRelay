import { authApp, handle, json, readBody } from '@/lib/http';
import { createLabel, listLabels } from '@/lib/services/labels';
import { labelCreate } from '@/lib/validation';

export const GET = (req: Request) =>
  handle(async () => {
    const { ctx } = await authApp(req);
    return json(await listLabels(ctx));
  });

export const POST = (req: Request) =>
  handle(async () => {
    const { ctx } = await authApp(req);
    return json(await createLabel(ctx, await readBody(req, labelCreate)), 201);
  });
