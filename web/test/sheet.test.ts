import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import type { Client } from '@libsql/client';
import { migrate } from '../lib/migrate';

vi.stubEnv('TURSO_DATABASE_URL', ':memory:');

import * as register from '../app/api/v1/auth/register/route';
import * as sheetRoute from '../app/api/v1/sheet/route';
import * as taskRoute from '../app/api/v1/tasks/route';
import { getDb } from '../lib/db';
import { ApiError } from '../lib/errors';
import { MAX_SHEET_DAYS, sheetView } from '../lib/services/sheet';
import { dayStats } from '../lib/services/stats';
import { createTask, deleteTask, setDay } from '../lib/services/tasks';
import { addDays } from '../lib/time';
import { call, makeClock, makeDb, makeUser, task, type Clock, type TestUser } from './helpers';

let db: Client;
let clock: Clock;
let u: TestUser;

beforeAll(async () => {
  await migrate(await getDb());
});
afterEach(() => {
  vi.unstubAllEnvs();
  vi.stubEnv('TURSO_DATABASE_URL', ':memory:');
});
beforeEach(async () => {
  db = await makeDb();
  clock = makeClock('2026-11-06T12:00:00Z'); // a Friday
  u = await makeUser(db, clock);
});

const day = (view: Awaited<ReturnType<typeof sheetView>>, date: string) => view.days.find((d) => d.date === date)!;

