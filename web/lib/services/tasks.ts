import type { InStatement, Row } from '@libsql/client';
import type { Ctx } from '../ctx';
import { badRequest, conflict, notFound, unprocessable } from '../errors';
import { daysToMask, firstOccurrence, maskToDays, occursOn, occursSql, type Recurring } from '../recurrence';
import { addDays, dateOf, todayFor } from '../time';
import type { DayPut, TaskCreate, TaskPatch } from '../validation';
import { auditStatements } from './activity';
import { assertOwnedLabel } from './labels';
import { writeBatch } from './version';

export interface TaskDto {
  id: string;
  title: string;
  notes: string | null;
  duration_min: number;
  type_id: string | null;
  priority_id: string | null;
  due_date: string;
  alarm_time: string | null;
  reminder_kind: 'alarm' | 'notification';
  recur: 'none' | 'daily';
  recur_until: string | null;
  /** Weekdays a repeating task occurs on (1=Mon..7=Sun); null = every day. */
  recur_days: number[] | null;
  created_at: string;
  updated_at: string;
  /** Who last changed the task itself: the user's app/web, or an AI assistant. */
  updated_by: 'app' | 'ai';
  /** The calendar day this view of the task is for (recurring tasks occur on many days). */
  date: string;
  status: 'open' | 'done' | 'skipped';
  day_note: string | null;
  completed_at: string | null;
  /** Who last changed this day's state (done/skipped), if it has one. */
  day_updated_by: 'app' | 'ai' | null;
  /** 1..3 when the task is one of that day's Top 3. */
  top_position: 1 | 2 | 3 | null;
}

export const TASK_COLS =
  't.id, t.title, t.notes, t.duration_min, t.type_id, t.priority_id, t.due_date, t.alarm_time, t.reminder_kind, t.recur, t.recur_until, t.recur_days, t.created_at, t.updated_at, t.updated_by';
/** Needs `td` (task_days) and `f` (day_focus) joined for the day being viewed. */
export const DAY_COLS =
  'td.status AS day_status, td.note AS day_note, td.completed_at AS day_completed_at, td.updated_by AS day_updated_by, f.position AS top_position';
/** For queries that return tasks without a specific day attached (overdue, search). */
export const NO_DAY_COLS =
  'NULL AS day_status, NULL AS day_note, NULL AS day_completed_at, NULL AS day_updated_by, NULL AS top_position';
const topJoin = (dateExpr: string) => `LEFT JOIN day_focus f ON f.user_id = t.user_id AND f.task_id = t.id AND f.date = ${dateExpr}`;

const str = (v: unknown): string | null => (v == null ? null : String(v));

export function toTaskDto(r: Row, date: string): TaskDto {
  return {
    id: String(r.id),
    title: String(r.title),
    notes: str(r.notes),
    duration_min: Number(r.duration_min),
    type_id: str(r.type_id),
    priority_id: str(r.priority_id),
    due_date: String(r.due_date),
    alarm_time: str(r.alarm_time),
    reminder_kind: String(r.reminder_kind) as TaskDto['reminder_kind'],
    recur: String(r.recur) as TaskDto['recur'],
    recur_until: str(r.recur_until),
    recur_days: maskToDays(r.recur_days == null ? null : Number(r.recur_days)),
    created_at: String(r.created_at),
    updated_at: String(r.updated_at),
    updated_by: String(r.updated_by) as TaskDto['updated_by'],
    date,
    status: (str(r.day_status) as 'done' | 'skipped' | null) ?? 'open',
    day_note: str(r.day_note),
    completed_at: str(r.day_completed_at),
    day_updated_by: str(r.day_updated_by) as TaskDto['day_updated_by'],
    top_position: r.top_position == null ? null : (Number(r.top_position) as 1 | 2 | 3),
  };
}

