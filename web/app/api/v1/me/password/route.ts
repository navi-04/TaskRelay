import { authApp, handle, json, readBody } from '@/lib/http';
import { changePassword } from '@/lib/services/account';
import { sessionTokenHash } from '@/lib/services/auth';
import { passwordChange } from '@/lib/validation';

/** POST /me/password {current_password, new_password} - signs out every other session, keeps this one. */
export const POST = (req: Request) =>
  handle(async () => {
    const { ctx, token } = await authApp(req);
    await changePassword(ctx.db, ctx.userId, await readBody(req, passwordChange), sessionTokenHash(token), ctx.now());
    return json({ ok: true });
  });
