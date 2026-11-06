import type { Ctx } from '../ctx';
import { maskToDays, occursOn, type Recurring } from '../recurrence';
import { addDays, todayFor } from '../time';

export type HabitState = 'done' | 'missed' | 'skipped' | 'none' | 'pending';

export interface HabitDto {
  task_id: string;
  title: string;
  recur_days: number[] | null;
  current_streak: number;
  /** Best run inside the requested window (not all time). */
  best_streak: number;
  /** Percent of counted occurrences done on the day, over the last 30 / 90 days of the window; null if none counted. */
  rate_30: number | null;
  rate_90: number | null;
  /** The last 7 days ending at `date`; `none` = the task does not occur that day (e.g. weekday not selected). */
  last7: Array<{ date: string; state: HabitState }>;
}

interface HabitRow {
  status: 'done' | 'skipped';
  completed_on: string | null;
}

/** State of a repeating task on one day. A late completion counts as missed, so streaks can't be repaired afterwards. */
export function habitState(task: Recurring, date: string, today: string, row: HabitRow | undefined): HabitState {
  if (!occursOn(task, date)) return 'none';
  if (row?.status === 'skipped') return 'skipped';
  if (row?.status === 'done') return row.completed_on == null || row.completed_on <= date ? 'done' : 'missed';
  return date >= today ? 'pending' : 'missed';
}

/**
 * Streaks over OCCURRING days only: skipped and still-pending days are neutral, a missed day (left open, or ticked late)
 * ends the current streak. `from`..`date` is the window; `date` is "today" for the purposes of pending.
 */
export function walkHabit(
  task: Recurring & { id: string; title: string },
  rows: Map<string, HabitRow>,
  from: string,
  date: string,
): Omit<HabitDto, 'task_id' | 'title' | 'recur_days'> {
  const states: Array<[string, HabitState]> = [];
  for (let d = from; d <= date; d = addDays(d, 1)) states.push([d, habitState(task, d, date, rows.get(d))]);

  let current = 0;
  for (let i = states.length - 1; i >= 0; i--) {
    const s = states[i][1];
    if (s === 'done') current++;
    else if (s === 'missed') break;
  }

  let best = 0;
  let run = 0;
  for (const [, s] of states) {
    if (s === 'done') best = Math.max(best, ++run);
    else if (s === 'missed') run = 0;
  }

  const rate = (n: number): number | null => {
    const slice = states.slice(-n);
    const hits = slice.filter(([, s]) => s === 'done').length;
    const counted = hits + slice.filter(([, s]) => s === 'missed').length;
    return counted === 0 ? null : Math.round((hits / counted) * 100);
  };

  const last7 = states.slice(-7).map(([d, state]) => ({ date: d, state }));
  return { current_streak: current, best_streak: best, rate_30: rate(30), rate_90: rate(90), last7 };
}

const MAX_HABITS = 100;

/** Every active repeating task (not ended before `date`) with its streaks and a 7-day strip: two queries, no per-task work. */
export async function listHabits(ctx: Ctx, date = todayFor(ctx.now(), ctx.tz), days = 90): Promise<{ date: string; habits: HabitDto[] }> {
  const from = addDays(date, -(days - 1));
  const tasks = await ctx.db.execute({
    sql: `SELECT id, title, due_date, recur, recur_until, recur_days FROM tasks
          WHERE user_id = :uid AND deleted_at IS NULL AND recur = 'daily'
            AND due_date <= :date AND (recur_until IS NULL OR recur_until >= :date)
          ORDER BY created_at, id LIMIT ${MAX_HABITS}`,
    args: { uid: ctx.userId, date },
  });
  if (tasks.rows.length === 0) return { date, habits: [] };

  const rows = await ctx.db.execute({
    sql: `SELECT task_id, date, status, completed_on FROM task_days
          WHERE user_id = :uid AND date BETWEEN :from AND :date
            AND task_id IN (SELECT id FROM tasks WHERE user_id = :uid AND deleted_at IS NULL AND recur = 'daily')`,
    args: { uid: ctx.userId, from, date },
  });
  const byTask = new Map<string, Map<string, HabitRow>>();
  for (const r of rows.rows) {
    const id = String(r.task_id);
    if (!byTask.has(id)) byTask.set(id, new Map());
    byTask.get(id)!.set(String(r.date), {
      status: String(r.status) as HabitRow['status'],
      completed_on: r.completed_on == null ? null : String(r.completed_on),
    });
  }

  const habits = tasks.rows.map((r): HabitDto => {
    const task = {
      id: String(r.id),
      title: String(r.title),
      recur: String(r.recur),
      due_date: String(r.due_date),
      recur_until: r.recur_until == null ? null : String(r.recur_until),
      recur_days: r.recur_days == null ? null : Number(r.recur_days),
    };
    const windowFrom = task.due_date > from ? task.due_date : from;
    return {
      task_id: task.id,
      title: task.title,
      recur_days: maskToDays(task.recur_days),
      // before the series started there is nothing to count, but the 7-day strip always spans 7 days
      ...walkHabit(task, byTask.get(task.id) ?? new Map(), windowFrom > addDays(date, -6) ? addDays(date, -6) : windowFrom, date),
    };
  });
  return { date, habits };
}
