import { beforeEach, describe, expect, it } from 'vitest';
import type { Client } from '@libsql/client';
import { createTask, deleteTask, getTask, listOverdue, listTasksForDate, moveTasks, setDay, updateTask } from '../lib/services/tasks';
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

const ids = (rows: { id: string }[]) => rows.map((r) => r.id).sort();
const expectApi = async (p: Promise<unknown>, status: number, code?: string) => {
  const err = await p.then(
    () => null,
    (e) => e,
  );
  expect(err).toBeInstanceOf(ApiError);
  expect((err as ApiError).status).toBe(status);
  if (code) expect((err as ApiError).code).toBe(code);
};

describe('recurrence expansion', () => {
  it('shows a one-off only on its due date', async () => {
    const t = await createTask(u.ctx(), task({ title: 'once', due_date: '2026-11-10' }));
    expect(ids(await listTasksForDate(u.ctx(), '2026-11-10'))).toEqual([t.id]);
    expect(await listTasksForDate(u.ctx(), '2026-11-09')).toHaveLength(0);
    expect(await listTasksForDate(u.ctx(), '2026-11-11')).toHaveLength(0);
  });

  it('shows a daily task from its start day onward, not before', async () => {
    const t = await createTask(u.ctx(), task({ title: 'daily', due_date: '2026-11-10', recur: 'daily' }));
    expect(await listTasksForDate(u.ctx(), '2026-11-09')).toHaveLength(0);
    expect(ids(await listTasksForDate(u.ctx(), '2026-11-10'))).toEqual([t.id]);
    expect(ids(await listTasksForDate(u.ctx(), '2027-03-01'))).toEqual([t.id]);
  });

  it('treats recur_until as inclusive', async () => {
    await createTask(u.ctx(), task({ title: 'ends', due_date: '2026-11-10', recur: 'daily', recur_until: '2026-11-12' }));
    expect(await listTasksForDate(u.ctx(), '2026-11-12')).toHaveLength(1);
    expect(await listTasksForDate(u.ctx(), '2026-11-13')).toHaveLength(0);
  });

  it('crosses month, year and leap-day boundaries', async () => {
    await createTask(u.ctx(), task({ title: 'span', due_date: '2027-12-30', recur: 'daily', recur_until: '2028-03-01' }));
    for (const d of ['2027-12-31', '2028-01-01', '2028-02-28', '2028-02-29', '2028-03-01']) {
      expect(await listTasksForDate(u.ctx(), d), d).toHaveLength(1);
    }
    expect(await listTasksForDate(u.ctx(), '2028-03-02')).toHaveLength(0);
  });

  it('hides a skipped day only for that day', async () => {
    const t = await createTask(u.ctx(), task({ title: 'daily', due_date: '2026-11-01', recur: 'daily' }));
    await deleteTask(u.ctx(), t.id, 'day:2026-11-07');
    expect(await listTasksForDate(u.ctx(), '2026-11-07')).toHaveLength(0);
    expect(await listTasksForDate(u.ctx(), '2026-11-06')).toHaveLength(1);
    expect(await listTasksForDate(u.ctx(), '2026-11-08')).toHaveLength(1);
  });

  it('hides soft-deleted tasks everywhere', async () => {
    const t = await createTask(u.ctx(), task({ title: 'gone', due_date: '2026-11-06' }));
    await deleteTask(u.ctx(), t.id, 'all');
    expect(await listTasksForDate(u.ctx(), '2026-11-06')).toHaveLength(0);
    await expectApi(getTask(u.ctx(), t.id), 404);
  });

  it('keeps per-day completion and notes independent', async () => {
    const t = await createTask(u.ctx(), task({ title: 'daily', due_date: '2026-11-01', recur: 'daily' }));
    await setDay(u.ctx(), t.id, '2026-11-05', { status: 'done', note: 'five' });
    await setDay(u.ctx(), t.id, '2026-11-06', { status: 'done', note: 'six' });
    const d5 = (await listTasksForDate(u.ctx(), '2026-11-05'))[0];
    const d6 = (await listTasksForDate(u.ctx(), '2026-11-06'))[0];
    const d7 = (await listTasksForDate(u.ctx(), '2026-11-07'))[0];
    expect([d5.status, d5.day_note]).toEqual(['done', 'five']);
    expect([d6.status, d6.day_note]).toEqual(['done', 'six']);
    expect([d7.status, d7.day_note]).toEqual(['open', null]);
  });
});