async function getOwnedRow(ctx: Ctx, id: string): Promise<Row> {
  const rs = await ctx.db.execute({
    sql: 'SELECT * FROM tasks WHERE id = ? AND user_id = ? AND deleted_at IS NULL',
    args: [id, ctx.userId],
  });
  if (rs.rows.length === 0) throw notFound('Task not found');
  return rs.rows[0];
}

export const rowRecurring = (r: Row): Recurring => ({
  recur: String(r.recur),
  due_date: String(r.due_date),
  recur_until: str(r.recur_until),
  recur_days: r.recur_days == null ? null : Number(r.recur_days),
});

// ───────────────────────────── reads ─────────────────────────────

/** The tasks that occur on `date`, recurrence resolved, done state for that day attached. Skipped days are hidden. */
export async function listTasksForDate(ctx: Ctx, date: string): Promise<TaskDto[]> {
  const rs = await ctx.db.execute({
    sql: `SELECT ${TASK_COLS}, ${DAY_COLS}
          FROM tasks t
          LEFT JOIN task_days td ON td.task_id = t.id AND td.date = :d
          ${topJoin(':d')}
          LEFT JOIN labels p ON p.id = t.priority_id AND p.user_id = t.user_id
          WHERE t.user_id = :uid AND t.deleted_at IS NULL
            AND ${occursSql('t', ':d')}
            AND COALESCE(td.status, 'open') <> 'skipped'
          ORDER BY COALESCE(td.status = 'done', 0), (p.sort_order IS NULL), p.sort_order DESC,
                   (t.alarm_time IS NULL), t.alarm_time, t.created_at, t.id`,
    args: { d: date, uid: ctx.userId },
  });
  return rs.rows.map((r) => toTaskDto(r, date));
}

const OVERDUE_LIMIT = 50;
/** Older open one-offs are not "overdue" any more (keeps the Today query bounded). */
export const OVERDUE_LOOKBACK_DAYS = 90;

const OVERDUE_WHERE = `t.user_id = :uid AND t.deleted_at IS NULL AND t.recur = 'none'
  AND t.due_date < :today AND t.due_date >= date(:today, '-${OVERDUE_LOOKBACK_DAYS} day')
  AND NOT EXISTS (SELECT 1 FROM task_days td WHERE td.task_id = t.id AND td.date = t.due_date)`;

/**
 * Overdue = one-off, not deleted, due in the last 90 days before today, with no done/skipped record on its due date.
 * Recurring tasks are never overdue (a missed day is just missed). Nothing is rewritten: this is a query.
 */
export async function listOverdue(ctx: Ctx, today: string): Promise<{ items: TaskDto[]; count: number }> {
  const [items, count] = await Promise.all([
    ctx.db.execute({
      sql: `SELECT ${TASK_COLS}, ${NO_DAY_COLS}
            FROM tasks t WHERE ${OVERDUE_WHERE} ORDER BY t.due_date DESC, t.created_at, t.id LIMIT ${OVERDUE_LIMIT}`,
      args: { uid: ctx.userId, today },
    }),
    countOverdue(ctx, today),
  ]);
  return { items: items.rows.map((r) => toTaskDto(r, String(r.due_date))), count };
}

export async function countOverdue(ctx: Ctx, today: string): Promise<number> {
  const rs = await ctx.db.execute({ sql: `SELECT COUNT(*) AS n FROM tasks t WHERE ${OVERDUE_WHERE}`, args: { uid: ctx.userId, today } });
  return Number(rs.rows[0].n);
}

export async function getTask(ctx: Ctx, id: string, date?: string): Promise<TaskDto> {
  const rs = await ctx.db.execute({
    sql: `SELECT ${TASK_COLS}, ${DAY_COLS}
          FROM tasks t
          LEFT JOIN task_days td ON td.task_id = t.id AND td.date = COALESCE(:d, t.due_date)
          ${topJoin('COALESCE(:d, t.due_date)')}
          WHERE t.id = :id AND t.user_id = :uid AND t.deleted_at IS NULL`,
    args: { d: date ?? null, id, uid: ctx.userId },
  });
  if (rs.rows.length === 0) throw notFound('Task not found');
  return toTaskDto(rs.rows[0], date ?? String(rs.rows[0].due_date));
}

