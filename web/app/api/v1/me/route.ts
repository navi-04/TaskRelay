import { authApp, clearedSessionCookie, handle, json, readBody } from '@/lib/http';
import { deleteAccount } from '@/lib/services/account';
import { getMe, setTimezone } from '@/lib/services/auth';
import { accountDelete, mePatch } from '@/lib/validation';

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

/** DELETE /me {password} - permanently deletes the account and all its data. */
export const DELETE = (req: Request) =>
  handle(async () => {
    const { ctx } = await authApp(req);
    await deleteAccount(ctx.db, ctx.userId, (await readBody(req, accountDelete)).password, ctx.now());
    return json({ ok: true }, 200, { 'Set-Cookie': clearedSessionCookie(req) });
  });
