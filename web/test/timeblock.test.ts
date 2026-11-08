import { beforeAll, describe, expect, it, vi } from 'vitest';

vi.stubEnv('TURSO_DATABASE_URL', ':memory:');

import * as register from '../app/api/v1/auth/register/route';
import * as me from '../app/api/v1/me/route';
import * as tasks from '../app/api/v1/tasks/route';
import * as taskById from '../app/api/v1/tasks/[id]/route';
import * as taskDay from '../app/api/v1/tasks/[id]/days/[date]/route';
import * as sync from '../app/api/v1/sync/route';
import * as aiTasks from '../app/api/ai/tasks/route';
import * as aiManual from '../app/api/ai/route';
import { getDb } from '../lib/db';
import { migrate } from '../lib/migrate';
import { listTasksForDate, createTask, setDay, updateTask } from '../lib/services/tasks';
import { sheetView } from '../lib/services/sheet';
import { buildSync, syncEtag } from '../lib/services/sync';
import { taskBlock, toMinutes } from '../lib/timeblock';
import { call, makeClock, makeDb, makeUser, task } from './helpers';

describe('taskBlock: the one rule for "when is this task occupying my day"', () => {
  const t = (start_time: string | null, end_time: string | null, duration_min = 30) => ({ start_time, end_time, duration_min });

  it('start and end give the block; start alone lasts the duration; an end alone or nothing is no block', () => {
    expect(taskBlock(t('09:00', '10:30', 90))).toEqual({ start: 540, end: 630 });
    expect(taskBlock(t('09:00', null, 45))).toEqual({ start: 540, end: 585 });
    expect(taskBlock(t(null, '17:00'))).toBeNull();
    expect(taskBlock(t(null, null))).toBeNull();
  });

  it('a block that would run past midnight is cut at midnight', () => {
    expect(taskBlock(t('23:30', null, 120))).toEqual({ start: 1410, end: 1440 });
    expect(taskBlock(t('00:00', '23:59'))).toEqual({ start: 0, end: 1439 });
  });

  it('a block with no length is not a block', () => {
    expect(taskBlock(t('23:59', null, 30))).toEqual({ start: 1439, end: 1440 });
    expect(taskBlock(t('10:00', '10:00'))).toBeNull();
    expect(toMinutes('07:05')).toBe(425);
  });
});

