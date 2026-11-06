import { authApp, handle, json, readBody } from '@/lib/http';
import { getMe, setAiEnabled } from '@/lib/services/auth';
import { aiAccessPatch } from '@/lib/validation';

/** Switch AI access on or off. */
export const PATCH = (req: Request) =>
  handle(async () => {
    const { ctx } = await authApp(req);
    const { enabled } = await readBody(req, aiAccessPatch);
    await setAiEnabled(ctx.db, ctx.userId, enabled);
    return json(await getMe(ctx.db, ctx.userId));
  });
