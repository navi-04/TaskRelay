import { authApp, handle, json, readBody } from '@/lib/http';
import { getMe, setTimezone } from '@/lib/services/auth';
import { mePatch } from '@/lib/validation';

export const GET = (req: Request) =>
  handle(async () => {
    const { ctx } = await authApp(req);
    return json(await getMe(ctx.db, ctx.userId));
  });

/** The app reports the device timezone here so the server's notion of "today" matches the phone. */
export const PATCH = (req: Request) =>
  handle(async () => {
    const { ctx } = await authApp(req);
    const { timezone } = await readBody(req, mePatch);
    await setTimezone(ctx.db, ctx.userId, timezone);
    return json(await getMe(ctx.db, ctx.userId));
  });
