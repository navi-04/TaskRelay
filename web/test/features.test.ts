import { beforeEach, describe, expect, it } from 'vitest';
import type { Client } from '@libsql/client';
import { ApiError } from '../lib/errors';
import { dayStats } from '../lib/services/stats';
import { setTop } from '../lib/services/focus';
import { listActivity } from '../lib/services/activity';
import {
  createTask,
  deleteTask,
  getTask,
  listTasksForDate,
  moveTasks,
  restoreTask,
  setDay,
  updateTask,
} from '../lib/services/tasks';
import { dayView } from '../lib/services/views';
import { makeClock, makeDb, makeUser, task, type Clock, type TestUser } from './helpers';

let db: Client;
let clock: Clock;
let u: TestUser;

beforeEach(async () => {
  db = await makeDb();
  clock = makeClock('2026-11-06T12:00:00Z'); // a Friday
  u = await makeUser(db, clock);
});

const fails = async (p: Promise<unknown>, status: number, code?: string) => {
  const e = await p.then(() => null, (err) => err);
  expect(e, 'expected an ApiError').toBeInstanceOf(ApiError);
  expect((e as ApiError).status).toBe(status);
  if (code) expect((e as ApiError).code).toBe(code);
};
const titles = async (date: string) => (await listTasksForDate(u.ctx(), date)).map((t) => t.title);

describe('weekday repeats', () => {
  it('occur only on the chosen weekdays and expose them on the DTO', async () => {
    const t = await createTask(u.ctx(), task({ title: 'Gym', due_date: '2026-11-02', recur: 'daily', recur_days: [1, 3, 5] }));
    expect(t.recur_days).toEqual([1, 3, 5]);
    const week = ['02', '03', '04', '05', '06', '07', '08'].map((d) => `2026-11-${d}`);
    const on = [];
    for (const d of week) if ((await titles(d)).length) on.push(d);
    expect(on).toEqual(['2026-11-02', '2026-11-04', '2026-11-06']);
  });

  it('all seven days normalises to "every day" (null)', async () => {
    const t = await createTask(u.ctx(), task({ title: 'Daily', due_date: '2026-11-02', recur: 'daily', recur_days: [1, 2, 3, 4, 5, 6, 7] }));
    expect(t.recur_days).toBeNull();
    expect(await titles('2026-11-03')).toEqual(['Daily']);
  });

  it('a start date outside the weekdays is a lower bound: first occurrence is the next matching day', async () => {
    const t = await createTask(u.ctx(), task({ title: 'Mondays', due_date: '2026-11-07', recur: 'daily', recur_days: [1] })); // starts Saturday
    expect(await titles('2026-11-07')).toEqual([]);
    expect(await titles('2026-11-09')).toEqual(['Mondays']);
    await fails(setDay(u.ctx(), t.id, '2026-11-07', { status: 'done' }), 422, 'not_on_date');
  });

  it('rejects weekdays on a one-off, and a pattern that never occurs before its end date (422)', async () => {
    await fails(createTask(u.ctx(), task({ title: 'x', due_date: '2026-11-06', recur: 'none', recur_days: [1] })), 422, 'invalid_recurrence');
    await fails(createTask(u.ctx(), task({ title: 'x', due_date: '2026-11-07', recur: 'daily', recur_days: [1], recur_until: '2026-11-08' })), 422, 'invalid_recurrence');
    const one = await createTask(u.ctx(), task({ title: 'one', due_date: '2026-11-06' }));
    await fails(updateTask(u.ctx(), one.id, { recur_days: [2] }), 422, 'invalid_recurrence');
    await fails(updateTask(u.ctx(), one.id, { recur: 'none', recur_days: [2] }), 422, 'invalid_recurrence');
  });

  it('can be changed later: weekly -> every day -> one-off clears weekdays and the end date', async () => {
    const t = await createTask(u.ctx(), task({ title: 'Flex', due_date: '2026-11-02', recur: 'daily', recur_days: [2], recur_until: '2026-12-31' }));
    expect(await titles('2026-11-03')).toEqual(['Flex']);
    expect(await titles('2026-11-04')).toEqual([]);

    const everyDay = await updateTask(u.ctx(), t.id, { recur_days: null });
    expect(everyDay.recur_days).toBeNull();
    expect(await titles('2026-11-04')).toEqual(['Flex']);

    const asWeekly = await updateTask(u.ctx(), t.id, { recur_days: [5] });
    expect(asWeekly.recur_days).toEqual([5]);
    expect(await titles('2026-11-04')).toEqual([]);

    const oneOff = await updateTask(u.ctx(), t.id, { recur: 'none' });
    expect([oneOff.recur_days, oneOff.recur_until]).toEqual([null, null]);
  });

  it('a one-off can become a weekly series in one edit', async () => {
    const t = await createTask(u.ctx(), task({ title: 'Grow', due_date: '2026-11-02' }));
    const r = await updateTask(u.ctx(), t.id, { recur: 'daily', recur_days: [1, 4] });
    expect([r.recur, r.recur_days]).toEqual(['daily', [1, 4]]);
    expect(await titles('2026-11-05')).toEqual(['Grow']); // Thursday
  });

  it('skip-one-day and end-the-series respect the weekdays', async () => {
    const t = await createTask(u.ctx(), task({ title: 'MWF', due_date: '2026-11-02', recur: 'daily', recur_days: [1, 3, 5] }));
    await fails(deleteTask(u.ctx(), t.id, 'day:2026-11-03'), 422, 'not_on_date'); // a Tuesday
    await deleteTask(u.ctx(), t.id, 'day:2026-11-04'); // Wednesday
    expect(await titles('2026-11-04')).toEqual([]);
    expect(await titles('2026-11-06')).toEqual(['MWF']);
    await deleteTask(u.ctx(), t.id, 'from:2026-11-09');
    expect(await titles('2026-11-09')).toEqual([]);
  });

  it('stats count only the days the task occurs on', async () => {
    await createTask(u.ctx(), task({ title: 'Tue/Thu', due_date: '2026-11-02', recur: 'daily', recur_days: [2, 4] }));
    const days = await dayStats(u.ctx(), '2026-11-02', '2026-11-08');
    expect(days.map((d) => d.planned)).toEqual([0, 1, 0, 1, 0, 0, 0]);
  });
});

