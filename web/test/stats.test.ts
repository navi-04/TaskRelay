import { beforeEach, describe, expect, it } from 'vitest';
import type { Client } from '@libsql/client';
import { createTask, deleteTask, setDay } from '../lib/services/tasks';
import { dayStats, streak, weekSummary } from '../lib/services/stats';
import { addDays, dateOf, daysBetween, isValidDate } from '../lib/time';
import { ApiError } from '../lib/errors';
import { makeClock, makeDb, makeUser, task, type Clock, type TestUser } from './helpers';

let db: Client;
let clock: Clock;
let u: TestUser;

beforeEach(async () => {
  db = await makeDb();
  clock = makeClock('2026-11-06T12:00:00Z');
  u = await makeUser(db, clock);
});

/** Tick a task done "on" a given day by moving the clock there first. */
async function completeOn(id: string, date: string, when: string) {
  clock.set(when);
  await setDay(u.ctx(), id, date, { status: 'done' });
  clock.set('2026-11-06T12:00:00Z');
}

describe('dayStats', () => {
  it('counts planned, done, on-time and minutes per day, zero-filling empty days', async () => {
    const a = await createTask(u.ctx(), task({ title: 'a', due_date: '2026-11-04', duration_min: 30 }));
    await createTask(u.ctx(), task({ title: 'b', due_date: '2026-11-04', duration_min: 45 }));
    await completeOn(a.id, '2026-11-04', '2026-11-04T10:00:00Z');
    const days = await dayStats(u.ctx(), '2026-11-03', '2026-11-05');
    expect(days.map((d) => d.date)).toEqual(['2026-11-03', '2026-11-04', '2026-11-05']);
    expect(days[0]).toMatchObject({ planned: 0, done: 0 });
    expect(days[1]).toEqual({ date: '2026-11-04', planned: 2, done: 1, on_time: 1, planned_min: 75, done_min: 30 });
    expect(days[2]).toMatchObject({ planned: 0 });
  });

  it('separates late completions from on-time ones', async () => {
    const t = await createTask(u.ctx(), task({ title: 'late', due_date: '2026-11-04' }));
    await completeOn(t.id, '2026-11-04', '2026-11-06T09:00:00Z');
    const [d] = await dayStats(u.ctx(), '2026-11-04', '2026-11-04');
    expect(d).toMatchObject({ planned: 1, done: 1, on_time: 0 });
  });

  it('excludes skipped days from planned', async () => {
    const t = await createTask(u.ctx(), task({ title: 'd', due_date: '2026-11-01', recur: 'daily' }));
    await deleteTask(u.ctx(), t.id, 'day:2026-11-03');
    const days = await dayStats(u.ctx(), '2026-11-02', '2026-11-04');
    expect(days.map((d) => d.planned)).toEqual([1, 0, 1]);
  });

  it('rejects inverted and oversized ranges', async () => {
    await expect(dayStats(u.ctx(), '2026-11-05', '2026-11-01')).rejects.toBeInstanceOf(ApiError);
    await expect(dayStats(u.ctx(), '2026-01-01', '2026-12-31')).rejects.toMatchObject({ code: 'range_too_large' });
  });
});

