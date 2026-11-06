import { beforeEach, describe, expect, it } from 'vitest';
import type { Client } from '@libsql/client';
import { createTask, deleteTask, getTask, listOverdue, listTasksForDate, moveTasks, setDay, updateTask } from '../lib/services/tasks';
import { createLabel, deleteLabel, listLabels, updateLabel } from '../lib/services/labels';
import { dayStats, streak } from '../lib/services/stats';
import { getSettings, patchSettings } from '../lib/services/settings';
import { deleteAllTasks } from '../lib/services/auth';
import { ApiError } from '../lib/errors';
import { makeClock, makeDb, makeUser, task, type Clock, type TestUser } from './helpers';

let db: Client;
let clock: Clock;
let a: TestUser;
let b: TestUser;

beforeEach(async () => {
  db = await makeDb();
  clock = makeClock('2026-11-06T12:00:00Z');
  a = await makeUser(db, clock);
  b = await makeUser(db, clock);
});

const status = async (p: Promise<unknown>) => {
  const e = await p.then(
    () => null,
    (err) => err,
  );
  expect(e, 'expected an ApiError').toBeInstanceOf(ApiError);
  return (e as ApiError).status;
};

describe("user B can never touch user A's data (cross-user lookups are 404)", () => {
  it('tasks: read, update, delete, set day', async () => {
    const t = await createTask(a.ctx(), task({ title: 'secret', due_date: '2026-11-06' }));
    expect(await status(getTask(b.ctx(), t.id))).toBe(404);
    expect(await status(updateTask(b.ctx(), t.id, { title: 'hacked' }))).toBe(404);
    expect(await status(deleteTask(b.ctx(), t.id, 'all'))).toBe(404);
    expect(await status(setDay(b.ctx(), t.id, '2026-11-06', { status: 'done' }))).toBe(404);
    expect((await getTask(a.ctx(), t.id)).title).toBe('secret');
  });

  it('lists, overdue, stats and streak only see own tasks', async () => {
    await createTask(a.ctx(), task({ title: 'a-today', due_date: '2026-11-06' }));
    await createTask(a.ctx(), task({ title: 'a-old', due_date: '2026-11-01' }));
    expect(await listTasksForDate(b.ctx(), '2026-11-06')).toHaveLength(0);
    expect((await listOverdue(b.ctx(), '2026-11-06')).count).toBe(0);
    expect((await dayStats(b.ctx(), '2026-11-01', '2026-11-06')).every((d) => d.planned === 0)).toBe(true);
    expect(await streak(b.ctx(), '2026-11-06')).toBe(0);
  });

  it("move reports A's ids as skipped and leaves them untouched", async () => {
    const t = await createTask(a.ctx(), task({ title: 'old', due_date: '2026-11-01' }));
    const r = await moveTasks(b.ctx(), [t.id], '2026-11-06');
    expect(r).toEqual({ moved: [], skipped: [t.id] });
    expect((await getTask(a.ctx(), t.id)).due_date).toBe('2026-11-01');
  });

  it('delete-all only deletes the caller’s tasks', async () => {
    const mine = await createTask(a.ctx(), task({ title: 'mine', due_date: '2026-11-06' }));
    await createTask(b.ctx(), task({ title: 'theirs', due_date: '2026-11-06' }));
    await deleteAllTasks(db, b.id);
    expect((await getTask(a.ctx(), mine.id)).title).toBe('mine');
    expect(await listTasksForDate(b.ctx(), '2026-11-06')).toHaveLength(0);
  });

  it('labels: list, update, delete', async () => {
    const aLabels = await listLabels(a.ctx());
    const bLabels = await listLabels(b.ctx());
    expect(aLabels.types.map((l) => l.id)).not.toEqual(expect.arrayContaining(bLabels.types.map((l) => l.id)));
    expect(await status(updateLabel(b.ctx(), aLabels.types[0].id, { label: 'x' }))).toBe(404);
    expect(await status(deleteLabel(b.ctx(), aLabels.types[0].id))).toBe(404);
  });

  it('settings are per user', async () => {
    await patchSettings(a.ctx(), { daily_time_limit_min: 120, estimation_mode: 'count' });
    expect(await getSettings(b.ctx())).toMatchObject({ daily_time_limit_min: 480, estimation_mode: 'time' });
  });
});

describe('labels referenced by tasks', () => {
  it("rejects another user's label, and a label of the wrong kind (400)", async () => {
    const aLabels = await listLabels(a.ctx());
    expect(await status(createTask(b.ctx(), task({ title: 'x', due_date: '2026-11-06', type_id: aLabels.types[0].id })))).toBe(400);
    const own = await listLabels(b.ctx());
    // a priority id used as a type id
    expect(await status(createTask(b.ctx(), task({ title: 'x', due_date: '2026-11-06', type_id: own.priorities[0].id })))).toBe(400);
    const t = await createTask(b.ctx(), task({ title: 'ok', due_date: '2026-11-06', type_id: own.types[0].id }));
    expect(await status(updateTask(b.ctx(), t.id, { priority_id: aLabels.priorities[0].id }))).toBe(400);
  });

  it('deleting a label detaches it from tasks instead of leaving a dangling id', async () => {
    const { types } = await listLabels(a.ctx());
    const t = await createTask(a.ctx(), task({ title: 'x', due_date: '2026-11-06', type_id: types[1].id }));
    await deleteLabel(a.ctx(), types[1].id);
    expect((await getTask(a.ctx(), t.id)).type_id).toBeNull();
    expect((await listLabels(a.ctx())).types).toHaveLength(7);
  });

  it('the last label of a kind cannot be deleted', async () => {
    let { priorities } = await listLabels(a.ctx());
    for (const p of priorities.slice(1)) await deleteLabel(a.ctx(), p.id);
    priorities = (await listLabels(a.ctx())).priorities;
    expect(priorities).toHaveLength(1);
    expect(await status(deleteLabel(a.ctx(), priorities[0].id))).toBe(409);
  });

  it('new labels sort after existing ones', async () => {
    const created = await createLabel(a.ctx(), { kind: 'type', label: 'Errand' });
    const { types } = await listLabels(a.ctx());
    expect(types[types.length - 1].id).toBe(created.id);
  });
});
