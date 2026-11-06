import type { InStatement, Row } from '@libsql/client';
import type { Ctx } from '../ctx';
import { badRequest, conflict, notFound, unprocessable } from '../errors';
import { addDays, dateOf, todayFor } from '../time';
import type { DayPut, TaskCreate, TaskPatch } from '../validation';
import { assertOwnedLabel } from './labels';

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
  created_at: string;
  updated_at: string;
  /** The calendar day this view of the task is for (recurring tasks occur on many days). */
  date: string;
  status: 'open' | 'done' | 'skipped';
  day_note: string | null;
  completed_at: string | null;
}

const COLS =
  't.id, t.title, t.notes, t.duration_min, t.type_id, t.priority_id, t.due_date, t.alarm_time, t.reminder_kind, t.recur, t.recur_until, t.created_at, t.updated_at';
const DAY_COLS = 'td.status AS day_status, td.note AS day_note, td.completed_at AS day_completed_at';

const str = (v: unknown): string | null => (v == null ? null : String(v));

function toDto(r: Row, date: string): TaskDto {
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
    created_at: String(r.created_at),
    updated_at: String(r.updated_at),
    date,
    status: (str(r.day_status) as 'done' | 'skipped' | null) ?? 'open',
    day_note: str(r.day_note),
    completed_at: str(r.day_completed_at),
  };
}

/** Does this task occur on `date`? The single definition of recurrence used by writes. (Reads use the same rule in SQL.) */
export function occursOn(t: { recur: string; due_date: string; recur_until: string | null }, date: string): boolean {
  if (t.recur === 'none') return t.due_date === date;
  return t.due_date <= date && (t.recur_until == null || date <= t.recur_until);
}

async function getOwnedRow(ctx: Ctx, id: string): Promise<Row> {
  const rs = await ctx.db.execute({
    sql: 'SELECT * FROM tasks WHERE id = ? AND user_id = ? AND deleted_at IS NULL',
    args: [id, ctx.userId],
  });
  if (rs.rows.length === 0) throw notFound('Task not found');
  return rs.rows[0];
}

const rowTask = (r: Row) => ({
  recur: String(r.recur),
  due_date: String(r.due_date),
  recur_until: str(r.recur_until),
});

// ───────────────────────────── reads ─────────────────────────────

/** The tasks that occur on `date`, recurrence resolved, done state for that day attached. Skipped days are hidden. */
export async function listTasksForDate(ctx: Ctx, date: string): Promise<TaskDto[]> {
  const rs = await ctx.db.execute({
    sql: `SELECT ${COLS}, ${DAY_COLS}
          FROM tasks t
          LEFT JOIN task_days td ON td.task_id = t.id AND td.date = :d
          LEFT JOIN labels p ON p.id = t.priority_id AND p.user_id = t.user_id
          WHERE t.user_id = :uid AND t.deleted_at IS NULL
            AND ( (t.recur = 'none' AND t.due_date = :d)
               OR (t.recur = 'daily' AND t.due_date <= :d AND (t.recur_until IS NULL OR t.recur_until >= :d)) )
            AND COALESCE(td.status, 'open') <> 'skipped'
          ORDER BY COALESCE(td.status = 'done', 0), (p.sort_order IS NULL), p.sort_order DESC,
                   (t.alarm_time IS NULL), t.alarm_time, t.created_at, t.id`,
    args: { d: date, uid: ctx.userId },
  });
  return rs.rows.map((r) => toDto(r, date));
}

const OVERDUE_LIMIT = 50;

/**
 * Overdue = one-off, not deleted, due before today, with no done/skipped record on its due date.
 * Recurring tasks are never overdue (a missed day is just missed). Nothing is rewritten: this is a query.
 */
export async function listOverdue(ctx: Ctx, today: string): Promise<{ items: TaskDto[]; count: number }> {
  const where = `t.user_id = :uid AND t.deleted_at IS NULL AND t.recur = 'none' AND t.due_date < :today
                 AND NOT EXISTS (SELECT 1 FROM task_days td WHERE td.task_id = t.id AND td.date = t.due_date)`;
  const [items, count] = await Promise.all([
    ctx.db.execute({
      sql: `SELECT ${COLS}, NULL AS day_status, NULL AS day_note, NULL AS day_completed_at
            FROM tasks t WHERE ${where} ORDER BY t.due_date DESC, t.created_at, t.id LIMIT ${OVERDUE_LIMIT}`,
      args: { uid: ctx.userId, today },
    }),
    ctx.db.execute({ sql: `SELECT COUNT(*) AS n FROM tasks t WHERE ${where}`, args: { uid: ctx.userId, today } }),
  ]);
  return { items: items.rows.map((r) => toDto(r, String(r.due_date))), count: Number(count.rows[0].n) };
}

