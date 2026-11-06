import { beforeEach, describe, expect, it } from 'vitest';
import type { Client } from '@libsql/client';
import { daysToMask, firstOccurrence, maskToDays, occursOn, type Recurring, weekdayIndex } from '../lib/recurrence';
import { listTasksForDate } from '../lib/services/tasks';
import { dayStats } from '../lib/services/stats';
import { addDays } from '../lib/time';
import { makeClock, makeDb, makeUser, type Clock, type TestUser } from './helpers';

const MON = 1, TUE = 2, WED = 3, THU = 4, FRI = 5, SAT = 6, SUN = 7;
const weekly = (due: string, days: number[], until: string | null = null): Recurring => ({
  recur: 'daily',
  due_date: due,
  recur_until: until,
  recur_days: daysToMask(days),
});

describe('weekday masks', () => {
  it('round-trips every non-empty proper subset of weekdays', () => {
    for (let mask = 1; mask <= 126; mask++) {
      const days = maskToDays(mask)!;
      expect(days.every((d, i) => d >= 1 && d <= 7 && (i === 0 || d > days[i - 1]))).toBe(true);
      expect(daysToMask(days)).toBe(mask);
    }
  });

  it('treats null, empty and "all seven days" as every day', () => {
    expect(daysToMask(null)).toBeNull();
    expect(daysToMask(undefined)).toBeNull();
    expect(daysToMask([])).toBeNull();
    expect(daysToMask([1, 2, 3, 4, 5, 6, 7])).toBeNull();
    expect(maskToDays(null)).toBeNull();
  });

  it('maps Mon=1 .. Sun=7 regardless of input order', () => {
    expect(daysToMask([MON, WED, FRI])).toBe(0b0010101);
    expect(daysToMask([FRI, MON, WED])).toBe(0b0010101);
    expect(maskToDays(0b1100000)).toEqual([SAT, SUN]);
  });
});

describe('weekdayIndex (Monday-based, on calendar dates only)', () => {
  it('is correct across month, year and leap-day boundaries', () => {
    expect(weekdayIndex('2026-11-02')).toBe(0); // Monday
    expect(weekdayIndex('2026-11-06')).toBe(4); // Friday
    expect(weekdayIndex('2026-11-08')).toBe(6); // Sunday
    expect(weekdayIndex('2026-12-31')).toBe(3); // Thursday
    expect(weekdayIndex('2027-01-01')).toBe(4); // Friday
    expect(weekdayIndex('2028-02-29')).toBe(1); // Tuesday (leap day)
    expect(weekdayIndex('2028-03-01')).toBe(2);
  });
});

describe('occursOn', () => {
  it('one-offs occur only on their due date', () => {
    const t: Recurring = { recur: 'none', due_date: '2026-11-10', recur_until: null, recur_days: null };
    expect(occursOn(t, '2026-11-10')).toBe(true);
    expect(occursOn(t, '2026-11-09')).toBe(false);
    expect(occursOn(t, '2026-11-11')).toBe(false);
  });

  it('weekday repeats follow the mask, start at due_date, and treat recur_until as inclusive', () => {
    const t = weekly('2026-11-02', [MON, WED, FRI], '2026-11-13');
    const days = ['02', '03', '04', '05', '06', '07', '08', '09', '10', '11', '12', '13', '14'].map((d) => `2026-11-${d}`);
    expect(days.filter((d) => occursOn(t, d))).toEqual(['2026-11-02', '2026-11-04', '2026-11-06', '2026-11-09', '2026-11-11', '2026-11-13']);
    expect(occursOn(t, '2026-10-30')).toBe(false); // a Friday before the start
  });

  it('a start date outside the mask is a lower bound, not an occurrence', () => {
    const t = weekly('2026-11-07', [MON]); // starts on a Saturday
    expect(occursOn(t, '2026-11-07')).toBe(false);
    expect(occursOn(t, '2026-11-09')).toBe(true);
    expect(firstOccurrence(t)).toBe('2026-11-09');
  });

  it('firstOccurrence is null when the series ends before its first matching weekday', () => {
    expect(firstOccurrence(weekly('2026-11-07', [MON], '2026-11-08'))).toBeNull();
    expect(firstOccurrence(weekly('2026-11-07', [SAT, SUN]))).toBe('2026-11-07');
  });

  it('works across year and leap-day boundaries', () => {
    const t = weekly('2027-12-27', [TUE, THU]);
    expect(['2027-12-28', '2027-12-30', '2028-01-04', '2028-02-29', '2028-03-02'].map((d) => occursOn(t, d))).toEqual([true, true, true, true, true]);
    expect(occursOn(t, '2028-03-01')).toBe(false); // a Wednesday
  });
});