describe("Today's Top 3", () => {
  const make = (title: string, extra = {}) => createTask(u.ctx(), task({ title, due_date: '2026-11-06', ...extra }));

  it('sets, reorders, replaces and clears the list; position is exposed on tasks and in the day view', async () => {
    const [a, b, c] = [await make('a'), await make('b'), await make('c')];
    await setTop(u.ctx(), '2026-11-06', [b.id, a.id]);
    let v = await dayView(u.ctx(), '2026-11-06');
    expect(v.top).toEqual([b.id, a.id]);
    expect(Object.fromEntries(v.tasks.map((t) => [t.title, t.top_position]))).toEqual({ a: 2, b: 1, c: null });

    await setTop(u.ctx(), '2026-11-06', [c.id]); // replace
    v = await dayView(u.ctx(), '2026-11-06');
    expect(v.top).toEqual([c.id]);

    await setTop(u.ctx(), '2026-11-06', []); // clear; repeating it is harmless
    await setTop(u.ctx(), '2026-11-06', []);
    expect((await dayView(u.ctx(), '2026-11-06')).top).toEqual([]);
  });

  it('is per day: a repeating task can be starred on one day only', async () => {
    const r = await createTask(u.ctx(), task({ title: 'daily', due_date: '2026-11-01', recur: 'daily' }));
    await setTop(u.ctx(), '2026-11-06', [r.id]);
    expect((await dayView(u.ctx(), '2026-11-06')).top).toEqual([r.id]);
    expect((await dayView(u.ctx(), '2026-11-07')).top).toEqual([]);
  });

  it('allows at most 3, no duplicates, only live tasks of the caller that occur that day', async () => {
    const [a, b, c, d] = [await make('a'), await make('b'), await make('c'), await make('d')];
    await fails(setTop(u.ctx(), '2026-11-06', [a.id, b.id, c.id, d.id]), 400, 'invalid_top');
    await fails(setTop(u.ctx(), '2026-11-06', [a.id, a.id]), 400, 'invalid_top');
    await fails(setTop(u.ctx(), '2026-11-06', ['no-such-task-id']), 404);

    const other = await makeUser(db, clock);
    const theirs = await createTask(other.ctx(), task({ title: 'theirs', due_date: '2026-11-06' }));
    await fails(setTop(u.ctx(), '2026-11-06', [theirs.id]), 404);

    const tomorrow = await createTask(u.ctx(), task({ title: 'tomorrow', due_date: '2026-11-07' }));
    await fails(setTop(u.ctx(), '2026-11-06', [tomorrow.id]), 422, 'not_on_date');
    const overdue = await createTask(u.ctx(), task({ title: 'overdue', due_date: '2026-11-01' }));
    await fails(setTop(u.ctx(), '2026-11-06', [overdue.id]), 422, 'not_on_date'); // must be moved to today first
  });

  it('a failed set leaves the previous list intact', async () => {
    const a = await make('a');
    await setTop(u.ctx(), '2026-11-06', [a.id]);
    await fails(setTop(u.ctx(), '2026-11-06', [a.id, 'no-such-task-id']), 404);
    expect((await dayView(u.ctx(), '2026-11-06')).top).toEqual([a.id]);
  });

  it('completing keeps the slot; deleting frees it; restoring brings it back', async () => {
    const [a, b] = [await make('a'), await make('b')];
    await setTop(u.ctx(), '2026-11-06', [a.id, b.id]);
    await setDay(u.ctx(), a.id, '2026-11-06', { status: 'done' });
    expect((await dayView(u.ctx(), '2026-11-06')).top).toEqual([a.id, b.id]);

    await deleteTask(u.ctx(), b.id, 'all');
    expect((await dayView(u.ctx(), '2026-11-06')).top).toEqual([a.id]);
    await restoreTask(u.ctx(), b.id);
    expect((await dayView(u.ctx(), '2026-11-06')).top).toEqual([a.id, b.id]);
  });

  it('skipping a starred repeating day drops it from the list, and a skipped task cannot be starred', async () => {
    const r = await createTask(u.ctx(), task({ title: 'daily', due_date: '2026-11-01', recur: 'daily' }));
    await setTop(u.ctx(), '2026-11-06', [r.id]);
    await deleteTask(u.ctx(), r.id, 'day:2026-11-06');
    expect((await dayView(u.ctx(), '2026-11-06')).top).toEqual([]);
    await fails(setTop(u.ctx(), '2026-11-06', [r.id]), 422, 'not_on_date');
  });

  it("is scoped per user: one user's list is invisible to another", async () => {
    const other = await makeUser(db, clock);
    const mine = await make('mine');
    const theirs = await createTask(other.ctx(), task({ title: 'theirs', due_date: '2026-11-06' }));
    await setTop(u.ctx(), '2026-11-06', [mine.id]);
    await setTop(other.ctx(), '2026-11-06', [theirs.id]);
    expect((await dayView(u.ctx(), '2026-11-06')).top).toEqual([mine.id]);
    expect((await dayView(other.ctx(), '2026-11-06')).top).toEqual([theirs.id]);
  });
});

