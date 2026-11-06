import { authApp, clearedSessionCookie, handle, json } from '@/lib/http';
import { logout } from '@/lib/services/auth';

export const POST = (req: Request) =>
  handle(async () => {
    const { ctx, token } = await authApp(req);
    await logout(ctx.db, token);
    return json({ ok: true }, 200, { 'Set-Cookie': clearedSessionCookie(req) });
  });
