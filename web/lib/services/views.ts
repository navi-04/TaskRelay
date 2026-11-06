import type { Ctx } from '../ctx';
import { addDays, todayFor } from '../time';
import { getSettings } from './settings';
import { dayStats, streak, weekSummary } from './stats';
import { listOverdue, listTasksForDate, summarize, type TaskDto } from './tasks';

export interface DayView {
  date: string;
  /** The server's idea of today for this user (their timezone). */
  today: string;
  tasks: TaskDto[];
  summary: ReturnType<typeof summarize>;
  /** Only present when `date` is today. */
  overdue?: { items: TaskDto[]; count: number };
}

/** One day: its tasks, totals, and (for today) the overdue list. Used by the app, the web UI and the AI API. */
export async function dayView(ctx: Ctx, date: string): Promise<DayView> {
  const today = todayFor(ctx.now(), ctx.tz);
  const tasks = await listTasksForDate(ctx, date);
  const view: DayView = { date, today, tasks, summary: summarize(tasks) };
  if (date === today) view.overdue = await listOverdue(ctx, today);
  return view;
}

/** Calendar/insights data: per-day stats for a range plus streak and the rolling week. */
export async function statsView(ctx: Ctx, from?: string, to?: string) {
  const today = todayFor(ctx.now(), ctx.tz);
  const end = to ?? today;
  const start = from ?? addDays(end, -6);
  const [days, currentStreak, week] = await Promise.all([dayStats(ctx, start, end), streak(ctx, today), weekSummary(ctx, today)]);
  return { today, from: start, to: end, days, streak: currentStreak, week };
}

/** Everything the "how is my day going" question needs, in one read (the AI entry point and Today header). */
export async function overview(ctx: Ctx) {
  const today = todayFor(ctx.now(), ctx.tz);
  const [day, settings, currentStreak, week] = await Promise.all([
    dayView(ctx, today),
    getSettings(ctx),
    streak(ctx, today),
    weekSummary(ctx, today),
  ]);
  const used = settings.estimation_mode === 'time' ? day.summary.planned_min : day.summary.planned;
  const limit = settings.estimation_mode === 'time' ? settings.daily_time_limit_min : settings.daily_count_limit;
  return {
    today,
    timezone: ctx.tz,
    tasks: day.tasks,
    summary: day.summary,
    overdue: day.overdue,
    capacity: { mode: settings.estimation_mode, unit: settings.estimation_mode === 'time' ? 'minutes' : 'tasks', used, limit, over_limit: used > limit },
    streak: currentStreak,
    week,
  };
}
