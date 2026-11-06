import { beforeEach, describe, expect, it } from 'vitest';
import type { Client } from '@libsql/client';
import { ApiError } from '../lib/errors';
import { changePassword, deleteAccount, exportAccount } from '../lib/services/account';
import { authenticateSession, login, sessionTokenHash } from '../lib/services/auth';
import { setTop } from '../lib/services/focus';
import { createLabel } from '../lib/services/labels';
import { createTask, deleteTask, setDay } from '../lib/services/tasks';
import { makeClock, makeDb, makeUser, task, type Clock, type TestUser } from './helpers';

let db: Client;
let clock: Clock;
let u: TestUser;

beforeEach(async () => {
  db = await makeDb();
  clock = makeClock('2026-11-06T12:00:00Z');
  u = await makeUser(db, clock);
});

const apiError = async (p: Promise<unknown>) => {
  const e = await p.then(() => null, (err) => err);
  expect(e).toBeInstanceOf(ApiError);
  return e as ApiError;
};

const env = () => ({ ip: '9.9.9.9', now: clock.now() });

describe('change password', () => {
  it('signs out every other session but keeps the one that asked', async () => {
    const other = (await login(db, { email: u.email, password: u.password }, env())).token;
    await changePassword(db, u.id, { current_password: u.password, new_password: 'a brand new password' }, sessionTokenHash(u.token), clock.now());

    expect(await authenticateSession(db, u.token, clock.now())).not.toBeNull();
    expect(await authenticateSession(db, other, clock.now())).toBeNull();
    expect((await apiError(login(db, { email: u.email, password: u.password }, env()))).status).toBe(401);
    expect((await login(db, { email: u.email, password: 'a brand new password' }, env())).token).toBeTruthy();
  });

  it('a wrong current password is 403 (not 401, the session is fine) and lockout comes after 5 tries', async () => {
    const attempt = () => changePassword(db, u.id, { current_password: 'wrong wrong', new_password: 'whatever it is' }, sessionTokenHash(u.token), clock.now());
    for (let i = 0; i < 5; i++) {
      const e = await apiError(attempt());
      expect([e.status, e.code]).toEqual([403, 'wrong_password']);
    }
    expect((await apiError(attempt())).status).toBe(429);
    // even the right password is refused while locked out
    const locked = await apiError(changePassword(db, u.id, { current_password: u.password, new_password: 'whatever it is' }, sessionTokenHash(u.token), clock.now()));
    expect(locked.status).toBe(429);
    clock.set('2026-11-06T12:16:00Z');
    await changePassword(db, u.id, { current_password: u.password, new_password: 'whatever it is' }, sessionTokenHash(u.token), clock.now());
  });
});

describe('delete account', () => {
  it('needs the right password', async () => {
    expect((await apiError(deleteAccount(db, u.id, 'not my password', clock.now()))).code).toBe('wrong_password');
    expect(await authenticateSession(db, u.token, clock.now())).not.toBeNull(); // nothing was deleted
  });

  it('removes every row of the user in every table, and nobody else’s', async () => {
    const other = await makeUser(db, clock);
    const keep = await createTask(other.ctx(), task({ title: 'keep me', due_date: '2026-11-06' }));
    await setDay(other.ctx(), keep.id, '2026-11-06', { status: 'done' });

    const a = await createTask(u.ctx('ai'), task({ title: 'a', due_date: '2026-11-06' }));
    const b = await createTask(u.ctx(), task({ title: 'b', due_date: '2026-11-01', recur: 'daily' }));
    await setDay(u.ctx(), b.id, '2026-11-06', { status: 'done' });
    await setTop(u.ctx(), '2026-11-06', [a.id]);
    await createLabel(u.ctx(), { kind: 'type', label: 'Extra' });
    await deleteTask(u.ctx('ai'), a.id, 'all'); // soft-deleted rows must go too
    await login(db, { email: u.email, password: 'wrong' }, env()).catch(() => undefined); // leaves a rate-limit row

    await deleteAccount(db, u.id, u.password, clock.now());

    // Every table that has a user_id column is empty for this user (catches tables added later that forget deletion)
    const tables = (await db.execute(`SELECT name FROM sqlite_schema WHERE type = 'table' AND name NOT LIKE 'sqlite_%'`)).rows.map((r) => String(r.name));
    const withUserId: string[] = [];
    for (const t of tables) {
      const cols = (await db.execute(`PRAGMA table_info(${t})`)).rows.map((r) => String(r.name));
      if (cols.includes('user_id')) withUserId.push(t);
    }
    expect(withUserId).toEqual(expect.arrayContaining(['tasks', 'task_days', 'labels', 'settings', 'sessions', 'day_focus', 'activity']));
    for (const t of withUserId) {
      const n = Number((await db.execute({ sql: `SELECT COUNT(*) AS n FROM ${t} WHERE user_id = ?`, args: [u.id] })).rows[0].n);
      expect(n, `${t} still has rows`).toBe(0);
    }
    expect(Number((await db.execute({ sql: 'SELECT COUNT(*) AS n FROM users WHERE id = ?', args: [u.id] })).rows[0].n)).toBe(0);
    const keys = (await db.execute({ sql: 'SELECT key FROM rate_limits WHERE key LIKE ? OR key = ?', args: [`%:${u.id}`, `login:email:${u.email}`] })).rows;
    expect(keys).toHaveLength(0);

    expect(await authenticateSession(db, u.token, clock.now())).toBeNull(); // signed out
    expect((await apiError(login(db, { email: u.email, password: u.password }, env()))).status).toBe(401);
    // the other user is untouched
    expect(Number((await db.execute({ sql: 'SELECT COUNT(*) AS n FROM tasks WHERE user_id = ?', args: [other.id] })).rows[0].n)).toBe(1);
    expect(Number((await db.execute({ sql: 'SELECT COUNT(*) AS n FROM task_days WHERE user_id = ?', args: [other.id] })).rows[0].n)).toBe(1);
  });
});

describe('export', () => {
  it('contains the user’s data including deleted tasks, and none of the secrets', async () => {
    const t = await createTask(u.ctx(), task({ title: 'visible', due_date: '2026-11-06' }));
    const gone = await createTask(u.ctx(), task({ title: 'deleted one', due_date: '2026-11-06' }));
    await setDay(u.ctx(), t.id, '2026-11-06', { status: 'done', note: 'nice' });
    await deleteTask(u.ctx(), gone.id, 'all');
    await createTask((await makeUser(db, clock)).ctx(), task({ title: 'not mine', due_date: '2026-11-06' }));

    const out = await exportAccount(db, u.id, clock.now());
    expect(out.user).toMatchObject({ id: u.id, email: u.email });
    expect((out.tasks as Array<{ title: string }>).map((x) => x.title).sort()).toEqual(['deleted one', 'visible']);
    expect(out.task_days).toHaveLength(1);
    expect(out.labels).toHaveLength(12);
    expect(out.settings).toMatchObject({ estimation_mode: 'time' });

    const text = JSON.stringify(out);
    expect(text).not.toMatch(/password_hash|ai_access_id|token_hash|scrypt\$/);
    expect(text).not.toContain('not mine');
  });

  it('is limited to 5 per hour', async () => {
    for (let i = 0; i < 5; i++) await exportAccount(db, u.id, clock.now());
    expect((await apiError(exportAccount(db, u.id, clock.now()))).status).toBe(429);
  });
});
