// Contract fixtures: real output of the real services with a fixed clock and fixed ids, saved as JSON.
// The Flutter app parses these files in its tests, so the API contract is checked on both sides.
//   npm test                         -> fails if the API output no longer matches the saved fixtures
//   UPDATE_FIXTURES=1 npm test       -> rewrites them (review the diff: it IS the API change)
import { describe, expect, it } from 'vitest';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { ApiError } from '../lib/errors';
import { errorResponse } from '../lib/http';
import { daysToMask, maskToDays, occursOn } from '../lib/recurrence';
import { listActivity } from '../lib/services/activity';
import { setTop } from '../lib/services/focus';
import { listHabits } from '../lib/services/habits';
import { listLabels } from '../lib/services/labels';
import { weeklyReview } from '../lib/services/review';
import { searchTasks } from '../lib/services/search';
import { sheetView } from '../lib/services/sheet';
import { getSettings } from '../lib/services/settings';
import { buildSync } from '../lib/services/sync';
import { createTask, setDay, updateTask } from '../lib/services/tasks';
import { dayView, statsView } from '../lib/services/views';
import { addDays } from '../lib/time';
import { taskCreate } from '../lib/validation';
import { makeClock, makeDb, makeUser, task } from './helpers';

const DIR = path.join(process.cwd(), 'test', 'fixtures');
const UPDATE = process.env.UPDATE_FIXTURES === '1';
const BASE = '2026-11-06T12:00:00Z'; // a Friday

async function errorShapes() {
  const body = async (e: unknown) => (await errorResponse(e).json()) as unknown;
  const invalid = taskCreate.safeParse({});
  return {
    unauthorized: await body(new ApiError(401, 'unauthorized', 'Not signed in')),
    not_found: await body(new ApiError(404, 'not_found', 'Task not found')),
    conflict: await body(new ApiError(409, 'id_in_use', 'That task id is already in use')),
    unprocessable: await body(new ApiError(422, 'not_on_date', 'The task does not occur on that day')),
    upgrade_required: await body(new ApiError(426, 'upgrade_required', 'Please update TaskRelay to continue')),
    rate_limited: await body(new ApiError(429, 'rate_limited', 'Too many attempts. Try again in 15 min.')),
    validation_error: await body(invalid.success ? null : invalid.error),
  };
}

/** Golden table for the Dart `occursOn`: every row is also checked against the SQL by the differential test. */
function recurrenceCases() {
  const rows: Array<{ name: string; recur: string; due_date: string; recur_until: string | null; recur_days: number[] | null; from: string; to: string }> = [
    { name: 'one-off', recur: 'none', due_date: '2026-11-10', recur_until: null, recur_days: null, from: '2026-11-08', to: '2026-11-12' },
    { name: 'every day from a start date', recur: 'daily', due_date: '2026-11-10', recur_until: null, recur_days: null, from: '2026-11-08', to: '2026-11-14' },
    { name: 'until is inclusive', recur: 'daily', due_date: '2026-11-10', recur_until: '2026-11-12', recur_days: null, from: '2026-11-09', to: '2026-11-14' },
    { name: 'Mon/Wed/Fri', recur: 'daily', due_date: '2026-11-02', recur_until: null, recur_days: [1, 3, 5], from: '2026-11-02', to: '2026-11-15' },
    { name: 'start date outside the weekdays', recur: 'daily', due_date: '2026-11-07', recur_until: null, recur_days: [1], from: '2026-11-07', to: '2026-11-16' },
    { name: 'weekends with an end date', recur: 'daily', due_date: '2026-11-01', recur_until: '2026-11-22', recur_days: [6, 7], from: '2026-11-01', to: '2026-11-30' },
    { name: 'across a year boundary', recur: 'daily', due_date: '2026-12-28', recur_until: null, recur_days: [2, 4], from: '2026-12-28', to: '2027-01-12' },
    { name: 'across a leap day', recur: 'daily', due_date: '2028-02-26', recur_until: null, recur_days: [2, 3], from: '2028-02-26', to: '2028-03-06' },
  ];
  return rows.map((r) => {
    const t = { recur: r.recur, due_date: r.due_date, recur_until: r.recur_until, recur_days: daysToMask(r.recur_days) };
    const occurs: string[] = [];
    for (let d = r.from; d <= r.to; d = addDays(d, 1)) if (occursOn(t, d)) occurs.push(d);
    expect(maskToDays(t.recur_days)).toEqual(r.recur_days); // the API form round-trips
    return { ...r, occurs };
  });
}