describe('delete scopes', () => {
  it('day:D is idempotent', async () => {
    const t = await createTask(u.ctx(), task({ title: 'd', due_date: '2026-11-01', recur: 'daily' }));
    await deleteTask(u.ctx(), t.id, 'day:2026-11-07');
    await deleteTask(u.ctx(), t.id, 'day:2026-11-07');
    expect(await listTasksForDate(u.ctx(), '2026-11-07')).toHaveLength(0);
  });

  it('day:D outside the series is rejected', async () => {
    const t = await createTask(u.ctx(), task({ title: 'd', due_date: '2026-11-10', recur: 'daily' }));
    await expectApi(deleteTask(u.ctx(), t.id, 'day:2026-11-01'), 422, 'not_on_date');
  });

  it('from:D ends the series the day before D', async () => {
    const t = await createTask(u.ctx(), task({ title: 'd', due_date: '2026-11-01', recur: 'daily' }));
    await deleteTask(u.ctx(), t.id, 'from:2026-11-09');
    expect((await getTask(u.ctx(), t.id)).recur_until).toBe('2026-11-08');
    expect(await listTasksForDate(u.ctx(), '2026-11-08')).toHaveLength(1);
    expect(await listTasksForDate(u.ctx(), '2026-11-09')).toHaveLength(0);
  });

  it('from:D on the first day (or earlier) deletes the whole series', async () => {
    const t = await createTask(u.ctx(), task({ title: 'd', due_date: '2026-11-05', recur: 'daily' }));
    await deleteTask(u.ctx(), t.id, 'from:2026-11-05');
    await expectApi(getTask(u.ctx(), t.id), 404);
  });

  it('from:D never extends a series that already ended earlier', async () => {
    const t = await createTask(u.ctx(), task({ title: 'd', due_date: '2026-11-01', recur: 'daily', recur_until: '2026-11-05' }));
    await deleteTask(u.ctx(), t.id, 'from:2026-11-20');
    expect((await getTask(u.ctx(), t.id)).recur_until).toBe('2026-11-05');
  });

  it('any scope deletes a one-off', async () => {
    const a = await createTask(u.ctx(), task({ title: 'a', due_date: '2026-11-06' }));
    const b = await createTask(u.ctx(), task({ title: 'b', due_date: '2026-11-06' }));
    await deleteTask(u.ctx(), a.id, 'from:2026-11-06');
    await deleteTask(u.ctx(), b.id, 'day:2026-11-06');
    expect(await listTasksForDate(u.ctx(), '2026-11-06')).toHaveLength(0);
  });
});

describe('setDay (idempotent, never a toggle)', () => {
  it('records done once and keeps the original completion time on replay', async () => {
    const t = await createTask(u.ctx(), task({ title: 'x', due_date: '2026-11-06' }));
    const first = await setDay(u.ctx(), t.id, '2026-11-06', { status: 'done' });
    clock.set('2026-11-06T18:00:00Z');
    const again = await setDay(u.ctx(), t.id, '2026-11-06', { status: 'done' });
    expect(first.status).toBe('done');
    expect(again.completed_at).toBe(first.completed_at);
  });

  it('open removes the record and is itself idempotent', async () => {
    const t = await createTask(u.ctx(), task({ title: 'x', due_date: '2026-11-06' }));
    await setDay(u.ctx(), t.id, '2026-11-06', { status: 'done' });
    expect((await setDay(u.ctx(), t.id, '2026-11-06', { status: 'open' })).status).toBe('open');
    expect((await setDay(u.ctx(), t.id, '2026-11-06', { status: 'open' })).status).toBe('open');
  });

  it('rejects a day the task does not occur on', async () => {
    const t = await createTask(u.ctx(), task({ title: 'x', due_date: '2026-11-06' }));
    await expectApi(setDay(u.ctx(), t.id, '2026-11-07', { status: 'done' }), 422, 'not_on_date');
  });

  it('keeps a replayed offline completion time but refuses the future', async () => {
    const t = await createTask(u.ctx(), task({ title: 'x', due_date: '2026-11-06' }));
    const r = await setDay(u.ctx(), t.id, '2026-11-06', { status: 'done', completed_at: '2026-11-06T08:30:00Z' });
    expect(r.completed_at).toBe('2026-11-06T08:30:00.000Z');
    const t2 = await createTask(u.ctx(), task({ title: 'y', due_date: '2026-11-06' }));
    await expectApi(setDay(u.ctx(), t2.id, '2026-11-06', { status: 'done', completed_at: '2026-11-07T08:30:00Z' }), 400, 'invalid_time');
  });

  it('records completed_on in the user local day, not UTC', async () => {
    const ist = await makeUser(db, clock, { tz: 'Asia/Kolkata' });
    const t = await createTask(ist.ctx(), task({ title: 'late', due_date: '2026-11-06' }));
    // 20:30 UTC on the 6th is 02:00 on the 7th in India.
    clock.set('2026-11-06T20:30:00Z');
    await setDay(ist.ctx(), t.id, '2026-11-06', { status: 'done' });
    const row = await db.execute({ sql: 'SELECT completed_on FROM task_days WHERE task_id = ?', args: [t.id] });
    expect(String(row.rows[0].completed_on)).toBe('2026-11-07');
  });
});

