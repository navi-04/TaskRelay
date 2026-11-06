import type { Ctx } from '../ctx';
import { badRequest, notFound, unprocessable } from '../errors';
import { occursOn } from '../recurrence';
import { writeBatch } from './version';

export const TOP_MAX = 3;

/**
 * Replace the Top-3 list for one day (idempotent set). Every task must be the caller's, live, occur on that day
 * and not be skipped that day, so an overdue task has to be moved to today before it can be starred.
 * Order in `taskIds` = position 1..3.
 */
export async function setTop(ctx: Ctx, date: string, taskIds: string[]): Promise<void> {
  if (taskIds.length > TOP_MAX) throw badRequest(`At most ${TOP_MAX} tasks can be in the Top ${TOP_MAX}`, 'invalid_top');
  if (new Set(taskIds).size !== taskIds.length) throw badRequest('A task can only appear once', 'invalid_top');

  if (taskIds.length > 0) {
    const marks = taskIds.map(() => '?').join(', ');
    const rs = await ctx.db.execute({
      sql: `SELECT id, recur, due_date, recur_until, recur_days FROM tasks
            WHERE user_id = ? AND deleted_at IS NULL AND id IN (${marks})`,
      args: [ctx.userId, ...taskIds],
    });
    const found = new Map(rs.rows.map((r) => [String(r.id), r]));
    for (const id of taskIds) {
      const r = found.get(id);
      if (!r) throw notFound('Task not found');
      const t = {
        recur: String(r.recur),
        due_date: String(r.due_date),
        recur_until: r.recur_until == null ? null : String(r.recur_until),
        recur_days: r.recur_days == null ? null : Number(r.recur_days),
      };
      if (!occursOn(t, date)) throw unprocessable('A task can only be in the Top 3 on a day it occurs', 'not_on_date');
    }
    const skipped = await ctx.db.execute({
      sql: `SELECT 1 FROM task_days WHERE user_id = ? AND date = ? AND status = 'skipped' AND task_id IN (${marks})`,
      args: [ctx.userId, date, ...taskIds],
    });
    if (skipped.rows.length > 0) throw unprocessable('A skipped task cannot be in the Top 3', 'not_on_date');
  }

  await writeBatch(ctx, [
    { sql: 'DELETE FROM day_focus WHERE user_id = ? AND date = ?', args: [ctx.userId, date] },
    ...taskIds.map((id, i) => ({
      sql: 'INSERT INTO day_focus (user_id, date, task_id, position) VALUES (?, ?, ?, ?)',
      args: [ctx.userId, date, id, i + 1],
    })),
  ]);
}
