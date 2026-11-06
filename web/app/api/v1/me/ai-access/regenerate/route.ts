import { authApp, handle, json } from '@/lib/http';
import { regenerateAiAccess } from '@/lib/services/auth';

/** Issue a new AI access id; the previous one stops working immediately. */
export const POST = (req: Request) =>
  handle(async () => {
    const { ctx } = await authApp(req);
    return json({ ai_access_id: await regenerateAiAccess(ctx.db, ctx.userId) });
  });
