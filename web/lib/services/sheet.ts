import type { Ctx } from '../ctx';
import { badRequest } from '../errors';
import { maskToDays, occursOn, weekdayIndex } from '../recurrence';
import { addDays, daysBetween, todayFor } from '../time';

/** The spreadsheet view: one row per calendar day, one tick column per repeating task, the day's one-off tasks, and totals. */

export const MAX_SHEET_DAYS = 92;
const MAX_COLUMNS = 100;
const MAX_ONE_OFFS = 2000;

export type CellState = 'done' | 'open' | 'skipped';

export interface SheetColumn {
  task_id: string;
  title: string;
  duration_min: number;
  alarm_time: string | null;
  start_time: string | null;
  end_time: string | null;
  /** 1=Mon..7=Sun, or null = every day. */
  recur_days: number[] | null;
}

export interface SheetTask {
  id: string;
  title: string;
  status: CellState;
  duration_min: number;
  alarm_time: string | null;
  start_time: string | null;
  end_time: string | null;
}

export interface SheetDay {
  date: string;
  /** 1=Mon..7=Sun. */
  weekday: number;
  is_weekend: boolean;
  is_today: boolean;
  /** Only the repeating tasks that occur this day have a cell; a missing key means "not scheduled". */
  cells: Record<string, CellState>;
  /** One-off tasks due this day. */
  tasks: SheetTask[];
  /** Same rules as the Calendar: skipped days are not counted; any done task counts as done. */
  planned: number;
  done: number;
  pct: number | null;
  /** Completion notes written that day, as "Title: note". */
  notes: string[];
}

export interface SheetView {
  from: string;
  to: string;
  today: string;
  columns: SheetColumn[];
  days: SheetDay[];
}

interface DayRow {
  status: 'done' | 'skipped';
  note: string | null;
}

const stateOf = (row: DayRow | undefined): CellState => (row ? row.status : 'open');

/** Default window: the whole month that contains today. `to` alone is an error-free "up to"; a window is at most 92 days. */
function window(ctx: Ctx, from?: string, to?: string): { from: string; to: string; today: string } {
  const today = todayFor(ctx.now(), ctx.tz);
  const start = from ?? `${(to ?? today).slice(0, 7)}-01`;
  const end = to ?? (from ? addDays(from, 30) : addDays(`${addMonthStart(today)}`, -1));
  if (end < start) throw badRequest('"to" must not be before "from"', 'invalid_range');
  if (daysBetween(start, end) + 1 > MAX_SHEET_DAYS) throw badRequest(`A sheet shows at most ${MAX_SHEET_DAYS} days`, 'range_too_large');
  return { from: start, to: end, today };
}

/** First day of the month after `date`. */
function addMonthStart(date: string): string {
  const y = Number(date.slice(0, 4));
  const m = Number(date.slice(5, 7));
  return m === 12 ? `${y + 1}-01-01` : `${y}-${String(m + 1).padStart(2, '0')}-01`;
}