describe('start and end time on a task (service)', () => {
  it('stores both, and the duration becomes their difference', async () => {
    const db = await makeDb();
    const u = await makeUser(db, makeClock());
    const ctx = u.ctx();
    const made = await createTask(ctx, task({ id: 'tb-both-0001', title: 'Deep work', due_date: '2026-11-06', start_time: '09:00', end_time: '10:30', duration_min: 15 }));
    expect([made.start_time, made.end_time, made.duration_min]).toEqual(['09:00', '10:30', 90]); // the times win over a stale estimate
  });

  it('keeps the estimate when only a start (or only an end) is given, and the default of 30 when nothing is', async () => {
    const db = await makeDb();
    const ctx = (await makeUser(db, makeClock())).ctx();
    const a = await createTask(ctx, task({ id: 'tb-start-001', title: 'A', due_date: '2026-11-06', start_time: '14:00', duration_min: 45 }));
    const b = await createTask(ctx, task({ id: 'tb-end-00001', title: 'B', due_date: '2026-11-06', end_time: '17:00' }));
    const c = await createTask(ctx, task({ id: 'tb-none-0001', title: 'C', due_date: '2026-11-06' }));
    expect([a.start_time, a.end_time, a.duration_min]).toEqual(['14:00', null, 45]);
    expect([b.start_time, b.end_time, b.duration_min]).toEqual([null, '17:00', 30]);
    expect([c.start_time, c.end_time, c.duration_min]).toEqual([null, null, 30]);
  });

  it('refuses an end that is not after the start, on create and on update', async () => {
    const db = await makeDb();
    const ctx = (await makeUser(db, makeClock())).ctx();
    const { taskCreate } = await import('../lib/validation');
    for (const [start, end] of [['10:00', '10:00'], ['10:00', '09:59']]) {
      const parsed = taskCreate.safeParse({ title: 'X', due_date: '2026-11-06', start_time: start, end_time: end });
      expect(parsed.success).toBe(false);
      expect(parsed.error?.issues[0].path).toEqual(['end_time']);
    }
    await createTask(ctx, task({ id: 'tb-upd-00001', title: 'U', due_date: '2026-11-06', start_time: '10:00', end_time: '11:00' }));
    // a one-sided change is checked against the stored side
    await expect(updateTask(ctx, 'tb-upd-00001', { end_time: '09:00' })).rejects.toMatchObject({ status: 422, code: 'invalid_time_range' });
    await expect(updateTask(ctx, 'tb-upd-00001', { start_time: '11:30' })).rejects.toMatchObject({ status: 422, code: 'invalid_time_range' });
    const kept = (await listTasksForDate(ctx, '2026-11-06'))[0];
    expect([kept.start_time, kept.end_time, kept.duration_min]).toEqual(['10:00', '11:00', 60]); // nothing was half-applied
  });

  it('moving one side recomputes the duration; removing a side keeps the last duration', async () => {
    const db = await makeDb();
    const ctx = (await makeUser(db, makeClock())).ctx();
    await createTask(ctx, task({ id: 'tb-move-0001', title: 'M', due_date: '2026-11-06', start_time: '10:00', end_time: '11:00' }));
    const later = await updateTask(ctx, 'tb-move-0001', { end_time: '12:15' });
    expect([later.start_time, later.end_time, later.duration_min]).toEqual(['10:00', '12:15', 135]);
    const shifted = await updateTask(ctx, 'tb-move-0001', { start_time: '12:00' });
    expect([shifted.start_time, shifted.end_time, shifted.duration_min]).toEqual(['12:00', '12:15', 15]);
    const open = await updateTask(ctx, 'tb-move-0001', { end_time: null });
    expect([open.start_time, open.end_time, open.duration_min]).toEqual(['12:00', null, 15]);
    const longer = await updateTask(ctx, 'tb-move-0001', { duration_min: 50 }); // no end any more: the estimate is free again
    expect(longer.duration_min).toBe(50);
    const cleared = await updateTask(ctx, 'tb-move-0001', { start_time: null });
    expect([cleared.start_time, cleared.end_time]).toEqual([null, null]);
  });

  it('a duration that contradicts the times is refused, the same duration is fine', async () => {
    const db = await makeDb();
    const ctx = (await makeUser(db, makeClock())).ctx();
    await createTask(ctx, task({ id: 'tb-dur-00001', title: 'D', due_date: '2026-11-06', start_time: '10:00', end_time: '11:00' }));
    await expect(updateTask(ctx, 'tb-dur-00001', { duration_min: 30 })).rejects.toMatchObject({ status: 422, code: 'duration_follows_times' });
    expect((await updateTask(ctx, 'tb-dur-00001', { duration_min: 60, notes: 'same length' })).duration_min).toBe(60);
    // changing the times in the same request as a stale duration: the times win
    expect((await updateTask(ctx, 'tb-dur-00001', { end_time: '10:30', duration_min: 60 })).duration_min).toBe(30);
  });

  it('applies to every day of a repeating task and sorts the day by start time', async () => {
    const db = await makeDb();
    const ctx = (await makeUser(db, makeClock())).ctx();
    await createTask(ctx, task({ id: 'tb-late-0001', title: 'Late block', due_date: '2026-11-06', start_time: '16:00', end_time: '17:00' }));
    await createTask(ctx, task({ id: 'tb-rep-00001', title: 'Standup', due_date: '2026-11-02', recur: 'daily', recur_days: [1, 2, 3, 4, 5], start_time: '09:00', end_time: '09:15' }));
    await createTask(ctx, task({ id: 'tb-plain-001', title: 'No time', due_date: '2026-11-06' }));
    await createTask(ctx, task({ id: 'tb-alarm-001', title: 'Alarm only', due_date: '2026-11-06', alarm_time: '12:00' }));
    const day = await listTasksForDate(ctx, '2026-11-06');
    expect(day.map((x) => x.id)).toEqual(['tb-rep-00001', 'tb-alarm-001', 'tb-late-0001', 'tb-plain-001']); // 09:00, 12:00 (alarm), 16:00, none
    expect(day[0].start_time).toBe('09:00');
    expect(day[0].duration_min).toBe(15);
  });
});

