import type { Ctx } from '../ctx';
import { badRequest } from '../errors';
import { occursSql } from '../recurrence';
import { addDays, daysBetween, todayFor } from '../time';

export interface DayStat {
  date: string;
  /** Tasks that occur that day (skipped days excluded). */
  planned: number;
  /** Tasks marked done for that day, whenever they were ticked. */
  done: number;
  /** Done on or before that day (completed_on <= date); late completions don't count. */
  on_time: number;
  planned_min: number;
  done_min: number;
}

export const MAX_RANGE_DAYS = 62;
const STREAK_LOOKBACK_DAYS = 400;
/** The streak walk fetches this many days per query and stops at the first break. */
const STREAK_CHUNK_DAYS = 62;

/**
 * Per-day totals for [from, to], one row per calendar day (zeros for empty days).
 * This is the only place stats are computed; Calendar, Insights, the Today header and the AI overview use it.
 */
async function rangeStats(ctx: Ctx, from: string, to: string): Promise<DayStat[]> {
  const rs = await ctx.db.execute({
    sql: `WITH RECURSIVE days(d) AS (
            SELECT :from UNION ALL SELECT date(d, '+1 day') FROM days WHERE d < :to
          ),
          planned AS (
            SELECT days.d AS d, t.duration_min AS dur, td.status AS st, td.completed_on AS co
            FROM days
            JOIN tasks t ON t.user_id = :uid AND t.deleted_at IS NULL
              AND ${occursSql('t', 'days.d')}
            LEFT JOIN task_days td ON td.task_id = t.id AND td.date = days.d
            WHERE COALESCE(td.status, 'open') <> 'skipped'
          )
          SELECT d,
                 COUNT(*) AS planned,
                 COALESCE(SUM(st = 'done'), 0) AS done,
                 COALESCE(SUM(st = 'done' AND co <= d), 0) AS on_time,
                 COALESCE(SUM(dur), 0) AS planned_min,
                 COALESCE(SUM(CASE WHEN st = 'done' THEN dur END), 0) AS done_min
          FROM planned GROUP BY d ORDER BY d`,
    args: { from, to, uid: ctx.userId },
  });
  const byDate = new Map<string, DayStat>();
  for (const r of rs.rows) {
    byDate.set(String(r.d), {
      date: String(r.d),
      planned: Number(r.planned),
      done: Number(r.done),
      on_time: Number(r.on_time),
      planned_min: Number(r.planned_min),
      done_min: Number(r.done_min),
    });
  }
  const out: DayStat[] = [];
  for (let d = from; d <= to; d = addDays(d, 1)) {
    out.push(byDate.get(d) ?? { date: d, planned: 0, done: 0, on_time: 0, planned_min: 0, done_min: 0 });
  }
  return out;
}

export async function dayStats(ctx: Ctx, from: string, to: string): Promise<DayStat[]> {
  if (to < from) throw badRequest('`to` cannot be before `from`', 'invalid_range');
  if (daysBetween(from, to) + 1 > MAX_RANGE_DAYS) throw badRequest(`Range is limited to ${MAX_RANGE_DAYS} days`, 'range_too_large');
  return rangeStats(ctx, from, to);
}

/**
 * Consecutive clean days ending yesterday, plus today if it is already clean.
 * clean = planned > 0 and every task done on or before its day; empty days are neutral;
 * a day with unfinished/late tasks breaks the streak; today never breaks it while in progress.
 */
export async function streak(ctx: Ctx, today = todayFor(ctx.now(), ctx.tz)): Promise<number> {
  // Nothing can be planned before the user's earliest task, so never look further back than that.
  const first = await ctx.db.execute({
    sql: 'SELECT MIN(due_date) AS first FROM tasks WHERE user_id = ? AND deleted_at IS NULL',
    args: [ctx.userId],
  });
  if (first.rows[0].first == null) return 0;
  const earliest = String(first.rows[0].first);
  const floor = earliest > addDays(today, -STREAK_LOOKBACK_DAYS) ? earliest : addDays(today, -STREAK_LOOKBACK_DAYS);

  let count = 0;
  let end = today;
  while (end >= floor) {
    const start = addDays(end, -(STREAK_CHUNK_DAYS - 1)) > floor ? addDays(end, -(STREAK_CHUNK_DAYS - 1)) : floor;
    const days = await rangeStats(ctx, start, end);
    for (let i = days.length - 1; i >= 0; i--) {
      const d = days[i];
      if (d.date === today) {
        if (d.planned > 0 && d.on_time === d.planned) count++; // clean today counts; in-progress today never breaks
        continue;
      }
      if (d.planned === 0) continue;
      if (d.on_time === d.planned) count++;
      else return count;
    }
    end = addDays(start, -1);
  }
  return count;
}

/** Rolling 7 days ending today. */
export async function weekSummary(ctx: Ctx, today = todayFor(ctx.now(), ctx.tz)) {
  const from = addDays(today, -6);
  const days = await rangeStats(ctx, from, today);
  const planned = days.reduce((s, d) => s + d.planned, 0);
  const done = days.reduce((s, d) => s + d.done, 0);
  const daysWithTasks = days.filter((d) => d.planned > 0).length;
  const plannedMin = days.reduce((s, d) => s + d.planned_min, 0);
  return {
    from,
    to: today,
    planned,
    done,
    completion_pct: planned === 0 ? 0 : Math.round((done / planned) * 100),
    planned_min: plannedMin,
    done_min: days.reduce((s, d) => s + d.done_min, 0),
    days_with_tasks: daysWithTasks,
    avg_daily_planned_min: daysWithTasks === 0 ? 0 : Math.round(plannedMin / daysWithTasks),
  };
}
