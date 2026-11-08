// Pure helpers for the Sheet tab (a spreadsheet view of all tasks). Calendar-day maths is done on 'YYYY-MM-DD' strings only.

import type { CellState, SheetColumn, SheetDay, SheetTask, SheetView } from '../services/sheet';
import { addMonths, monthStart } from './calendar';
import { fmtClock, fmtTimeBlock, repeatLabel, shiftDate, WEEKDAYS } from './format';

export type SheetFilter = 'all' | 'incomplete' | 'weekdays';

export const SHEET_FILTERS: readonly { id: SheetFilter; label: string }[] = [
  { id: 'all', label: 'All days' },
  { id: 'incomplete', label: 'Incomplete days' },
  { id: 'weekdays', label: 'Weekdays only' },
];

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'] as const;

// ── months ──────────────────────────────────────────────────────────────────────────────────────

/** First and last day of the month that contains `date`. */
export function monthRange(date: string): { from: string; to: string } {
  return { from: monthStart(date), to: shiftDate(addMonths(date, 1), -1) };
}

/** First day of the previous month. */
export const prevMonth = (date: string): string => addMonths(date, -1);

/** First day of the next month. */
export const nextMonth = (date: string): string => addMonths(date, 1);

/** API path for a month; `null` = the server's default window (the current month in the user's timezone). */
export function sheetPath(month: string | null): string {
  if (!month) return '/sheet';
  const { from, to } = monthRange(month);
  return `/sheet?from=${from}&to=${to}`;
}

// ── rows ────────────────────────────────────────────────────────────────────────────────────────

/** Keep the rows a filter asks for. "Incomplete" = something planned that is not done yet (skipped tasks are not planned). */
export function filterDays<T extends Pick<SheetDay, 'is_weekend' | 'planned' | 'done'>>(days: readonly T[], filter: SheetFilter): T[] {
  if (filter === 'weekdays') return days.filter((d) => !d.is_weekend);
  if (filter === 'incomplete') return days.filter((d) => d.planned > d.done);
  return [...days];
}

/** True when the month has neither a repeating task nor a one-off task. */
export const isEmptyMonth = (view: Pick<SheetView, 'columns' | 'days'>): boolean =>
  view.columns.length === 0 && view.days.every((d) => d.tasks.length === 0);

// ── cells ───────────────────────────────────────────────────────────────────────────────────────

/** What a tap on a cell or task sets: done <-> open, and a skipped one is reopened. Always an explicit state (the API is a set, not a toggle). */
export const nextStatus = (state: CellState): 'done' | 'open' => (state === 'open' ? 'done' : 'open');

/** A habit that is not scheduled on a day has no cell state at all, and so nothing to tap. */
export const isTogglable = (state: CellState | undefined): state is CellState => state === 'done' || state === 'open' || state === 'skipped';

const STATUS_WORD: Record<CellState, string> = { done: 'done', open: 'not done', skipped: 'skipped' };

/** "6 Nov" */
export const shortDate = (date: string): string => `${Number(date.slice(8, 10))} ${MONTHS[Number(date.slice(5, 7)) - 1]}`;

/** "Fri 6 Nov" */
export const dayName = (day: Pick<SheetDay, 'date' | 'weekday'>): string => `${WEEKDAYS[day.weekday - 1]} ${shortDate(day.date)}`;

/** Accessible name of a tick button: "Gym, Fri 6 Nov: not done". */
export const cellLabel = (title: string, day: Pick<SheetDay, 'date' | 'weekday'>, state: CellState): string =>
  `${title}, ${dayName(day)}: ${STATUS_WORD[state]}`;

/** Accessible name of a one-off task's chip: like cellLabel, with the start time after the title when it has one ("Call Bob at 9:00 AM, Fri 6 Nov: not done"). */
export const chipLabel = (t: Pick<SheetTask, 'title' | 'start_time'>, day: Pick<SheetDay, 'date' | 'weekday'>, state: CellState): string =>
  cellLabel(t.start_time ? `${t.title} at ${fmtClock(t.start_time)}` : t.title, day, state);

/** What a one-off task's chip says before its title: the start time ("9:00 AM"), or '' when it has none. */
export const startPrefix = (t: Pick<SheetTask, 'start_time'>): string => (t.start_time ? fmtClock(t.start_time) : '');

/**
 * Second header line of a habit column: "6:00 PM–7:00 PM · Mon Wed Fri" (either part is left out when it does not apply).
 * The time block (start and end, "from 6:00 PM" for a start alone, "by 7:00 PM" for an end alone) wins over the reminder time.
 */
export function habitMeta(c: Pick<SheetColumn, 'alarm_time' | 'start_time' | 'end_time' | 'recur_days'>): string {
  const when = fmtTimeBlock(c) || (c.alarm_time ? fmtClock(c.alarm_time) : '');
  return [when, repeatLabel({ recur: 'daily', recur_days: c.recur_days })].filter(Boolean).join(' · ');
}

// ── totals ──────────────────────────────────────────────────────────────────────────────────────

/** "50%", or an en dash when nothing is planned. */
export const pctText = (day: Pick<SheetDay, 'pct'>): string => (day.pct == null ? '–' : `${day.pct}%`);

/** A fully done day is shown inverted. */
export const isFullDay = (day: Pick<SheetDay, 'pct'>): boolean => day.pct === 100;

/** Days before today with something still not done get a bold %, never a colour. */
export const isMissedDay = (day: Pick<SheetDay, 'date' | 'planned' | 'done'>, today: string): boolean => day.date < today && day.planned > day.done;

/** Same counting rules as the server: skipped is not planned; pct is null when nothing is planned. */
export function dayTotals(cells: Record<string, CellState>, tasks: readonly SheetTask[]): Pick<SheetDay, 'planned' | 'done' | 'pct'> {
  const states = [...Object.values(cells), ...tasks.map((t) => t.status)];
  const planned = states.filter((s) => s !== 'skipped').length;
  const done = states.filter((s) => s === 'done').length;
  return { planned, done, pct: planned === 0 ? null : Math.round((done / planned) * 100) };
}

/** The view with one task's state on one day replaced, and that day's totals recomputed (an optimistic update). Other days are untouched. */
export function withStatus(view: SheetView, taskId: string, date: string, status: CellState): SheetView {
  return {
    ...view,
    days: view.days.map((d) => {
      if (d.date !== date) return d;
      const isCell = Object.hasOwn(d.cells, taskId);
      const isTask = d.tasks.some((t) => t.id === taskId);
      if (!isCell && !isTask) return d;
      const cells = isCell ? { ...d.cells, [taskId]: status } : d.cells;
      const tasks = isTask ? d.tasks.map((t) => (t.id === taskId ? { ...t, status } : t)) : d.tasks;
      return { ...d, cells, tasks, ...dayTotals(cells, tasks) };
    }),
  };
}
