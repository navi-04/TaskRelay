import { aiJson, aiRoute } from '@/lib/http';
import { listLabels } from '@/lib/services/labels';

/** Valid task types and priorities. Names can be used directly as `type` / `priority` when creating or editing tasks. */
export const GET = (req: Request) => aiRoute(req, async (ctx) => aiJson(await listLabels(ctx)));