export async function sheetView(ctx: Ctx, from?: string, to?: string): Promise<SheetView> {
  const w = window(ctx, from, to);

  const cols = await ctx.db.execute({
    sql: `SELECT id, title, duration_min, alarm_time, start_time, end_time, due_date, recur, recur_until, recur_days FROM tasks
          WHERE user_id = :uid AND deleted_at IS NULL AND recur = 'daily'
            AND due_date <= :to AND (recur_until IS NULL OR recur_until >= :from)
          ORDER BY (COALESCE(start_time, alarm_time) IS NULL), COALESCE(start_time, alarm_time), created_at, id LIMIT ${MAX_COLUMNS}`,
    args: { uid: ctx.userId, from: w.from, to: w.to },
  });
  const oneOffs = await ctx.db.execute({
    sql: `SELECT id, title, duration_min, alarm_time, start_time, end_time, due_date FROM tasks
          WHERE user_id = :uid AND deleted_at IS NULL AND recur = 'none' AND due_date BETWEEN :from AND :to
          ORDER BY due_date, (COALESCE(start_time, alarm_time) IS NULL), COALESCE(start_time, alarm_time), created_at, id LIMIT ${MAX_ONE_OFFS}`,
    args: { uid: ctx.userId, from: w.from, to: w.to },
  });
  const marks = await ctx.db.execute({
    sql: `SELECT task_id, date, status, note FROM task_days
          WHERE user_id = :uid AND date BETWEEN :from AND :to
            AND task_id IN (SELECT id FROM tasks WHERE user_id = :uid AND deleted_at IS NULL)`,
    args: { uid: ctx.userId, from: w.from, to: w.to },
  });

  const rows = new Map<string, Map<string, DayRow>>(); // task id -> date -> row
  for (const r of marks.rows) {
    const id = String(r.task_id);
    if (!rows.has(id)) rows.set(id, new Map());
    rows.get(id)!.set(String(r.date), { status: String(r.status) as DayRow['status'], note: r.note == null ? null : String(r.note) });
  }

  const habits = cols.rows.map((r) => ({
    id: String(r.id),
    title: String(r.title),
    recur: String(r.recur),
    due_date: String(r.due_date),
    recur_until: r.recur_until == null ? null : String(r.recur_until),
    recur_days: r.recur_days == null ? null : Number(r.recur_days),
    duration_min: Number(r.duration_min),
    alarm_time: r.alarm_time == null ? null : String(r.alarm_time),
    start_time: r.start_time == null ? null : String(r.start_time),
    end_time: r.end_time == null ? null : String(r.end_time),
  }));
  const columns: SheetColumn[] = habits.map((h) => ({
    task_id: h.id,
    title: h.title,
    duration_min: h.duration_min,
    alarm_time: h.alarm_time,
    start_time: h.start_time,
    end_time: h.end_time,
    recur_days: maskToDays(h.recur_days),
  }));

  const byDate = new Map<string, SheetTask[]>();
  const titles = new Map<string, string>(habits.map((h) => [h.id, h.title]));
  const dueOf = new Map<string, string>();
  for (const r of oneOffs.rows) {
    const id = String(r.id);
    const date = String(r.due_date);
    titles.set(id, String(r.title));
    dueOf.set(id, date);
    const list = byDate.get(date) ?? [];
    list.push({
      id,
      title: String(r.title),
      status: stateOf(rows.get(id)?.get(date)),
      duration_min: Number(r.duration_min),
      alarm_time: r.alarm_time == null ? null : String(r.alarm_time),
      start_time: r.start_time == null ? null : String(r.start_time),
      end_time: r.end_time == null ? null : String(r.end_time),
    });
    byDate.set(date, list);
  }

  const days: SheetDay[] = [];
  for (let date = w.from; date <= w.to; date = addDays(date, 1)) {
    const weekday = weekdayIndex(date) + 1;
    const cells: Record<string, CellState> = {};
    for (const h of habits) {
      if (occursOn(h, date)) cells[h.id] = stateOf(rows.get(h.id)?.get(date));
    }
    const tasks = byDate.get(date) ?? [];
    const states = [...Object.values(cells), ...tasks.map((t) => t.status)];
    const planned = states.filter((s) => s !== 'skipped').length;
    const done = states.filter((s) => s === 'done').length;

    const notes: string[] = [];
    for (const [id, perDay] of rows) {
      const note = perDay.get(date)?.note;
      if (note && titles.has(id) && (id in cells || dueOf.get(id) === date)) notes.push(`${titles.get(id)}: ${note}`);
    }
    notes.sort();

    days.push({
      date,
      weekday,
      is_weekend: weekday >= 6,
      is_today: date === w.today,
      cells,
      tasks,
      planned,
      done,
      pct: planned === 0 ? null : Math.round((done / planned) * 100),
      notes,
    });
  }
  return { from: w.from, to: w.to, today: w.today, columns, days };
}
