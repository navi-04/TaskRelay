import { beforeEach, describe, expect, it } from 'vitest';
import type { Client, InStatement } from '@libsql/client';
import { createLabel, deleteLabel, listLabels, updateLabel } from '../lib/services/labels';
import { getSettings, patchSettings } from '../lib/services/settings';
import { dayStats, streak, weekSummary } from '../lib/services/stats';
import { createTask, deleteTask, getTask, listOverdue, listTasksForDate, moveTasks, setDay, updateTask } from '../lib/services/tasks';
import { deleteAllTasks, setTimezone } from '../lib/services/auth';
import { overview } from '../lib/services/views';
import { makeClock, makeDb, makeUser, task, type Clock, type TestUser } from './helpers';

/**
 * Wraps a client so that a bare `execute` touching phone-visible tables throws.
 * Those tables may only be written through writeBatch (which bumps data_version atomically).
 */
function guarded(db: Client): Client {
  return new Proxy(db, {
    get(target, prop) {
      if (prop === 'execute') {
        return (stmt: InStatement) => {
          const sql = typeof stmt === 'string' ? stmt : stmt.sql;
          if (/^\s*(INSERT|UPDATE|DELETE|REPLACE)\b/i.test(sql) && /\b(tasks|task_days|labels|settings|day_focus)\b/i.test(sql)) {
            throw new Error(`bare write to a phone-visible table (use writeBatch): ${sql.slice(0, 90)}`);
          }
          return target.execute(stmt);
        };
      }
      const value = Reflect.get(target, prop, target);
      return typeof value === 'function' ? value.bind(target) : value;
    },
  });
}

let raw: Client;
let db: Client;
let clock: Clock;
let u: TestUser;
let other: TestUser;

const version = async (userId: string) =>
  Number((await raw.execute({ sql: 'SELECT data_version AS v FROM users WHERE id = ?', args: [userId] })).rows[0].v);

beforeEach(async () => {
  raw = await makeDb();
  db = guarded(raw);
  clock = makeClock('2026-11-06T12:00:00Z');
  u = await makeUser(raw, clock);
  other = await makeUser(raw, clock);
});

const ctx = () => ({ ...u.ctx(), db });

describe('data_version (the phone feed change token)', () => {
  it('starts at 0 for a new user', async () => {
    expect(await version(u.id)).toBe(0);
  });

  it('the guard itself works: a bare write to a phone-visible table throws, other writes pass', async () => {
    expect(() => db.execute({ sql: "UPDATE tasks SET title = 'x'", args: [] })).toThrow(/bare write/);
    expect(() => db.execute(`DELETE FROM labels`)).toThrow(/bare write/);
    await expect(db.execute({ sql: 'UPDATE sessions SET last_used = last_used', args: [] })).resolves.toBeTruthy();
  });

  it('every write operation bumps it, and none writes outside writeBatch', async () => {
    await createTask(ctx(), task({ id: 'ver-seed-0001', title: 'seed', due_date: '2026-11-06' }));
    await createTask(ctx(), task({ id: 'ver-daily-0001', title: 'daily', due_date: '2026-11-01', recur: 'daily' }));
    await createTask(ctx(), task({ id: 'ver-old-0001', title: 'old', due_date: '2026-11-01' }));
    const labels = await listLabels(ctx());

    const ops: Array<[string, () => Promise<unknown>]> = [
      ['create task', () => createTask(ctx(), task({ title: 'new', due_date: '2026-11-07' }))],
      ['update task', () => updateTask(ctx(), 'ver-seed-0001', { title: 'renamed' })],
      ['set day done', () => setDay(ctx(), 'ver-seed-0001', '2026-11-06', { status: 'done' })],
      ['set day open', () => setDay(ctx(), 'ver-seed-0001', '2026-11-06', { status: 'open' })],
      ['move overdue task', () => moveTasks(ctx(), ['ver-old-0001'], '2026-11-06')],
      ['skip one day', () => deleteTask(ctx(), 'ver-daily-0001', 'day:2026-11-03')],
      ['end the series', () => deleteTask(ctx(), 'ver-daily-0001', 'from:2026-11-20')],
      ['delete task', () => deleteTask(ctx(), 'ver-seed-0001', 'all')],
      ['create label', () => createLabel(ctx(), { kind: 'type', label: 'Errand' })],
      ['update label', () => updateLabel(ctx(), labels.types[0].id, { label: 'Renamed' })],
      ['delete label', () => deleteLabel(ctx(), labels.types[1].id)],
      ['patch settings', () => patchSettings(ctx(), { daily_count_limit: 5 })],
      ['change timezone', () => setTimezone(raw, u.id, 'Asia/Kolkata')],
      ['delete all tasks', () => deleteAllTasks(raw, u.id)],
    ];

    for (const [name, op] of ops) {
      const before = await version(u.id);
      await op();
      expect(await version(u.id), name).toBeGreaterThan(before);
    }
  });

  it('reads never bump it', async () => {
    await createTask(ctx(), task({ id: 'ver-read-0001', title: 'x', due_date: '2026-11-06' }));
    const before = await version(u.id);
    await listTasksForDate(ctx(), '2026-11-06');
    await getTask(ctx(), 'ver-read-0001');
    await listOverdue(ctx(), '2026-11-06');
    await dayStats(ctx(), '2026-11-01', '2026-11-06');
    await streak(ctx(), '2026-11-06');
    await weekSummary(ctx(), '2026-11-06');
    await getSettings(ctx());
    await listLabels(ctx());
    await overview(ctx());
    expect(await version(u.id)).toBe(before);
  });

  it("one user's writes never change another user's version", async () => {
    const before = await version(other.id);
    await createTask(ctx(), task({ title: 'mine', due_date: '2026-11-06' }));
    await patchSettings(ctx(), { daily_count_limit: 7 });
    expect(await version(other.id)).toBe(before);
  });

  it('a no-op create retry (same id) still returns the task and does not corrupt state', async () => {
    const input = task({ id: 'ver-retry-0001', title: 'once', due_date: '2026-11-06' });
    await createTask(ctx(), input);
    await createTask(ctx(), input);
    expect(await listTasksForDate(ctx(), '2026-11-06')).toHaveLength(1);
  });
});
