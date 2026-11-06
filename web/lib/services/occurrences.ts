import type { Ctx } from '../ctx';
import { occursOn } from '../recurrence';
import { addDays } from '../time';

/** The columns needed to expand a task into the days it occurs on. */
export interface OccTask {
  id: string;
  title: string;
  alarm_time: string | null;
  reminder_kind: 'alarm' | 'notification';
  duration_min: number;
  priority_id: string | null;
  due_date: string;
  recur: string;
  recur_until: string | null;
  recur_days: number | null;
}

export interface DayRow {
  status: 'done' | 'skipped';
  completed_on: string | null;
  completed_at: string | null;
}

export interface Occurrence {
  task: OccTask;
  date: string;
  /** 'open' when the task has no task_days row for that day. */
  status: 'open' | 'done' | 'skipped';
  completed_on: string | null;
  completed_at: string | null;
}

/** Live tasks that can occur somewhere in [from, to] (one-offs due in range + repeating series overlapping it). */
export async function loadTasksOverlapping(ctx: Ctx, from: string, to: string, alarmOnly = false): Promise<OccTask[]> {
  const rs = await ctx.db.execute({
    sql: `SELECT id, title, alarm_time, reminder_kind, duration_min, priority_id, due_date, recur, recur_until, recur_days
          FROM tasks
          WHERE user_id = :uid AND deleted_at IS NULL ${alarmOnly ? 'AND alarm_time IS NOT NULL' : ''}
            AND ( (recur = 'none' AND due_date BETWEEN :from AND :to)
               OR (recur = 'daily' AND due_date <= :to AND (recur_until IS NULL OR recur_until >= :from)) )`,
    args: { uid: ctx.userId, from, to },
  });
  return rs.rows.map((r) => ({
    id: String(r.id),
    title: String(r.title),
    alarm_time: r.alarm_time == null ? null : String(r.alarm_time),
    reminder_kind: String(r.reminder_kind) as OccTask['reminder_kind'],
    duration_min: Number(r.duration_min),
    priority_id: r.priority_id == null ? null : String(r.priority_id),
    due_date: String(r.due_date),
    recur: String(r.recur),
    recur_until: r.recur_until == null ? null : String(r.recur_until),
    recur_days: r.recur_days == null ? null : Number(r.recur_days),
  }));
}

/** done/skipped rows in [from, to], keyed `${task_id}|${date}`. */
export async function loadDayRows(ctx: Ctx, from: string, to: string): Promise<Map<string, DayRow>> {
  const rs = await ctx.db.execute({
    sql: 'SELECT task_id, date, status, completed_on, completed_at FROM task_days WHERE user_id = ? AND date BETWEEN ? AND ?',
    args: [ctx.userId, from, to],
  });
  return new Map(
    rs.rows.map((r) => [
      `${r.task_id}|${r.date}`,
      {
        status: String(r.status) as DayRow['status'],
        completed_on: r.completed_on == null ? null : String(r.completed_on),
        completed_at: r.completed_at == null ? null : String(r.completed_at),
      },
    ]),
  );
}

/**
 * Expand tasks into (task, day) occurrences over [from, to] using the shared recurrence rule.
 * Returns every occurrence with its status (including skipped); callers filter. Sorted by date, then alarm time, then title.
 */
export function expandOccurrences(tasks: OccTask[], dayRows: Map<string, DayRow>, from: string, to: string): Occurrence[] {
  const out: Occurrence[] = [];
  for (let d = from; d <= to; d = addDays(d, 1)) {
    const day: Occurrence[] = [];
    for (const task of tasks) {
      if (!occursOn(task, d)) continue;
      const row = dayRows.get(`${task.id}|${d}`);
      day.push({ task, date: d, status: row?.status ?? 'open', completed_on: row?.completed_on ?? null, completed_at: row?.completed_at ?? null });
    }
    day.sort((a, b) => (a.task.alarm_time ?? '99:99').localeCompare(b.task.alarm_time ?? '99:99') || a.task.title.localeCompare(b.task.title) || a.task.id.localeCompare(b.task.id));
    out.push(...day);
  }
  return out;
}
