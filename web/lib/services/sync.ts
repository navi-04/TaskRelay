import type { Ctx } from '../ctx';
import { addDays, todayFor } from '../time';
import { expandOccurrences, loadDayRows, loadTasksOverlapping } from './occurrences';
import { getSettings, type SettingsDto } from './settings';
import { countOverdue, listTasksForDate, summarize } from './tasks';

export const SYNC_DEFAULT_DAYS = 14;
export const SYNC_MAX_DAYS = 14;
const ALARM_CAP = 200;
const TODAY_TASKS_CAP = 25;
const TODAY_BLOCKS_CAP = 50;

/** Bump when the feed gains or changes fields: a phone holding an ETag from the old shape must refetch instead of getting a 304. */
const FEED_SHAPE = 2;

/** Changes only when something the phone can see changes (see data_version), the day rolls over, the window changes, or the feed shape does. */
export const syncEtag = (dataVersion: number, today: string, days: number) => `W/"${dataVersion}.${today}.${days}.${FEED_SHAPE}"`;

export interface SyncFeed {
  version: string;
  server_time: string;
  timezone: string;
  today: {
    date: string;
    planned: number;
    done: number;
    overdue_count: number;
    /** Titles of today's Top 3 in order. */
    top: string[];
    /** Up to 25 tasks, Top 3 first, for the home-screen widget. */
    tasks: Array<{ id: string; title: string; status: 'open' | 'done'; is_top: boolean; duration_min: number }>;
    /** Today's tasks that have a start time, earliest first (up to 50): the slots the app blocker keeps free of distractions. */
    blocks: Array<{ id: string; title: string; start_time: string; end_time: string | null; duration_min: number; status: 'open' | 'done' }>;
  };
  window: { from: string; to: string; /** Alarms after this date are not authoritative (the list was capped). */ covered_until: string; truncated: boolean };
  alarms: Array<{ task_id: string; date: string; time: string; title: string; kind: 'alarm' | 'notification'; duration_min: number }>;
  settings: SettingsDto;
}

/**
 * Everything the phone needs in ONE call: the upcoming alarm occurrences with recurrence already resolved
 * (open ones only; done/skipped/deleted are excluded), today's numbers for reminder text, and the reminder settings.
 * The server resolves recurrence so the phone never re-implements it.
 */
export async function buildSync(ctx: Ctx, days: number, version: string): Promise<SyncFeed> {
  const today = todayFor(ctx.now(), ctx.tz);
  const to = addDays(today, days - 1);

  const [alarmTasks, dayRows, settings, todayTasks, overdueCount] = await Promise.all([
    loadTasksOverlapping(ctx, today, to, true),
    loadDayRows(ctx, today, to),
    getSettings(ctx),
    listTasksForDate(ctx, today),
    countOverdue(ctx, today),
  ]);

  const open = expandOccurrences(alarmTasks, dayRows, today, to).filter((o) => o.status === 'open');
  const truncated = open.length > ALARM_CAP;
  const alarms = open.slice(0, ALARM_CAP).map((o) => ({
    task_id: o.task.id,
    date: o.date,
    time: o.task.alarm_time!,
    title: o.task.title,
    kind: o.task.reminder_kind,
    duration_min: o.task.duration_min,
  }));

  const top = todayTasks.filter((t) => t.top_position != null).sort((a, b) => a.top_position! - b.top_position!);
  const ordered = [...top, ...todayTasks.filter((t) => t.top_position == null)];
  const summary = summarize(todayTasks);

  return {
    version,
    server_time: ctx.now().toISOString(),
    timezone: ctx.tz,
    today: {
      date: today,
      planned: summary.planned,
      done: summary.done,
      overdue_count: overdueCount,
      top: top.map((t) => t.title),
      tasks: ordered.slice(0, TODAY_TASKS_CAP).map((t) => ({
        id: t.id,
        title: t.title,
        status: t.status === 'done' ? 'done' : 'open',
        is_top: t.top_position != null,
        duration_min: t.duration_min,
      })),
      blocks: todayTasks
        .filter((t) => t.start_time != null)
        .sort((a, b) => a.start_time!.localeCompare(b.start_time!) || a.id.localeCompare(b.id))
        .slice(0, TODAY_BLOCKS_CAP)
        .map((t) => ({
          id: t.id,
          title: t.title,
          start_time: t.start_time!,
          end_time: t.end_time,
          duration_min: t.duration_min,
          status: t.status === 'done' ? 'done' : 'open',
        })),
    },
    window: { from: today, to, covered_until: truncated ? alarms[alarms.length - 1].date : to, truncated },
    alarms,
    settings,
  };
}