describe('sheet: rows and columns', () => {
  it('has one row per calendar day, with weekday numbers, weekends and today marked', async () => {
    const v = await sheetView(u.ctx(), '2026-11-02', '2026-11-08');
    expect(v.days.map((d) => d.date)).toEqual(['2026-11-02', '2026-11-03', '2026-11-04', '2026-11-05', '2026-11-06', '2026-11-07', '2026-11-08']);
    expect(v.days.map((d) => d.weekday)).toEqual([1, 2, 3, 4, 5, 6, 7]);
    expect(v.days.map((d) => d.is_weekend)).toEqual([false, false, false, false, false, true, true]);
    expect(v.days.filter((d) => d.is_today).map((d) => d.date)).toEqual(['2026-11-06']);
    expect(v.today).toBe('2026-11-06');
    expect(day(v, '2026-11-03')).toMatchObject({ planned: 0, done: 0, pct: null, cells: {}, tasks: [], notes: [] });
  });

  it('defaults to the whole current month', async () => {
    const v = await sheetView(u.ctx());
    expect([v.from, v.to]).toEqual(['2026-11-01', '2026-11-30']);
    const dec = makeClock('2026-12-15T12:00:00Z');
    const w = await sheetView({ ...u.ctx(), now: dec.now });
    expect([w.from, w.to]).toEqual(['2026-12-01', '2026-12-31']);
  });

  it('makes a column per repeating task, in alarm-time order, and only those', async () => {
    await createTask(u.ctx(), task({ id: 'evening-habit-1', title: 'Skincare', due_date: '2026-11-01', recur: 'daily', alarm_time: '20:45' }));
    await createTask(u.ctx(), task({ id: 'morning-habit-1', title: 'Anki', due_date: '2026-11-01', recur: 'daily', alarm_time: '08:15' }));
    await createTask(u.ctx(), task({ id: 'plain-habit-0001', title: 'Stretch', due_date: '2026-11-01', recur: 'daily' }));
    await createTask(u.ctx(), task({ id: 'one-off-task-01', title: 'Pay rent', due_date: '2026-11-06' }));
    const v = await sheetView(u.ctx(), '2026-11-02', '2026-11-08');
    expect(v.columns.map((c) => c.title)).toEqual(['Anki', 'Skincare', 'Stretch']); // timed first, untimed last
    expect(v.columns[0]).toMatchObject({ task_id: 'morning-habit-1', alarm_time: '08:15', recur_days: null });
  });

  it('a weekday habit has cells only on its days; the cell states are done / open / skipped', async () => {
    await createTask(u.ctx(), task({ id: 'gym-habit-00001', title: 'Gym', due_date: '2026-11-02', recur: 'daily', recur_days: [1, 3, 5] }));
    await setDay(u.ctx(), 'gym-habit-00001', '2026-11-02', { status: 'done' });
    await setDay(u.ctx(), 'gym-habit-00001', '2026-11-04', { status: 'skipped' });
    const v = await sheetView(u.ctx(), '2026-11-02', '2026-11-08');
    expect(v.columns[0].recur_days).toEqual([1, 3, 5]);
    expect(v.days.map((d) => d.cells['gym-habit-00001'] ?? null)).toEqual(['done', null, 'skipped', null, 'open', null, null]);
  });

  it('a series appears only inside its own dates: not before it starts, not after it ends', async () => {
    await createTask(u.ctx(), task({ id: 'later-start-0001', title: 'Starts later', due_date: '2026-11-05', recur: 'daily' }));
    await createTask(u.ctx(), task({ id: 'ended-series-001', title: 'Ended', due_date: '2026-10-01', recur: 'daily', recur_until: '2026-11-03' }));
    await createTask(u.ctx(), task({ id: 'long-gone-00001', title: 'Long gone', due_date: '2026-09-01', recur: 'daily', recur_until: '2026-10-15' }));
    const v = await sheetView(u.ctx(), '2026-11-02', '2026-11-08');
    expect(v.columns.map((c) => c.title).sort()).toEqual(['Ended', 'Starts later']); // 'Long gone' ended before the window
    const has = (id: string) => v.days.filter((d) => id in d.cells).map((d) => d.date);
    expect(has('later-start-0001')).toEqual(['2026-11-05', '2026-11-06', '2026-11-07', '2026-11-08']);
    expect(has('ended-series-001')).toEqual(['2026-11-02', '2026-11-03']);
  });

  it('lists one-off tasks on their due date with their state', async () => {
    await createTask(u.ctx(), task({ id: 'one-off-task-01', title: 'Pay rent', due_date: '2026-11-06', duration_min: 20 }));
    await createTask(u.ctx(), task({ id: 'one-off-task-02', title: 'Call Bob', due_date: '2026-11-06', alarm_time: '09:00' }));
    await createTask(u.ctx(), task({ id: 'one-off-task-03', title: 'Next week', due_date: '2026-11-12' }));
    await setDay(u.ctx(), 'one-off-task-01', '2026-11-06', { status: 'done' });
    const v = await sheetView(u.ctx(), '2026-11-02', '2026-11-08');
    expect(day(v, '2026-11-06').tasks).toEqual([
      { id: 'one-off-task-02', title: 'Call Bob', status: 'open', duration_min: 30, alarm_time: '09:00', start_time: null, end_time: null }, // timed first
      { id: 'one-off-task-01', title: 'Pay rent', status: 'done', duration_min: 20, alarm_time: null, start_time: null, end_time: null },
    ]);
    expect(v.days.flatMap((d) => d.tasks).map((t) => t.id)).not.toContain('one-off-task-03'); // outside the window
  });

  it('never shows deleted tasks, and never another user’s', async () => {
    const gone = await createTask(u.ctx(), task({ title: 'Deleted', due_date: '2026-11-06' }));
    await deleteTask(u.ctx(), gone.id, 'all');
    await createTask(u.ctx(), task({ id: 'dead-habit-00001', title: 'Dead habit', due_date: '2026-11-01', recur: 'daily' }));
    await deleteTask(u.ctx(), 'dead-habit-00001', 'all');
    const other = await makeUser(db, clock);
    await createTask(other.ctx(), task({ id: 'their-one-off-01', title: 'Theirs', due_date: '2026-11-06' }));
    await createTask(other.ctx(), task({ id: 'their-habit-0001', title: 'Their habit', due_date: '2026-11-01', recur: 'daily' }));

    const v = await sheetView(u.ctx(), '2026-11-02', '2026-11-08');
    expect(v.columns).toEqual([]);
    expect(v.days.flatMap((d) => d.tasks)).toEqual([]);
    expect(day(v, '2026-11-06').planned).toBe(0);
  });

  it('collects the completion notes written that day', async () => {
    await createTask(u.ctx(), task({ id: 'one-off-task-01', title: 'Pay rent', due_date: '2026-11-06' }));
    await createTask(u.ctx(), task({ id: 'note-habit-0001', title: 'Anki', due_date: '2026-11-01', recur: 'daily' }));
    await setDay(u.ctx(), 'one-off-task-01', '2026-11-06', { status: 'done', note: 'Paid by card' });
    await setDay(u.ctx(), 'note-habit-0001', '2026-11-06', { status: 'done', note: 'Hard cards today' });
    await setDay(u.ctx(), 'note-habit-0001', '2026-11-05', { status: 'done' });
    const v = await sheetView(u.ctx(), '2026-11-02', '2026-11-08');
    expect(day(v, '2026-11-06').notes).toEqual(['Anki: Hard cards today', 'Pay rent: Paid by card']);
    expect(day(v, '2026-11-05').notes).toEqual([]);
  });
});

