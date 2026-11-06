import { authApp, handle } from '@/lib/http';
import { exportAccount } from '@/lib/services/account';

/** GET /me/export - a JSON download of all your data (no password hash, AI id or sessions). 5 per hour. */
export const GET = (req: Request) =>
  handle(async () => {
    const { ctx } = await authApp(req);
    const data = await exportAccount(ctx.db, ctx.userId, ctx.now());
    return new Response(JSON.stringify(data, null, 2), {
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Content-Disposition': 'attachment; filename="taskrelay-export.json"',
        'Cache-Control': 'no-store',
      },
    });
  });