/** Totals for a list of resolved tasks (what the Today header and the AI overview show). */
export function summarize(tasks: TaskDto[]) {
  const done = tasks.filter((t) => t.status === 'done');
  return {
    planned: tasks.length,
    done: done.length,
    planned_min: tasks.reduce((s, t) => s + t.duration_min, 0),
    done_min: done.reduce((s, t) => s + t.duration_min, 0),
  };
}

// ───────────────────────────── writes ─────────────────────────────

function assertRecurrence(r: Recurring) {
  if (r.recur === 'none') {
    if (r.recur_until != null) throw unprocessable('recur_until only applies to repeating tasks', 'invalid_recurrence');
    if (r.recur_days != null) throw unprocessable('recur_days only applies to repeating tasks', 'invalid_recurrence');
    return;
  }
  if (r.recur_until != null && r.recur_until < r.due_date) {
    throw unprocessable('recur_until cannot be before the start date', 'invalid_recurrence');
  }
  // A weekday pattern that never lands before the end date would create an invisible task.
  if (firstOccurrence(r) == null) {
    throw unprocessable('The chosen weekdays never occur before the end date', 'invalid_recurrence');
  }
}

/** Idempotent on `id`: creating the same id twice returns the first row; another user's id is a generic 409. */
export async function createTask(ctx: Ctx, input: TaskCreate): Promise<TaskDto> {
  const recurring: Recurring = {
    recur: input.recur,
    due_date: input.due_date,
    recur_until: input.recur_until ?? null,
    recur_days: daysToMask(input.recur_days),
  };
  assertRecurrence(recurring);
  await assertOwnedLabel(ctx, input.type_id, 'type');
  await assertOwnedLabel(ctx, input.priority_id, 'priority');

  const id = input.id ?? crypto.randomUUID();
  // A retried create (same id, same user, still live) is a pure read: no write, no version bump, no duplicate audit row.
  const existing = await ctx.db.execute({ sql: 'SELECT user_id, deleted_at FROM tasks WHERE id = ?', args: [id] });
  if (existing.rows.length > 0) {
    const mine = String(existing.rows[0].user_id) === ctx.userId && existing.rows[0].deleted_at == null;
    if (!mine) throw conflict('That task id is already in use', 'id_in_use');
    return getTask(ctx, id);
  }

  const now = ctx.now().toISOString();
  const [rs] = await writeBatch(ctx, [
    {
      sql: `INSERT INTO tasks (id, user_id, title, notes, duration_min, type_id, priority_id, due_date, alarm_time,
                               reminder_kind, recur, recur_until, recur_days, created_at, updated_at, updated_by)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO NOTHING`,
      args: [
        id, ctx.userId, input.title, input.notes ?? null, input.duration_min, input.type_id ?? null,
        input.priority_id ?? null, input.due_date, input.alarm_time ?? null, input.reminder_kind, input.recur,
        recurring.recur_until, recurring.recur_days, now, now, ctx.actor,
      ],
    },
    ...auditStatements(ctx, 'created', { id, title: input.title }, input.due_date),
  ]);
  if (rs.rowsAffected === 0) throw conflict('That task id is already in use', 'id_in_use'); // lost a race for the id
  return getTask(ctx, id);
}