describe('the database rejects a bad time block even if the service did not', () => {
  it('has CHECKs on both columns', async () => {
    const db = await makeDb();
    const u = await makeUser(db, makeClock());
    const insert = (id: string, start: string | null, end: string | null) =>
      db.execute({
        sql: `INSERT INTO tasks (id, user_id, title, due_date, start_time, end_time, created_at, updated_at) VALUES (?, ?, 't', '2026-11-06', ?, ?, 'x', 'x')`,
        args: [id, u.id, start, end],
      });
    await expect(insert('chk-1', '10:00', '09:00')).rejects.toThrow();
    await expect(insert('chk-2', '1a:00', null)).rejects.toThrow(); // (the exact 00-23 range is zod's job, as for alarm_time)
    await expect(insert('chk-3', null, '9:5')).rejects.toThrow();
    await expect(insert('chk-4', '10:00', '11:00')).resolves.toBeDefined();
    await expect(insert('chk-5', null, '08:00')).resolves.toBeDefined(); // an end alone is allowed
  });
});

describe('the phone feed carries the blocks', () => {
  it('lists today\'s timed tasks earliest first with their done state, and changes its ETag shape', async () => {
    const db = await makeDb();
    const clock = makeClock('2026-11-06T08:00:00Z');
    const ctx = (await makeUser(db, clock)).ctx();
    await createTask(ctx, task({ id: 'tb-sync-0002', title: 'Afternoon', due_date: '2026-11-06', start_time: '15:00', end_time: '16:00' }));
    await createTask(ctx, task({ id: 'tb-sync-0001', title: 'Morning', due_date: '2026-11-06', start_time: '09:00', duration_min: 20 }));
    await createTask(ctx, task({ id: 'tb-sync-0003', title: 'Untimed', due_date: '2026-11-06' }));
    await createTask(ctx, task({ id: 'tb-sync-0004', title: 'Tomorrow', due_date: '2026-11-07', start_time: '09:00', end_time: '10:00' }));
    await setDay(ctx, 'tb-sync-0001', '2026-11-06', { status: 'done' });

    const feed = await buildSync(ctx, 14, 'W/"x"');
    expect(feed.today.blocks).toEqual([
      { id: 'tb-sync-0001', title: 'Morning', start_time: '09:00', end_time: null, duration_min: 20, status: 'done' },
      { id: 'tb-sync-0002', title: 'Afternoon', start_time: '15:00', end_time: '16:00', duration_min: 60, status: 'open' },
    ]);
    expect(feed.today.planned).toBe(3);
    expect(feed.today.done).toBe(1);
    expect(syncEtag(7, '2026-11-06', 14)).toMatch(/^W\/"7\.2026-11-06\.14\.\d+"$/);
  });
});

describe('the spreadsheet carries the times', () => {
  it('has them on repeating columns and one-off tasks', async () => {
    const db = await makeDb();
    const ctx = (await makeUser(db, makeClock())).ctx();
    await createTask(ctx, task({ id: 'tb-sheet-001', title: 'Gym', due_date: '2026-11-02', recur: 'daily', start_time: '18:00', end_time: '19:00' }));
    await createTask(ctx, task({ id: 'tb-sheet-002', title: 'Call', due_date: '2026-11-03', start_time: '11:00' }));
    const sheet = await sheetView(ctx, '2026-11-02', '2026-11-08');
    expect(sheet.columns[0]).toMatchObject({ title: 'Gym', start_time: '18:00', end_time: '19:00' });
    expect(sheet.days[1].tasks[0]).toMatchObject({ title: 'Call', start_time: '11:00', end_time: null });
  });
});

let n = 0;
async function signUp() {
  const r = await call(register.POST, 'POST', '/api/v1/auth/register', {
    body: { email: `tb-${++n}@example.com`, password: 'correct horse 9' },
    headers: { 'x-forwarded-for': `10.7.0.${n}` },
  });
  expect(r.status).toBe(201);
  const profile = (await call(me.GET, 'GET', '/api/v1/me', { token: r.body.token })).body;
  return { token: r.body.token as string, aiId: profile.ai_access_id as string };
}