describe('update rules', () => {
  it('reschedules an open one-off', async () => {
    const t = await createTask(u.ctx(), task({ title: 'x', due_date: '2026-11-06' }));
    const moved = await updateTask(u.ctx(), t.id, { due_date: '2026-11-09' });
    expect(moved.due_date).toBe('2026-11-09');
  });

  it('refuses to reschedule a done one-off (409)', async () => {
    const t = await createTask(u.ctx(), task({ title: 'x', due_date: '2026-11-06' }));
    await setDay(u.ctx(), t.id, '2026-11-06', { status: 'done' });
    await expectApi(updateTask(u.ctx(), t.id, { due_date: '2026-11-09' }), 409, 'not_open');
  });

  it('daily -> none drops the other days and clears recur_until', async () => {
    const t = await createTask(u.ctx(), task({ title: 'x', due_date: '2026-11-01', recur: 'daily', recur_until: '2026-11-30' }));
    await setDay(u.ctx(), t.id, '2026-11-01', { status: 'done' });
    await setDay(u.ctx(), t.id, '2026-11-02', { status: 'done' });
    const one = await updateTask(u.ctx(), t.id, { recur: 'none' });
    expect(one.recur_until).toBeNull();
    const rows = await db.execute({ sql: 'SELECT date FROM task_days WHERE task_id = ?', args: [t.id] });
    expect(rows.rows.map((r) => String(r.date))).toEqual(['2026-11-01']);
  });

  it('rejects an end date before the start', async () => {
    await expectApi(createTask(u.ctx(), task({ title: 'x', due_date: '2026-11-10', recur: 'daily', recur_until: '2026-11-01' })), 422, 'invalid_recurrence');
  });
});

describe('overdue', () => {
  it('lists open past one-offs only', async () => {
    const open = await createTask(u.ctx(), task({ title: 'open', due_date: '2026-11-01' }));
    const done = await createTask(u.ctx(), task({ title: 'done', due_date: '2026-11-02' }));
    const skipped = await createTask(u.ctx(), task({ title: 'skipped', due_date: '2026-11-03' }));
    const daily = await createTask(u.ctx(), task({ title: 'daily', due_date: '2026-10-01', recur: 'daily' }));
    const today = await createTask(u.ctx(), task({ title: 'today', due_date: '2026-11-06' }));
    const future = await createTask(u.ctx(), task({ title: 'future', due_date: '2026-11-09' }));
    const deleted = await createTask(u.ctx(), task({ title: 'deleted', due_date: '2026-11-04' }));
    await setDay(u.ctx(), done.id, '2026-11-02', { status: 'done' });
    await setDay(u.ctx(), skipped.id, '2026-11-03', { status: 'skipped' });
    await deleteTask(u.ctx(), deleted.id, 'all');
    const { items, count } = await listOverdue(u.ctx(), '2026-11-06');
    expect(ids(items)).toEqual([open.id]);
    expect(count).toBe(1);
    expect([daily.id, today.id, future.id]).not.toContain(open.id);
  });

  it('is a pure query: nothing is rewritten', async () => {
    const t = await createTask(u.ctx(), task({ title: 'old', due_date: '2026-11-01' }));
    await listOverdue(u.ctx(), '2026-11-06');
    expect((await getTask(u.ctx(), t.id)).due_date).toBe('2026-11-01');
  });

  it('move-to-today moves open tasks and reports ineligible ones', async () => {
    const open = await createTask(u.ctx(), task({ title: 'open', due_date: '2026-11-01' }));
    const done = await createTask(u.ctx(), task({ title: 'done', due_date: '2026-11-02' }));
    const daily = await createTask(u.ctx(), task({ title: 'daily', due_date: '2026-11-01', recur: 'daily' }));
    await setDay(u.ctx(), done.id, '2026-11-02', { status: 'done' });
    const r = await moveTasks(u.ctx(), [open.id, done.id, daily.id, 'does-not-exist'], '2026-11-06');
    expect(r.moved).toEqual([open.id]);
    expect(r.skipped.sort()).toEqual([done.id, daily.id, 'does-not-exist'].sort());
    expect((await getTask(u.ctx(), open.id)).due_date).toBe('2026-11-06');
    expect((await listOverdue(u.ctx(), '2026-11-06')).count).toBe(0);
  });
});

describe('create idempotency', () => {
  it('returns the first row when the same id is created twice', async () => {
    const input = task({ id: 'task-abcdef01', title: 'once', due_date: '2026-11-06' });
    const a = await createTask(u.ctx(), input);
    const b = await createTask(u.ctx(), { ...input, title: 'changed' });
    expect(b.id).toBe(a.id);
    expect(b.title).toBe('once');
    expect(await listTasksForDate(u.ctx(), '2026-11-06')).toHaveLength(1);
  });

  it("reports another user's id as a generic 409", async () => {
    const other = await makeUser(db, clock);
    await createTask(other.ctx(), task({ id: 'task-shared01', title: 'theirs', due_date: '2026-11-06' }));
    await expectApi(createTask(u.ctx(), task({ id: 'task-shared01', title: 'mine', due_date: '2026-11-06' })), 409, 'id_in_use');
  });
});