export async function updateTask(ctx: Ctx, id: string, patch: TaskPatch): Promise<TaskDto> {
  const old = await getOwnedRow(ctx, id);
  const oldRecur = String(old.recur);
  const oldDue = String(old.due_date);

  const recur = patch.recur ?? (oldRecur as 'none' | 'daily');
  if (recur === 'none' && patch.recur_days != null) {
    throw unprocessable('recur_days only applies to repeating tasks', 'invalid_recurrence');
  }
  const merged: Recurring = {
    recur,
    due_date: patch.due_date ?? oldDue,
    recur_until: patch.recur_until !== undefined ? patch.recur_until : str(old.recur_until),
    recur_days: patch.recur_days !== undefined ? daysToMask(patch.recur_days) : old.recur_days == null ? null : Number(old.recur_days),
  };
  if (merged.recur === 'none') {
    // A one-off has no end date or weekdays; converting a series to a one-off clears them.
    merged.recur_until = null;
    merged.recur_days = null;
  }
  assertRecurrence(merged);
  if (patch.type_id !== undefined) await assertOwnedLabel(ctx, patch.type_id, 'type');
  if (patch.priority_id !== undefined) await assertOwnedLabel(ctx, patch.priority_id, 'priority');

  const statements: InStatement[] = [];
  if (oldRecur === 'none' && merged.recur === 'none' && merged.due_date !== oldDue) {
    // Only an open one-off can be rescheduled; otherwise its done/skipped row would be orphaned.
    const day = await ctx.db.execute({ sql: 'SELECT 1 FROM task_days WHERE task_id = ? AND date = ?', args: [id, oldDue] });
    if (day.rows.length > 0) throw conflict('Only open tasks can be rescheduled', 'not_open');
  }
  if (oldRecur === 'daily' && merged.recur === 'none') {
    // A one-off has exactly one day; drop the per-day rows of the old series.
    statements.push({ sql: 'DELETE FROM task_days WHERE task_id = ? AND date <> ?', args: [id, merged.due_date] });
  }

  const sets = ['updated_at = ?', 'updated_by = ?'];
  const args: Array<string | number | null> = [ctx.now().toISOString(), ctx.actor];
  const columns = ['title', 'notes', 'duration_min', 'type_id', 'priority_id', 'due_date', 'alarm_time', 'reminder_kind', 'recur'] as const;
  for (const c of columns) {
    if (patch[c] !== undefined) {
      sets.push(`${c} = ?`);
      args.push(patch[c] as string | number | null);
    }
  }
  sets.push('recur_until = ?', 'recur_days = ?');
  args.push(merged.recur_until, merged.recur_days);
  statements.push({ sql: `UPDATE tasks SET ${sets.join(', ')} WHERE id = ? AND user_id = ?`, args: [...args, id, ctx.userId] });

  const rescheduled = merged.due_date !== oldDue && merged.recur === 'none';
  statements.push(
    ...auditStatements(ctx, rescheduled ? 'rescheduled' : 'updated', { id, title: patch.title ?? String(old.title) }, merged.due_date, rescheduled ? `from ${oldDue}` : null),
  );

  await writeBatch(ctx, statements);
  return getTask(ctx, id);
}

const PURGE_AFTER_DAYS = 30;
/** How long a deleted task can be brought back (and how long it is kept before being purged). */
export const RESTORE_WINDOW_DAYS = PURGE_AFTER_DAYS;

/** Hard-delete this user's tasks that were soft-deleted more than 30 days ago (runs lazily with any delete). */
function purgeStatements(ctx: Ctx): InStatement[] {
  const cutoff = new Date(ctx.now().getTime() - PURGE_AFTER_DAYS * 86_400_000).toISOString();
  const expired = 'SELECT id FROM tasks WHERE user_id = ? AND deleted_at IS NOT NULL AND deleted_at < ?';
  const args = [ctx.userId, ctx.userId, cutoff];
  return [
    { sql: `DELETE FROM task_days WHERE user_id = ? AND task_id IN (${expired})`, args },
    { sql: `DELETE FROM day_focus WHERE user_id = ? AND task_id IN (${expired})`, args },
    { sql: 'DELETE FROM tasks WHERE user_id = ? AND deleted_at IS NOT NULL AND deleted_at < ?', args: [ctx.userId, cutoff] },
  ];
}

/**
 * scope: `all` | `day:D` | `from:D`. A one-off has one day, so any scope deletes it.
 * Recurring: `day:D` skips that day; `from:D` ends the series the day before D (or deletes it if D is its first day).
 * Deletes are soft (deleted_at) and can be undone with restoreTask for 30 days.
 */
