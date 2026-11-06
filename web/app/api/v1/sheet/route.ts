import { authApp, handle, json, queryDate } from '@/lib/http';
import { sheetView } from '@/lib/services/sheet';

/**
 * GET /sheet?from=&to= (max 92 days; default the whole current month)
 * -> one row per day: a tick cell per repeating task, the day's one-off tasks, Done / Total / %, and notes.
 */
export const GET = (req: Request) =>
  handle(async () => {
    const { ctx } = await authApp(req);
    const url = new URL(req.url);
    return json(await sheetView(ctx, queryDate(url, 'from'), queryDate(url, 'to')));
  });
