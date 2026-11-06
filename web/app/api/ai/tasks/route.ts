import { resolveBodyDates, resolveDate, resolveLabelNames, withLabelNames } from '@/lib/ai';
import { badRequest } from '@/lib/errors';
import { aiJson, aiRoute, readBody, todayOf } from '@/lib/http';
import { createTask, listTasksForDate } from '@/lib/services/tasks';
import { addDays, daysBetween } from '@/lib/time';
import { taskCreate } from '@/lib/validation';
import { z } from 'zod';

const MAX_DAYS = 31;
const MAX_TASKS = 200;

/** ?date=today|tomorrow|YYYY-MM-DD for one day, or ?from=&to= for up to 31 days (max 200 tasks, `truncated` if cut). */
export const GET = (req: Request) =>
  aiRoute(req, async (ctx, url) => {
    const from = url.searchParams.get('from');
    const to = url.searchParams.get('to');
    if (from || to) {
      const start = resolveDate(ctx, from ?? to!);
      const end = resolveDate(ctx, to ?? from!);
      if (end < start) throw badRequest('`to` cannot be before `from`', 'invalid_range');
      if (daysBetween(start, end) + 1 > MAX_DAYS) throw badRequest(`Range is limited to ${MAX_DAYS} days`, 'range_too_large');
      const dates: string[] = [];
      for (let d = start; d <= end; d = addDays(d, 1)) dates.push(d);
      const perDay = await Promise.all(dates.map((d) => listTasksForDate(ctx, d)));
      const all = perDay.flat();
      const tasks = await withLabelNames(ctx, all.slice(0, MAX_TASKS));
      return aiJson({ from: start, to: end, count: all.length, truncated: all.length > MAX_TASKS, tasks });
    }
    const date = resolveDate(ctx, url.searchParams.get('date') ?? 'today');
    const tasks = await listTasksForDate(ctx, date);
    return aiJson({ date, today: todayOf(ctx), count: tasks.length, tasks: await withLabelNames(ctx, tasks) });
  });

export const POST = (req: Request) =>
  aiRoute(req, async (ctx) => {
    const raw = await readBody(req, z.record(z.string(), z.unknown()));
    const body = await resolveLabelNames(ctx, resolveBodyDates(ctx, raw));
    const task = await createTask(ctx, taskCreate.parse(body));
    return aiJson((await withLabelNames(ctx, [task]))[0], 201);
  });
