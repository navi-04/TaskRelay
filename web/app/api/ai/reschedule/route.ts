import { resolveDate } from '@/lib/ai';
import { aiJson, aiRoute, readBody } from '@/lib/http';
import { moveTasks } from '@/lib/services/tasks';
import { idStr } from '@/lib/validation';
import { z } from 'zod';

const body = z.strictObject({ ids: z.array(idStr).min(1).max(50), to: z.string() });

/** Move up to 50 open one-off tasks to another day. Ineligible ids (done, recurring, unknown) are reported in `skipped`. */
export const POST = (req: Request) =>
  aiRoute(req, async (ctx) => {
    const { ids, to } = await readBody(req, body);
    return aiJson(await moveTasks(ctx, ids, resolveDate(ctx, to)));
  });