export async function getTask(ctx: Ctx, id: string, date?: string): Promise<TaskDto> {
  const rs = await ctx.db.execute({
    sql: `SELECT ${COLS}, ${DAY_COLS}
          FROM tasks t
          LEFT JOIN task_days td ON td.task_id = t.id AND td.date = COALESCE(:d, t.due_date)
          WHERE t.id = :id AND t.user_id = :uid AND t.deleted_at IS NULL`,
    args: { d: date ?? null, id, uid: ctx.userId },
  });
  if (rs.rows.length === 0) throw notFound('Task not found');
  return toDto(rs.rows[0], date ?? String(rs.rows[0].due_date));
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

function assertRecurrence(recur: string, due: string, until: string | null) {
  if (recur === 'none' && until != null) {
    throw unprocessable('recur_until only applies to daily tasks', 'invalid_recurrence');
  }
  if (until != null && until < due) {
    throw unprocessable('recur_until cannot be before the start date', 'invalid_recurrence');
  }
}

/** Idempotent on `id`: creating the same id twice returns the first row; another user's id is a generic 409. */
export async function createTask(ctx: Ctx, input: TaskCreate): Promise<TaskDto> {
  const recurUntil = input.recur === 'none' ? null : (input.recur_until ?? null);
  assertRecurrence(input.recur, input.due_date, input.recur_until ?? null);
  await assertOwnedLabel(ctx, input.type_id, 'type');
  await assertOwnedLabel(ctx, input.priority_id, 'priority');

  const id = input.id ?? crypto.randomUUID();
  const now = ctx.now().toISOString();
  const rs = await ctx.db.execute({
    sql: `INSERT INTO tasks (id, user_id, title, notes, duration_min, type_id, priority_id, due_date, alarm_time,
                             reminder_kind, recur, recur_until, created_at, updated_at, updated_by)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(id) DO NOTHING`,
    args: [
      id, ctx.userId, input.title, input.notes ?? null, input.duration_min, input.type_id ?? null,
      input.priority_id ?? null, input.due_date, input.alarm_time ?? null, input.reminder_kind, input.recur,
      recurUntil, now, now, ctx.actor,
    ],
  });
  if (rs.rowsAffected === 0) {
    const existing = await ctx.db.execute({
      sql: 'SELECT id FROM tasks WHERE id = ? AND user_id = ? AND deleted_at IS NULL',
      args: [id, ctx.userId],
    });
    if (existing.rows.length === 0) throw conflict('That task id is already in use', 'id_in_use');
  }
  return getTask(ctx, id);
}

export async function updateTask(ctx: Ctx, id: string, patch: TaskPatch): Promise<TaskDto> {
  const old = await getOwnedRow(ctx, id);
  const merged = {
    recur: patch.recur ?? (String(old.recur) as 'none' | 'daily'),
    due_date: patch.due_date ?? String(old.due_date),
    recur_until: patch.recur_until !== undefined ? patch.recur_until : str(old.recur_until),
  };
  if (merged.recur === 'none') merged.recur_until = null;
  assertRecurrence(merged.recur, merged.due_date, merged.recur_until);
  if (patch.type_id !== undefined) await assertOwnedLabel(ctx, patch.type_id, 'type');
  if (patch.priority_id !== undefined) await assertOwnedLabel(ctx, patch.priority_id, 'priority');

  const statements: InStatement[] = [];
  const oldRecur = String(old.recur);
  const oldDue = String(old.due_date);

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
  sets.push('recur_until = ?');
  args.push(merged.recur_until);
  statements.push({ sql: `UPDATE tasks SET ${sets.join(', ')} WHERE id = ? AND user_id = ?`, args: [...args, id, ctx.userId] });

  await ctx.db.batch(statements, 'write');
  return getTask(ctx, id);
}

/**
 * scope: `all` | `day:D` | `from:D`. A one-off has one day, so any scope deletes it.
 * Recurring: `day:D` skips that day; `from:D` ends the series the day before D (or deletes it if D is its first day).
 * Deletes are soft (deleted_at).
 */
export async function deleteTask(ctx: Ctx, id: string, scope: string): Promise<void> {
  const row = await getOwnedRow(ctx, id);
  const t = rowTask(row);
  const [kind, arg] = scope === 'all' ? ['all', ''] : (scope.split(':') as [string, string]);
  const now = ctx.now().toISOString();

  const softDelete = () =>
    ctx.db.execute({
      sql: 'UPDATE tasks SET deleted_at = ?, updated_at = ?, updated_by = ? WHERE id = ? AND user_id = ?',
      args: [now, now, ctx.actor, id, ctx.userId],
    });

  if (kind === 'all' || t.recur === 'none') {
    await softDelete();
    return;
  }
  if (kind === 'day') {
    if (!occursOn(t, arg)) throw unprocessable('The task does not occur on that day', 'not_on_date');
    await ctx.db.execute({
      sql: `INSERT INTO task_days (task_id, user_id, date, status, note, completed_at, completed_on, updated_by, updated_at)
            VALUES (?, ?, ?, 'skipped', NULL, NULL, NULL, ?, ?)
            ON CONFLICT(task_id, date) DO UPDATE SET status = 'skipped', note = NULL, completed_at = NULL,
              completed_on = NULL, updated_by = excluded.updated_by, updated_at = excluded.updated_at`,
      args: [id, ctx.userId, arg, ctx.actor, now],
    });
    return;
  }
  // from:D
  if (arg <= t.due_date) {
    await softDelete();
    return;
  }
  const end = addDays(arg, -1);
  if (t.recur_until != null && t.recur_until <= end) return; // already ended before D: nothing to do
  await ctx.db.execute({
    sql: 'UPDATE tasks SET recur_until = ?, updated_at = ?, updated_by = ? WHERE id = ? AND user_id = ?',
    args: [end, now, ctx.actor, id, ctx.userId],
  });
}

/**
 * Set the state of one task on one day (idempotent "set", never a toggle):
 * done (records when, and the user's local day it was ticked), skipped, or open (removes the record).
 * Replaying "done" keeps the original completion time, so alarm replays are harmless.
 */
export async function setDay(ctx: Ctx, id: string, date: string, input: DayPut): Promise<TaskDto> {
  const row = await getOwnedRow(ctx, id);
  if (!occursOn(rowTask(row), date)) throw unprocessable('The task does not occur on that day', 'not_on_date');

  if (input.status === 'open') {
    await ctx.db.execute({ sql: 'DELETE FROM task_days WHERE task_id = ? AND date = ? AND user_id = ?', args: [id, date, ctx.userId] });
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

  await ctx.db.execute({
    sql: `INSERT INTO task_days (task_id, user_id, date, status, note, completed_at, completed_on, updated_by, updated_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(task_id, date) DO UPDATE SET status = excluded.status, note = excluded.note,
            completed_at = excluded.completed_at, completed_on = excluded.completed_on,
            updated_by = excluded.updated_by, updated_at = excluded.updated_at`,
    args: [id, ctx.userId, date, input.status, note, completedAt, completedOn, ctx.actor, now.toISOString()],
  });
  return getTask(ctx, id, date);
}

/** Move open one-off tasks to another day (the "move all overdue to today" action). Ineligible ids are reported, not failed. */
export async function moveTasks(ctx: Ctx, ids: string[], to: string): Promise<{ moved: string[]; skipped: string[] }> {
  const marks = ids.map(() => '?').join(', ');
  const rs = await ctx.db.execute({
    sql: `SELECT t.id FROM tasks t
          WHERE t.user_id = ? AND t.deleted_at IS NULL AND t.recur = 'none' AND t.id IN (${marks})
            AND NOT EXISTS (SELECT 1 FROM task_days td WHERE td.task_id = t.id AND td.date = t.due_date)`,
    args: [ctx.userId, ...ids],
  });
  const eligible = rs.rows.map((r) => String(r.id));
  if (eligible.length > 0) {
    const eMarks = eligible.map(() => '?').join(', ');
    await ctx.db.execute({
      sql: `UPDATE tasks SET due_date = ?, updated_at = ?, updated_by = ? WHERE user_id = ? AND id IN (${eMarks})`,
      args: [to, ctx.now().toISOString(), ctx.actor, ctx.userId, ...eligible],
    });
  }
  return { moved: eligible, skipped: ids.filter((i) => !eligible.includes(i)) };
}

/** Today for this user. */
export const userToday = (ctx: Ctx) => todayFor(ctx.now(), ctx.tz);