export async function deleteTask(ctx: Ctx, id: string, scope: string): Promise<void> {
  const row = await getOwnedRow(ctx, id);
  const t = rowRecurring(row);
  const title = String(row.title);
  const [kind, arg] = scope === 'all' ? ['all', ''] : (scope.split(':') as [string, string]);
  const now = ctx.now().toISOString();

  const softDelete = () =>
    writeBatch(ctx, [
      {
        sql: 'UPDATE tasks SET deleted_at = ?, updated_at = ?, updated_by = ? WHERE id = ? AND user_id = ?',
        args: [now, now, ctx.actor, id, ctx.userId],
      },
      ...auditStatements(ctx, 'deleted', { id, title }, null, scope),
      ...purgeStatements(ctx),
    ]);

  if (kind === 'all' || t.recur === 'none') {
    await softDelete();
    return;
  }
  if (kind === 'day') {
    if (!occursOn(t, arg)) throw unprocessable('The task does not occur on that day', 'not_on_date');
    await writeBatch(ctx, [
      {
        sql: `INSERT INTO task_days (task_id, user_id, date, status, note, completed_at, completed_on, updated_by, updated_at)
              VALUES (?, ?, ?, 'skipped', NULL, NULL, NULL, ?, ?)
              ON CONFLICT(task_id, date) DO UPDATE SET status = 'skipped', note = NULL, completed_at = NULL,
                completed_on = NULL, updated_by = excluded.updated_by, updated_at = excluded.updated_at`,
        args: [id, ctx.userId, arg, ctx.actor, now],
      },
      ...auditStatements(ctx, 'deleted', { id, title }, arg, scope),
    ]);
    return;
  }
  // from:D
  if (arg <= t.due_date) {
    await softDelete();
    return;
  }
  const end = addDays(arg, -1);
  if (t.recur_until != null && t.recur_until <= end) return; // already ended before D: nothing to do
  await writeBatch(ctx, [
    {
      sql: 'UPDATE tasks SET recur_until = ?, updated_at = ?, updated_by = ? WHERE id = ? AND user_id = ?',
      args: [end, now, ctx.actor, id, ctx.userId],
    },
    ...auditStatements(ctx, 'deleted', { id, title }, arg, scope),
  ]);
}

/** Undo a delete of a whole task. Idempotent (a live task is returned as is); 404 if unknown or past the 30-day window. */
export async function restoreTask(ctx: Ctx, id: string): Promise<TaskDto> {
  const rs = await ctx.db.execute({ sql: 'SELECT title, deleted_at FROM tasks WHERE id = ? AND user_id = ?', args: [id, ctx.userId] });
  if (rs.rows.length === 0) throw notFound('Task not found');
  const deletedAt = rs.rows[0].deleted_at;
  if (deletedAt == null) return getTask(ctx, id);
  if (Date.parse(String(deletedAt)) < ctx.now().getTime() - RESTORE_WINDOW_DAYS * 86_400_000) throw notFound('Task not found');
  await writeBatch(ctx, [
    {
      sql: 'UPDATE tasks SET deleted_at = NULL, updated_at = ?, updated_by = ? WHERE id = ? AND user_id = ?',
      args: [ctx.now().toISOString(), ctx.actor, id, ctx.userId],
    },
    ...auditStatements(ctx, 'restored', { id, title: String(rs.rows[0].title) }),
  ]);
  return getTask(ctx, id);
}

/**
 * Set the state of one task on one day (idempotent "set", never a toggle):
 * done (records when, and the user's local day it was ticked), skipped, or open (removes the record).
 * Replaying "done" keeps the original completion time, so alarm replays are harmless.
 */