describe('AI activity log', () => {
  it('logs AI changes with what happened, never the app user’s own edits', async () => {
    const ai = u.ctx('ai');
    const t = await createTask(ai, task({ title: 'planned', due_date: '2026-11-06' }));
    await updateTask(ai, t.id, { title: 'renamed' });
    await setDay(ai, t.id, '2026-11-06', { status: 'done' });
    const old = await createTask(ai, task({ title: 'old', due_date: '2026-11-01' }));
    await moveTasks(ai, [old.id], '2026-11-06');
    await deleteTask(ai, t.id, 'all');
    await restoreTask(ai, t.id);

    await createTask(u.ctx('app'), task({ title: 'mine', due_date: '2026-11-06' })); // not logged
    const { items } = await listActivity(u.ctx());
    expect(items.map((i) => i.kind)).toEqual(['restored', 'deleted', 'rescheduled', 'created', 'completed', 'updated', 'created']);
    expect(items.every((i) => i.actor === 'ai')).toBe(true);
    expect(items.find((i) => i.kind === 'deleted')).toMatchObject({ title: 'renamed', detail: 'all' });
    expect(items.find((i) => i.kind === 'rescheduled')).toMatchObject({ title: 'old', date: '2026-11-06', detail: 'from 2026-11-01' });
  });

  it('a replayed "done" is not logged twice', async () => {
    const ai = u.ctx('ai');
    const t = await createTask(ai, task({ title: 'x', due_date: '2026-11-06' }));
    await setDay(ai, t.id, '2026-11-06', { status: 'done' });
    await setDay(ai, t.id, '2026-11-06', { status: 'done' });
    expect((await listActivity(u.ctx())).items.filter((i) => i.kind === 'completed')).toHaveLength(1);
  });

  it('paginates newest first and keeps only the latest 200', async () => {
    const ai = u.ctx('ai');
    for (let i = 0; i < 205; i++) await createTask(ai, task({ title: `t${i}`, due_date: '2026-11-06' }));
    const first = await listActivity(u.ctx(), 50);
    expect(first.items).toHaveLength(50);
    expect(first.items[0].title).toBe('t204');
    expect(first.next_before).not.toBeNull();
    const second = await listActivity(u.ctx(), 50, first.next_before!);
    expect(second.items[0].id).toBeLessThan(first.items[49].id);

    const all = await db.execute({ sql: 'SELECT COUNT(*) AS n, MIN(title) AS oldest FROM activity WHERE user_id = ?', args: [u.id] });
    expect(Number(all.rows[0].n)).toBe(200);
    expect(String(all.rows[0].oldest)).not.toBe('t0'); // the oldest were pruned
  });

  it('is private to the user', async () => {
    const other = await makeUser(db, clock);
    await createTask(u.ctx('ai'), task({ title: 'secret', due_date: '2026-11-06' }));
    expect((await listActivity(other.ctx())).items).toHaveLength(0);
  });
});