describe('sheet: totals agree with the Calendar', () => {
  it('Done / Total / % per day equal dayStats for every day (skips excluded, same counting rules)', async () => {
    await createTask(u.ctx(), task({ id: 'daily-habit-0001', title: 'Daily', due_date: '2026-10-20', recur: 'daily' }));
    await createTask(u.ctx(), task({ id: 'gym-habit-00001', title: 'Gym', due_date: '2026-10-20', recur: 'daily', recur_days: [1, 3, 5] }));
    await createTask(u.ctx(), task({ id: 'ending-habit-01', title: 'Ends', due_date: '2026-10-25', recur: 'daily', recur_until: '2026-11-04' }));
    for (const [i, d] of ['2026-11-02', '2026-11-03', '2026-11-04', '2026-11-05'].entries()) {
      await createTask(u.ctx(), task({ id: `one-off-day-0${i}`, title: `One ${i}`, due_date: d }));
    }
    for (const d of ['2026-11-01', '2026-11-02', '2026-11-04']) await setDay(u.ctx(), 'daily-habit-0001', d, { status: 'done' });
    await setDay(u.ctx(), 'daily-habit-0001', '2026-11-03', { status: 'skipped' });
    await setDay(u.ctx(), 'gym-habit-00001', '2026-11-02', { status: 'done' });
    await setDay(u.ctx(), 'one-off-day-01', '2026-11-03', { status: 'done' });
    await setDay(u.ctx(), 'one-off-day-02', '2026-11-04', { status: 'skipped' });
    clock.set('2026-11-09T09:00:00Z'); // a late tick: it still counts as done, exactly as in the Calendar
    await setDay(u.ctx(), 'ending-habit-01', '2026-11-02', { status: 'done' });
    clock.set('2026-11-06T12:00:00Z');

    const [v, stats] = await Promise.all([sheetView(u.ctx(), '2026-10-28', '2026-11-12'), dayStats(u.ctx(), '2026-10-28', '2026-11-12')]);
    expect(v.days.map((d) => d.date)).toEqual(stats.map((s) => s.date));
    for (const s of stats) {
      const d = day(v, s.date);
      expect({ date: d.date, planned: d.planned, done: d.done }).toEqual({ date: s.date, planned: s.planned, done: s.done });
      expect(d.pct).toBe(s.planned === 0 ? null : Math.round((s.done / s.planned) * 100));
    }
    expect(stats.some((s) => s.planned > 0 && s.done > 0)).toBe(true); // the scenario is not trivially empty
  });
});

describe('sheet: limits', () => {
  it('shows up to 92 days and rejects more, and rejects an inverted range', async () => {
    const last = addDays('2026-09-01', MAX_SHEET_DAYS - 1);
    expect((await sheetView(u.ctx(), '2026-09-01', last)).days).toHaveLength(MAX_SHEET_DAYS);
    await expect(sheetView(u.ctx(), '2026-09-01', addDays(last, 1))).rejects.toMatchObject({ status: 400, code: 'range_too_large' });
    await expect(sheetView(u.ctx(), '2026-11-08', '2026-11-02')).rejects.toBeInstanceOf(ApiError);
  });
});

describe('sheet over the API', () => {
  it('needs a session, returns the view for the caller only, and validates the range', async () => {
    expect((await call(sheetRoute.GET, 'GET', '/api/v1/sheet')).status).toBe(401);

    const a = await call(register.POST, 'POST', '/api/v1/auth/register', {
      body: { email: 'sheet-a@example.com', password: 'correct horse 9', timezone: 'UTC' },
      headers: { 'x-forwarded-for': '10.9.0.1' },
    });
    const b = await call(register.POST, 'POST', '/api/v1/auth/register', {
      body: { email: 'sheet-b@example.com', password: 'correct horse 9', timezone: 'UTC' },
      headers: { 'x-forwarded-for': '10.9.0.2' },
    });
    expect(a.status).toBe(201);
    const date = new Date().toISOString().slice(0, 10);
    const made = await call(taskRoute.POST, 'POST', '/api/v1/tasks', { token: a.body.token, body: { id: 'sheet-route-task1', title: 'Mine', due_date: date } });
    expect(made.status).toBe(201);

    const mine = await call(sheetRoute.GET, 'GET', `/api/v1/sheet?from=${date}&to=${date}`, { token: a.body.token });
    expect(mine.status).toBe(200);
    expect(mine.body.days).toHaveLength(1);
    expect(mine.body.days[0].tasks.map((t: { id: string }) => t.id)).toEqual(['sheet-route-task1']);
    const theirs = await call(sheetRoute.GET, 'GET', `/api/v1/sheet?from=${date}&to=${date}`, { token: b.body.token });
    expect(theirs.body.days[0].tasks).toEqual([]);

    expect((await call(sheetRoute.GET, 'GET', '/api/v1/sheet?from=2026-01-01&to=2026-12-31', { token: a.body.token })).status).toBe(400);
    expect((await call(sheetRoute.GET, 'GET', '/api/v1/sheet?from=not-a-date', { token: a.body.token })).status).toBe(400);
  });
});