describe('over HTTP', () => {
  beforeAll(async () => {
    await migrate(await getDb());
  });

  it('creates, patches and reads back start/end; a bad pair is rejected with the problem on end_time', async () => {
    const a = await signUp();
    const today = new Date().toISOString().slice(0, 10);
    const created = await call(tasks.POST, 'POST', '/api/v1/tasks', { token: a.token, body: { id: 'tb-http-0001', title: 'Write', due_date: today, start_time: '08:00', end_time: '09:00' } });
    expect([created.status, created.body.start_time, created.body.end_time, created.body.duration_min]).toEqual([201, '08:00', '09:00', 60]);

    const bad = await call(tasks.POST, 'POST', '/api/v1/tasks', { token: a.token, body: { title: 'Nope', due_date: today, start_time: '09:00', end_time: '08:00' } });
    expect([bad.status, bad.body.error.code]).toEqual([400, 'validation_error']);
    expect(bad.body.error.issues).toEqual([{ path: 'end_time', message: 'End time must be after the start time' }]);

    const patched = await call(taskById.PATCH, 'PATCH', '/api/v1/tasks/tb-http-0001', { token: a.token, body: { end_time: '10:30' } }, { id: 'tb-http-0001' });
    expect([patched.status, patched.body.end_time, patched.body.duration_min]).toEqual([200, '10:30', 150]);
    const clash = await call(taskById.PATCH, 'PATCH', '/api/v1/tasks/tb-http-0001', { token: a.token, body: { start_time: '11:00' } }, { id: 'tb-http-0001' });
    expect([clash.status, clash.body.error.code]).toEqual([422, 'invalid_time_range']);
    const dur = await call(taskById.PATCH, 'PATCH', '/api/v1/tasks/tb-http-0001', { token: a.token, body: { duration_min: 20 } }, { id: 'tb-http-0001' });
    expect([dur.status, dur.body.error.code]).toEqual([422, 'duration_follows_times']);

    const feed = await call(sync.GET, 'GET', '/api/v1/sync?days=14', { token: a.token });
    expect(feed.body.today.blocks).toEqual([{ id: 'tb-http-0001', title: 'Write', start_time: '08:00', end_time: '10:30', duration_min: 150, status: 'open' }]);
    await call(taskDay.PUT, 'PUT', `/api/v1/tasks/tb-http-0001/days/${today}`, { token: a.token, body: { status: 'done' } }, { id: 'tb-http-0001', date: today });
    const after = await call(sync.GET, 'GET', '/api/v1/sync?days=14', { token: a.token });
    expect(after.body.today.blocks[0].status).toBe('done');
  });

  it('an ETag from before the feed grew a field never gets a 304', async () => {
    const a = await signUp();
    const first = await call(sync.GET, 'GET', '/api/v1/sync?days=14', { token: a.token });
    const etag = first.headers.get('etag')!;
    const same = await call(sync.GET, 'GET', '/api/v1/sync?days=14', { token: a.token, headers: { 'if-none-match': etag } });
    expect(same.status).toBe(304);
    const old = etag.replace(/\.\d+"$/, '"'); // what the previous version of the server sent
    expect(old).not.toBe(etag);
    const stale = await call(sync.GET, 'GET', '/api/v1/sync?days=14', { token: a.token, headers: { 'if-none-match': old } });
    expect(stale.status).toBe(200);
    expect(stale.body.today.blocks).toEqual([]);
  });

  it('Claude can set the times, and the manual says how', async () => {
    const a = await signUp();
    const today = new Date().toISOString().slice(0, 10);
    const made = await call(aiTasks.POST, 'POST', `/api/ai/tasks?uid=${a.aiId}`, { body: { title: 'Plan week', due_date: today, start_time: '07:30', end_time: '08:00' } });
    expect([made.status, made.body.start_time, made.body.end_time, made.body.duration_min]).toEqual([201, '07:30', '08:00', 30]);
    const manual = await call(aiManual.GET, 'GET', `/api/ai?uid=${a.aiId}`);
    expect(Object.keys(manual.body.fields)).toEqual(expect.arrayContaining(['start_time', 'end_time']));
    expect(JSON.stringify(manual.body.rules)).toContain('time block');
  });
});