describe('restore and the 30-day purge', () => {
  it('restores a deleted task (idempotent), recording who did it', async () => {
    const t = await createTask(u.ctx(), task({ title: 'oops', due_date: '2026-11-06' }));
    await deleteTask(u.ctx(), t.id, 'all');
    await fails(getTask(u.ctx(), t.id), 404);
    const back = await restoreTask(u.ctx('app'), t.id);
    expect(back.title).toBe('oops');
    expect((await restoreTask(u.ctx(), t.id)).id).toBe(t.id); // restoring a live task is a no-op
    expect(await titles('2026-11-06')).toEqual(['oops']);
  });

  it('cannot restore unknown tasks or another user’s tasks (404)', async () => {
    const other = await makeUser(db, clock);
    const theirs = await createTask(other.ctx(), task({ title: 'theirs', due_date: '2026-11-06' }));
    await deleteTask(other.ctx(), theirs.id, 'all');
    await fails(restoreTask(u.ctx(), theirs.id), 404);
    await fails(restoreTask(u.ctx(), 'no-such-task-id'), 404);
  });

  it('after 30 days the deleted task can no longer be restored, and is purged by the next delete', async () => {
    const old = await createTask(u.ctx(), task({ title: 'old', due_date: '2026-11-06', recur: 'daily' }));
    await setDay(u.ctx(), old.id, '2026-11-06', { status: 'done' });
    await deleteTask(u.ctx(), old.id, 'all');

    clock.set('2026-12-10T12:00:00Z'); // 34 days later
    await fails(restoreTask(u.ctx(), old.id), 404);
    const next = await createTask(u.ctx(), task({ title: 'next', due_date: '2026-12-10' }));
    await deleteTask(u.ctx(), next.id, 'all'); // lazy purge runs with any delete

    const rows = await db.execute({ sql: 'SELECT (SELECT COUNT(*) FROM tasks WHERE id = ?) AS t, (SELECT COUNT(*) FROM task_days WHERE task_id = ?) AS d', args: [old.id, old.id] });
    expect([Number(rows.rows[0].t), Number(rows.rows[0].d)]).toEqual([0, 0]);
    const fresh = await db.execute({ sql: 'SELECT COUNT(*) AS n FROM tasks WHERE id = ?', args: [next.id] });
    expect(Number(fresh.rows[0].n)).toBe(1); // recently deleted tasks are kept for undo
  });

  it('a purge never touches another user’s data', async () => {
    const other = await makeUser(db, clock);
    const theirs = await createTask(other.ctx(), task({ title: 'theirs', due_date: '2026-11-06' }));
    await deleteTask(other.ctx(), theirs.id, 'all');
    clock.set('2026-12-20T12:00:00Z');
    const mine = await createTask(u.ctx(), task({ title: 'mine', due_date: '2026-12-20' }));
    await deleteTask(u.ctx(), mine.id, 'all'); // runs *my* purge only
    const left = await db.execute({ sql: 'SELECT COUNT(*) AS n FROM tasks WHERE id = ?', args: [theirs.id] });
    expect(Number(left.rows[0].n)).toBe(1);
  });
});
