import type { InStatement } from '@libsql/client';
import type { Ctx } from '../ctx';

export const ACTIVITY_KINDS = ['created', 'updated', 'deleted', 'completed', 'rescheduled', 'restored'] as const;
export type ActivityKind = (typeof ACTIVITY_KINDS)[number];

const KEEP_PER_USER = 200;

/**
 * Audit statements to append to a write batch. Only AI changes are logged (the user sees their own edits happen),
 * so this returns [] for the app actor. The prune keeps the newest 200 rows per user.
 */
export function auditStatements(
  ctx: Ctx,
  kind: ActivityKind,
  task: { id: string; title: string },
  date: string | null = null,
  detail: string | null = null,
): InStatement[] {
  if (ctx.actor !== 'ai') return [];
  return [
    {
      sql: 'INSERT INTO activity (user_id, at, actor, kind, task_id, title, date, detail) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      args: [ctx.userId, ctx.now().toISOString(), ctx.actor, kind, task.id, task.title, date, detail],
    },
    {
      // Keep the newest 200: delete everything older than the 200th newest row.
      // With fewer than 200 rows the subquery is NULL and nothing is deleted.
      sql: `DELETE FROM activity WHERE user_id = ?
            AND id < (SELECT id FROM activity WHERE user_id = ? ORDER BY id DESC LIMIT 1 OFFSET ${KEEP_PER_USER - 1})`,
      args: [ctx.userId, ctx.userId],
    },
  ];
}

export interface ActivityItem {
  id: number;
  at: string;
  actor: string;
  kind: ActivityKind;
  task_id: string;
  title: string;
  date: string | null;
  detail: string | null;
}

/** Newest first. Pass the previous page's `next_before` as `before` to continue. */
export async function listActivity(ctx: Ctx, limit = 50, before?: number): Promise<{ items: ActivityItem[]; next_before: number | null }> {
  const rs = await ctx.db.execute({
    sql: `SELECT id, at, actor, kind, task_id, title, date, detail FROM activity
          WHERE user_id = :uid AND (:before IS NULL OR id < :before)
          ORDER BY id DESC LIMIT :n`,
    args: { uid: ctx.userId, before: before ?? null, n: limit + 1 },
  });
  const rows = rs.rows.slice(0, limit);
  const items = rows.map((r) => ({
    id: Number(r.id),
    at: String(r.at),
    actor: String(r.actor),
    kind: String(r.kind) as ActivityKind,
    task_id: String(r.task_id),
    title: String(r.title),
    date: r.date == null ? null : String(r.date),
    detail: r.detail == null ? null : String(r.detail),
  }));
  return { items, next_before: rs.rows.length > limit ? items[items.length - 1].id : null };
}