export async function setDay(ctx: Ctx, id: string, date: string, input: DayPut): Promise<TaskDto> {
  const row = await getOwnedRow(ctx, id);
  const title = String(row.title);
  if (!occursOn(rowRecurring(row), date)) throw unprocessable('The task does not occur on that day', 'not_on_date');

  if (input.status === 'open') {
    await writeBatch(ctx, [
      { sql: 'DELETE FROM task_days WHERE task_id = ? AND date = ? AND user_id = ?', args: [id, date, ctx.userId] },
      ...auditStatements(ctx, 'updated', { id, title }, date, 'open'),
    ]);
    return getTask(ctx, id, date);
  }

  const now = ctx.now();
  const existing = await ctx.db.execute({
    sql: 'SELECT status, note, completed_at, completed_on FROM task_days WHERE task_id = ? AND date = ? AND user_id = ?',
    args: [id, date, ctx.userId],
  });
  const prev = existing.rows[0];
  const note = input.note !== undefined ? input.note : prev ? str(prev.note) : null;

  let completedAt: string | null = null;
  let completedOn: string | null = null;
  if (input.status === 'done') {
    if (prev && String(prev.status) === 'done') {
      completedAt = str(prev.completed_at);
      completedOn = str(prev.completed_on);
    } else {
      const at = input.completed_at ? new Date(input.completed_at) : now;
      // A replayed offline completion keeps its real time, but can't claim the future.
      if (at.getTime() > now.getTime() + 5 * 60_000) throw badRequest('completed_at cannot be in the future', 'invalid_time');
      completedAt = at.toISOString();
      completedOn = dateOf(at, ctx.tz);
    }
  }

  const unchanged = prev && String(prev.status) === input.status && input.note === undefined;
  await writeBatch(ctx, [
    {
      sql: `INSERT INTO task_days (task_id, user_id, date, status, note, completed_at, completed_on, updated_by, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(task_id, date) DO UPDATE SET status = excluded.status, note = excluded.note,
              completed_at = excluded.completed_at, completed_on = excluded.completed_on,
              updated_by = excluded.updated_by, updated_at = excluded.updated_at`,
      args: [id, ctx.userId, date, input.status, note, completedAt, completedOn, ctx.actor, now.toISOString()],
    },
    // A replayed "done" is not a new event worth logging
    ...(unchanged ? [] : auditStatements(ctx, input.status === 'done' ? 'completed' : 'updated', { id, title }, date, input.status === 'done' ? null : input.status)),
  ]);
  return getTask(ctx, id, date);
}

/** Move open one-off tasks to another day (the "move all overdue to today" action). Ineligible ids are reported, not failed. */
export async function moveTasks(ctx: Ctx, ids: string[], to: string): Promise<{ moved: string[]; skipped: string[] }> {
  const marks = ids.map(() => '?').join(', ');
  const rs = await ctx.db.execute({
    sql: `SELECT t.id, t.title, t.due_date FROM tasks t
          WHERE t.user_id = ? AND t.deleted_at IS NULL AND t.recur = 'none' AND t.id IN (${marks})
            AND NOT EXISTS (SELECT 1 FROM task_days td WHERE td.task_id = t.id AND td.date = t.due_date)`,
    args: [ctx.userId, ...ids],
  });
  const eligible = rs.rows.map((r) => ({ id: String(r.id), title: String(r.title), from: String(r.due_date) }));
  if (eligible.length > 0) {
    const eMarks = eligible.map(() => '?').join(', ');
    await writeBatch(ctx, [
      {
        sql: `UPDATE tasks SET due_date = ?, updated_at = ?, updated_by = ? WHERE user_id = ? AND id IN (${eMarks})`,
        args: [to, ctx.now().toISOString(), ctx.actor, ctx.userId, ...eligible.map((e) => e.id)],
      },
      ...eligible.flatMap((e) => auditStatements(ctx, 'rescheduled', { id: e.id, title: e.title }, to, `from ${e.from}`)),
    ]);
  }
  const movedIds = eligible.map((e) => e.id);
  return { moved: movedIds, skipped: ids.filter((i) => !movedIds.includes(i)) };
}

/** Today for this user. */
export const userToday = (ctx: Ctx) => todayFor(ctx.now(), ctx.tz);