describe('streak', () => {
  const TODAY = '2026-11-06';

  it('is 0 with no tasks', async () => {
    expect(await streak(u.ctx(), TODAY)).toBe(0);
  });

  it('counts consecutive clean days ending yesterday', async () => {
    for (const d of ['2026-11-04', '2026-11-05']) {
      const t = await createTask(u.ctx(), task({ title: d, due_date: d }));
      await completeOn(t.id, d, `${d}T10:00:00Z`);
    }
    expect(await streak(u.ctx(), TODAY)).toBe(2);
  });

  it('adds today only once today is clean', async () => {
    const y = await createTask(u.ctx(), task({ title: 'y', due_date: '2026-11-05' }));
    await completeOn(y.id, '2026-11-05', '2026-11-05T10:00:00Z');
    const t = await createTask(u.ctx(), task({ title: 't', due_date: TODAY }));
    expect(await streak(u.ctx(), TODAY)).toBe(1); // today pending: does not break it
    await completeOn(t.id, TODAY, `${TODAY}T10:00:00Z`);
    expect(await streak(u.ctx(), TODAY)).toBe(2);
  });

  it('breaks on a day with an unfinished task', async () => {
    const a = await createTask(u.ctx(), task({ title: 'a', due_date: '2026-11-03' }));
    await completeOn(a.id, '2026-11-03', '2026-11-03T10:00:00Z');
    await createTask(u.ctx(), task({ title: 'missed', due_date: '2026-11-04' }));
    const c = await createTask(u.ctx(), task({ title: 'c', due_date: '2026-11-05' }));
    await completeOn(c.id, '2026-11-05', '2026-11-05T10:00:00Z');
    expect(await streak(u.ctx(), TODAY)).toBe(1);
  });

  it('does not let a late completion repair an earlier day', async () => {
    const t = await createTask(u.ctx(), task({ title: 'late', due_date: '2026-11-05' }));
    await completeOn(t.id, '2026-11-05', '2026-11-06T08:00:00Z'); // ticked the next day
    expect(await streak(u.ctx(), TODAY)).toBe(0);
  });

  it('treats empty days as neutral', async () => {
    for (const d of ['2026-11-03', '2026-11-05']) {
      const t = await createTask(u.ctx(), task({ title: d, due_date: d }));
      await completeOn(t.id, d, `${d}T10:00:00Z`);
    }
    expect(await streak(u.ctx(), TODAY)).toBe(2); // 11-04 is empty
  });

  it('keeps counting across a month boundary', async () => {
    for (const d of ['2026-10-30', '2026-10-31', '2026-11-01']) {
      const t = await createTask(u.ctx(), task({ title: d, due_date: d }));
      await completeOn(t.id, d, `${d}T10:00:00Z`);
    }
    expect(await streak(u.ctx(), '2026-11-02')).toBe(3);
  });

  it('treats a skipped recurring day as neutral: it neither breaks nor adds to the streak', async () => {
    const t = await createTask(u.ctx(), task({ title: 'daily', due_date: '2026-11-01', recur: 'daily' }));
    for (const d of ['2026-11-01', '2026-11-02', '2026-11-04', '2026-11-05']) await completeOn(t.id, d, `${d}T10:00:00Z`);
    await deleteTask(u.ctx(), t.id, 'day:2026-11-03');
    expect(await streak(u.ctx(), TODAY)).toBe(4); // 01, 02, 04, 05 (03 is skipped)
  });
});

describe('weekSummary', () => {
  it('summarises the rolling 7 days ending today', async () => {
    const a = await createTask(u.ctx(), task({ title: 'a', due_date: '2026-11-05', duration_min: 60 }));
    await createTask(u.ctx(), task({ title: 'b', due_date: '2026-11-06', duration_min: 30 }));
    await createTask(u.ctx(), task({ title: 'old', due_date: '2026-10-20' }));
    await completeOn(a.id, '2026-11-05', '2026-11-05T10:00:00Z');
    const w = await weekSummary(u.ctx(), '2026-11-06');
    expect(w).toMatchObject({ from: '2026-10-31', to: '2026-11-06', planned: 2, done: 1, completion_pct: 50, planned_min: 90, done_min: 60, days_with_tasks: 2 });
  });
});

describe('time helpers', () => {
  it('derives the local day across timezones', () => {
    const i = new Date('2026-11-06T20:30:00Z');
    expect(dateOf(i, 'UTC')).toBe('2026-11-06');
    expect(dateOf(i, 'Asia/Kolkata')).toBe('2026-11-07');
    expect(dateOf(i, 'Pacific/Kiritimati')).toBe('2026-11-07'); // UTC+14
    expect(dateOf(i, 'Pacific/Pago_Pago')).toBe('2026-11-06'); // UTC-11
  });

  it('is correct on either side of a DST change', () => {
    // New York leaves DST at 06:00Z on 2026-11-01.
    expect(dateOf(new Date('2026-11-01T03:30:00Z'), 'America/New_York')).toBe('2026-10-31');
    expect(dateOf(new Date('2026-11-01T04:30:00Z'), 'America/New_York')).toBe('2026-11-01');
    expect(dateOf(new Date('2026-11-01T06:30:00Z'), 'America/New_York')).toBe('2026-11-01');
  });

  it('does date math on calendar days', () => {
    expect(addDays('2026-11-30', 1)).toBe('2026-12-01');
    expect(addDays('2026-12-31', 1)).toBe('2027-01-01');
    expect(addDays('2028-02-28', 1)).toBe('2028-02-29');
    expect(addDays('2027-02-28', 1)).toBe('2027-03-01');
    expect(addDays('2026-03-08', -1)).toBe('2026-03-07');
    expect(daysBetween('2026-11-01', '2026-11-06')).toBe(5);
  });

  it('rejects impossible dates', () => {
    expect(isValidDate('2026-02-30')).toBe(false);
    expect(isValidDate('2028-02-29')).toBe(true);
    expect(isValidDate('2027-02-29')).toBe(false);
    expect(isValidDate('1999-12-31')).toBe(false);
    expect(isValidDate('2026-1-5')).toBe(false);
  });
});
