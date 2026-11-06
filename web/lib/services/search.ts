import type { Ctx } from '../ctx';
import { TASK_COLS, toTaskDto, type TaskDto } from './tasks';

export const SEARCH_MAX_LIMIT = 50;

/**
 * Title + notes search across every date. User-scoped, deleted tasks excluded, title matches first,
 * then most recent. LIKE is ASCII-case-insensitive; `%`, `_` and `\` in the query are matched literally.
 * Each result carries the done/skipped state of its due date. O(user tasks), so callers rate-limit it.
 */
export async function searchTasks(
  ctx: Ctx,
  query: string,
  limit = 20,
  offset = 0,
): Promise<{ items: TaskDto[]; has_more: boolean }> {
  const pattern = `%${query.trim().replace(/[\\%_]/g, '\\$&')}%`;
  const rs = await ctx.db.execute({
    sql: `SELECT ${TASK_COLS},
                 td.status AS day_status, td.note AS day_note, td.completed_at AS day_completed_at,
                 td.updated_by AS day_updated_by, NULL AS top_position
          FROM tasks t
          LEFT JOIN task_days td ON td.task_id = t.id AND td.date = t.due_date
          WHERE t.user_id = :uid AND t.deleted_at IS NULL
            AND (t.title LIKE :p ESCAPE '\\' OR COALESCE(t.notes, '') LIKE :p ESCAPE '\\')
          ORDER BY (t.title LIKE :p ESCAPE '\\') DESC, t.due_date DESC, t.id
          LIMIT :n OFFSET :o`,
    args: { uid: ctx.userId, p: pattern, n: limit + 1, o: offset },
  });
  const items = rs.rows.slice(0, limit).map((r) => toTaskDto(r, String(r.due_date)));
  return { items, has_more: rs.rows.length > limit };
}