// ── The SQL used by reads and the TS used by writes must be the same rule ──────────────────────────

function prng(seed: number) {
  // mulberry32: deterministic, so a failure is reproducible
  return () => {
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

describe('SQL and TS agree (differential test)', () => {
  let db: Client;
  let clock: Clock;
  let u: TestUser;

  beforeEach(async () => {
    db = await makeDb();
    clock = makeClock('2026-11-06T12:00:00Z');
    u = await makeUser(db, clock);
  });

  it('lists and counts exactly the tasks occursOn says occur, for 25 random tasks over 300 days', async () => {
    const rand = prng(20261106);
    const int = (lo: number, hi: number) => lo + Math.floor(rand() * (hi - lo + 1));
    const START = '2026-01-01';
    const DAYS = 300;
    const now = clock.now().toISOString();

    interface Row extends Recurring {
      id: string;
      deleted: boolean;
    }
    const tasks: Row[] = [];
    for (let i = 0; i < 25; i++) {
      const recur = rand() < 0.4 ? 'none' : 'daily';
      const due = addDays('2025-12-01', int(0, 300));
      tasks.push({
        id: `diff-task-${String(i).padStart(4, '0')}`,
        recur,
        due_date: due,
        recur_until: recur === 'daily' && rand() < 0.5 ? addDays(due, int(0, 120)) : null,
        recur_days: recur === 'daily' && rand() < 0.6 ? int(1, 126) : null,
        deleted: rand() < 0.1,
      });
    }
    for (const t of tasks) {
      await db.execute({
        sql: `INSERT INTO tasks (id, user_id, title, due_date, recur, recur_until, recur_days, created_at, updated_at, deleted_at)
              VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        args: [t.id, u.id, t.id, t.due_date, t.recur, t.recur_until, t.recur_days, now, now, t.deleted ? now : null],
      });
    }
    // Skip some occurring (task, day) pairs
    const skipped = new Set<string>();
    for (let tries = 0; tries < 400 && skipped.size < 40; tries++) {
      const t = tasks[int(0, tasks.length - 1)];
      const d = addDays(START, int(0, DAYS - 1));
      if (!t.deleted && occursOn(t, d) && !skipped.has(`${t.id}|${d}`)) {
        skipped.add(`${t.id}|${d}`);
        await db.execute({
          sql: `INSERT INTO task_days (task_id, user_id, date, status, updated_at) VALUES (?, ?, ?, 'skipped', ?)`,
          args: [t.id, u.id, d, now],
        });
      }
    }

    const expectedFor = (d: string) =>
      tasks.filter((t) => !t.deleted && occursOn(t, d) && !skipped.has(`${t.id}|${d}`)).map((t) => t.id).sort();

    let occurrences = 0;
    for (let i = 0; i < DAYS; i++) {
      const d = addDays(START, i);
      const actual = (await listTasksForDate(u.ctx(), d)).map((t) => t.id).sort();
      expect(actual, d).toEqual(expectedFor(d));
      occurrences += actual.length;
    }
    expect(occurrences).toBeGreaterThan(300); // the data actually exercises the rule

    for (let from = START; from < addDays(START, DAYS); from = addDays(from, 60)) {
      const to = addDays(from, 59);
      for (const s of await dayStats(u.ctx(), from, to)) expect(s.planned, s.date).toBe(expectedFor(s.date).length);
    }
  });
});
