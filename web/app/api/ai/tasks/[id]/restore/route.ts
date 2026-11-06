import { withLabelNames } from '@/lib/ai';
import { aiJson, aiRoute } from '@/lib/http';
import { restoreTask } from '@/lib/services/tasks';
import { idStr } from '@/lib/validation';

type Params = { params: Promise<{ id: string }> };

/** Undo a delete of a whole task (works for 30 days). Safe to repeat. */
export const POST = (req: Request, { params }: Params) =>
  aiRoute(req, async (ctx) => {
    const task = await restoreTask(ctx, idStr.parse((await params).id));
    return aiJson((await withLabelNames(ctx, [task]))[0]);
  });