async function buildFixtures(): Promise<Record<string, unknown>> {
  const db = await makeDb();
  const clock = makeClock(BASE);
  const u = await makeUser(db, clock, { email: 'fixture@example.com' });
  const ctx = u.ctx();
  const ai = u.ctx('ai');
  const labels = await listLabels(ctx);
  const high = labels.priorities.find((p) => p.label === 'High')!.id;
  const medium = labels.priorities.find((p) => p.label === 'Medium')!.id;
  const bug = labels.types.find((t) => t.label === 'Bug')!.id;

  const at = async (iso: string, fn: () => Promise<unknown>) => {
    clock.set(iso);
    await fn();
    clock.set(BASE);
  };

  await createTask(ctx, task({ id: 'fx-task-standup', title: 'Team standup', due_date: '2026-11-06', alarm_time: '09:30', start_time: '09:30', end_time: '09:45', priority_id: high }));
  await createTask(ctx, task({ id: 'fx-task-report', title: 'Write quarterly report', notes: 'Include the Q3 numbers', due_date: '2026-11-06', duration_min: 90, start_time: '14:00' }));
  await createTask(ctx, task({ id: 'fx-task-gym', title: 'Gym', due_date: '2026-10-26', alarm_time: '17:45', start_time: '18:00', end_time: '19:00', reminder_kind: 'notification', recur: 'daily', recur_days: [1, 3, 5], priority_id: medium }));
  await createTask(ctx, task({ id: 'fx-task-meditate', title: 'Meditate', due_date: '2026-10-30', duration_min: 10, recur: 'daily' }));
  await createTask(ctx, task({ id: 'fx-task-old', title: 'Renew passport', due_date: '2026-11-01', duration_min: 45 }));
  await at('2026-11-06T04:10:00Z', () => setDay(ctx, 'fx-task-standup', '2026-11-06', { status: 'done', note: 'Short one' }));
  for (const d of ['2026-10-26', '2026-10-28']) await at(`${d}T19:00:00Z`, () => setDay(ctx, 'fx-task-gym', d, { status: 'done' }));
  for (const d of ['2026-10-31', '2026-11-01', '2026-11-02', '2026-11-04', '2026-11-05']) await at(`${d}T07:00:00Z`, () => setDay(ctx, 'fx-task-meditate', d, { status: 'done' }));
  await at('2026-11-04T07:30:00Z', () => setDay(ctx, 'fx-task-gym', '2026-11-04', { status: 'done' }));
  await setTop(ctx, '2026-11-06', ['fx-task-standup', 'fx-task-gym']);

  await createTask(ai, task({ id: 'fx-task-ai', title: 'Fix login bug', due_date: '2026-11-07', duration_min: 30, type_id: bug, priority_id: high }));
  await updateTask(ai, 'fx-task-ai', { duration_min: 45 });

  const out: Record<string, unknown> = {
    labels,
    settings: await getSettings(ctx),
    'day-view': await dayView(ctx, '2026-11-06'),
    stats: await statsView(ctx, '2026-10-31', '2026-11-06'),
    sync: await buildSync(ctx, 14, 'W/"fixture"'),
    habits: await listHabits(ctx, '2026-11-06', 30),
    sheet: await sheetView(ctx, '2026-11-02', '2026-11-08'), // Mon..Sun
    review: await weeklyReview(ctx),
    activity: await listActivity(ctx),
    search: await searchTasks(ctx, 'report'),
    errors: await errorShapes(),
    'recurrence-cases': recurrenceCases(),
  };

  // Seeded label ids and the user id are random per run: replace them with stable placeholders.
  let text = JSON.stringify(out);
  labels.types.forEach((l, i) => (text = text.split(l.id).join(`label-type-${i + 1}`)));
  labels.priorities.forEach((l, i) => (text = text.split(l.id).join(`label-priority-${i + 1}`)));
  text = text.split(u.id).join('user-1');
  return JSON.parse(text);
}

describe('contract fixtures', () => {
  it('match what the API produces (UPDATE_FIXTURES=1 rewrites them)', async () => {
    const all = await buildFixtures();
    if (UPDATE) mkdirSync(DIR, { recursive: true });
    for (const [name, value] of Object.entries(all)) {
      const file = path.join(DIR, `${name}.json`);
      if (UPDATE) {
        writeFileSync(file, JSON.stringify(value, null, 2) + '\n');
        continue;
      }
      expect(existsSync(file), `missing fixture ${name}.json - run: UPDATE_FIXTURES=1 npm test`).toBe(true);
      expect(JSON.parse(readFileSync(file, 'utf8')), `${name}.json is out of date - run: UPDATE_FIXTURES=1 npm test`).toEqual(value);
    }
  });

  it('are deterministic: two builds are identical', async () => {
    expect(await buildFixtures()).toEqual(await buildFixtures());
  });

  it('the fixture data actually exercises the contract (not trivially empty)', async () => {
    const all = (await buildFixtures()) as Record<string, any>;
    expect(all['day-view'].tasks.length).toBeGreaterThanOrEqual(3);
    expect(all['day-view'].top).toEqual(['fx-task-standup', 'fx-task-gym']);
    expect(all['day-view'].overdue.count).toBe(1);
    expect(all.sync.alarms.length).toBeGreaterThan(3);
    expect(all.sync.today.blocks.map((b: { id: string }) => b.id)).toEqual(['fx-task-standup', 'fx-task-report', 'fx-task-gym']); // 09:30, 14:00, 18:00
    expect(all.sync.today.blocks.map((b: { end_time: string | null }) => b.end_time)).toEqual(['09:45', null, '19:00']);
    expect(all['day-view'].tasks.some((t: { start_time: string | null }) => t.start_time === '14:00')).toBe(true);
    expect(all.sheet.columns.some((c: { start_time: string | null }) => c.start_time === '18:00')).toBe(true);
    expect(all.habits.habits.length).toBe(2);
    expect(all.sheet.columns.length).toBe(2);
    expect(all.sheet.days.length).toBe(7);
    expect(all.sheet.days.some((d: { tasks: unknown[] }) => d.tasks.length > 0)).toBe(true);
    expect(all.review.totals.planned).toBeGreaterThan(5);
    expect(all.activity.items.map((i: { kind: string }) => i.kind)).toEqual(['updated', 'created']);
    expect(all['recurrence-cases'].every((c: { occurs: string[] }) => c.occurs.length > 0)).toBe(true);
  });
});
