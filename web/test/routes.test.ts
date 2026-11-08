import { afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
import { migrate } from '../lib/migrate';

// Route handlers read the database through getDb(); point it at a private in-memory db for this file.
vi.stubEnv('TURSO_DATABASE_URL', ':memory:');

import * as health from '../app/api/health/route';
import * as register from '../app/api/v1/auth/register/route';
import * as loginRoute from '../app/api/v1/auth/login/route';
import * as logoutRoute from '../app/api/v1/auth/logout/route';
import * as me from '../app/api/v1/me/route';
import * as tasks from '../app/api/v1/tasks/route';
import * as taskMove from '../app/api/v1/tasks/move/route';
import * as taskById from '../app/api/v1/tasks/[id]/route';
import * as taskDay from '../app/api/v1/tasks/[id]/days/[date]/route';
import * as stats from '../app/api/v1/stats/route';
import * as labels from '../app/api/v1/labels/route';
import * as settings from '../app/api/v1/settings/route';
import { getDb } from '../lib/db';
import { BASE, call } from './helpers';

let n = 0;
async function signUp() {
  const email = `route${++n}@example.com`;
  const r = await call(register.POST, 'POST', '/api/v1/auth/register', {
    body: { email, password: 'correct horse 9', timezone: 'UTC' },
    headers: { 'x-forwarded-for': `10.0.0.${n}` },
  });
  expect(r.status).toBe(201);
  return { token: r.body.token as string, email };
}

const newTask = (token: string, extra: Record<string, unknown> = {}) =>
  call(tasks.POST, 'POST', '/api/v1/tasks', { token, body: { title: 'a task', due_date: '2026-11-06', ...extra } });

beforeAll(async () => {
  await migrate(await getDb());
});
afterEach(() => {
  vi.unstubAllEnvs();
  vi.stubEnv('TURSO_DATABASE_URL', ':memory:');
});

describe('basics', () => {
  it('health reports ok', async () => {
    const r = await call(health.GET, 'GET', '/api/health');
    expect([r.status, r.body]).toEqual([200, { ok: true }]);
  });

  it('every error uses { error: { code, message } }', async () => {
    const r = await call(tasks.GET, 'GET', '/api/v1/tasks');
    expect(r.status).toBe(401);
    expect(r.body).toEqual({ error: { code: 'unauthorized', message: expect.any(String) } });
  });

  it('login works and logout revokes the session', async () => {
    const { token, email } = await signUp();
    const login = await call(loginRoute.POST, 'POST', '/api/v1/auth/login', { body: { email, password: 'correct horse 9' } });
    expect(login.status).toBe(200);
    expect((await call(me.GET, 'GET', '/api/v1/me', { token: login.body.token })).body.email).toBe(email);
    await call(logoutRoute.POST, 'POST', '/api/v1/auth/logout', { token });
    expect((await call(me.GET, 'GET', '/api/v1/me', { token })).status).toBe(401);
  });

  it('GET /me exposes the AI access id to its owner', async () => {
    const { token } = await signUp();
    const r = await call(me.GET, 'GET', '/api/v1/me', { token });
    expect(r.body.ai_access_id).toHaveLength(43);
    expect(r.body.ai_access_enabled).toBe(true);
  });
});

describe('task lifecycle through the API', () => {
  it('create -> list for a day -> complete -> overdue/stats shapes', async () => {
    const { token } = await signUp();
    const created = await newTask(token, { id: 'task-route-0001', recur: 'daily' });
    expect(created.status).toBe(201);

    const day = await call(tasks.GET, 'GET', '/api/v1/tasks?date=2031-03-10', { token });
    expect(day.status).toBe(200);
    expect(day.body.tasks.map((t: { id: string }) => t.id)).toEqual(['task-route-0001']);
    expect(day.body).toMatchObject({ date: '2031-03-10', summary: { planned: 1, done: 0 } });
    expect(day.body.overdue).toBeUndefined(); // only for today

    const done = await call(taskDay.PUT, 'PUT', '/api/v1/tasks/task-route-0001/days/2031-03-10', { token, body: { status: 'done' } }, { id: 'task-route-0001', date: '2031-03-10' });
    expect(done.body.status).toBe('done');

    const s = await call(stats.GET, 'GET', '/api/v1/stats?from=2031-03-07&to=2031-03-10', { token });
    expect(s.status).toBe(200);
    expect(s.body.days).toHaveLength(4);
    expect(s.body.days.find((d: { date: string }) => d.date === '2031-03-10')).toMatchObject({ planned: 1, done: 1 });
  });

  it('posting the same id twice is safe', async () => {
    const { token } = await signUp();
    expect((await newTask(token, { id: 'task-twice-0001' })).status).toBe(201);
    expect((await newTask(token, { id: 'task-twice-0001' })).status).toBe(201);
    const day = await call(tasks.GET, 'GET', '/api/v1/tasks?date=2026-11-06', { token });
    expect(day.body.tasks).toHaveLength(1);
  });

  it('DELETE honours scope', async () => {
    const { token } = await signUp();
    await newTask(token, { id: 'task-scope-0001', due_date: '2026-11-01', recur: 'daily' });
    const del = await call(taskById.DELETE, 'DELETE', '/api/v1/tasks/task-scope-0001?scope=day:2026-11-03', { token }, { id: 'task-scope-0001' });
    expect(del.status).toBe(200);
    const d3 = await call(tasks.GET, 'GET', '/api/v1/tasks?date=2026-11-03', { token });
    expect(d3.body.tasks).toHaveLength(0);
    const bad = await call(taskById.DELETE, 'DELETE', '/api/v1/tasks/task-scope-0001?scope=whenever', { token }, { id: 'task-scope-0001' });
    expect(bad.status).toBe(400);
  });
});

describe('validation', () => {
  it('rejects impossible dates, unknown fields and bad bounds with 400', async () => {
    const { token } = await signUp();
    expect((await newTask(token, { due_date: '2026-02-30' })).status).toBe(400);
    expect((await newTask(token, { surprise: true })).status).toBe(400);
    expect((await newTask(token, { duration_min: 0 })).status).toBe(400);
    expect((await newTask(token, { alarm_time: '25:99' })).status).toBe(400);
    const r = await newTask(token, { title: '   ' });
    expect(r.status).toBe(400);
    expect(r.body.error.code).toBe('validation_error');
  });

  it('caps bulk moves at 50 ids and stats ranges at 62 days', async () => {
    const { token } = await signUp();
    const ids = Array.from({ length: 51 }, (_, i) => `task-bulk-${String(i).padStart(4, '0')}`);
    expect((await call(taskMove.POST, 'POST', '/api/v1/tasks/move', { token, body: { ids, to: '2026-11-06' } })).status).toBe(400);
    const r = await call(stats.GET, 'GET', '/api/v1/stats?from=2026-01-01&to=2026-12-31', { token });
    expect([r.status, r.body.error.code]).toEqual([400, 'range_too_large']);
  });

  it('rejects malformed JSON', async () => {
    const { token } = await signUp();
    const req = new Request(`${BASE}/api/v1/tasks`, { method: 'POST', headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' }, body: '{nope' });
    const res = await tasks.POST(req);
    expect(res.status).toBe(400);
    expect((await res.json()).error.code).toBe('invalid_json');
  });
});

describe('isolation matrix: user B against user A', () => {
  it("404 for every route that takes A's task id", async () => {
    const a = await signUp();
    const b = await signUp();
    await newTask(a.token, { id: 'task-owned-by-a1' });
    const id = { id: 'task-owned-by-a1' };

    const results = await Promise.all([
      call(taskById.GET, 'GET', '/api/v1/tasks/task-owned-by-a1', { token: b.token }, id),
      call(taskById.PATCH, 'PATCH', '/api/v1/tasks/task-owned-by-a1', { token: b.token, body: { title: 'hacked' } }, id),
      call(taskById.DELETE, 'DELETE', '/api/v1/tasks/task-owned-by-a1', { token: b.token }, id),
      call(taskDay.PUT, 'PUT', '/api/v1/tasks/task-owned-by-a1/days/2026-11-06', { token: b.token, body: { status: 'done' } }, { ...id, date: '2026-11-06' }),
    ]);
    expect(results.map((r) => r.status)).toEqual([404, 404, 404, 404]);
    // and A still sees it, untouched
    const mine = await call(taskById.GET, 'GET', '/api/v1/tasks/task-owned-by-a1', { token: a.token }, id);
    expect(mine.body).toMatchObject({ title: 'a task', status: 'open' });
  });

  it("B can't claim A's task id on create (generic 409), nor use A's labels (400)", async () => {
    const a = await signUp();
    const b = await signUp();
    await newTask(a.token, { id: 'task-claimed-001' });
    const claim = await newTask(b.token, { id: 'task-claimed-001', title: 'mine' });
    expect([claim.status, claim.body.error.code]).toEqual([409, 'id_in_use']);

    const aLabels = (await call(labels.GET, 'GET', '/api/v1/labels', { token: a.token })).body;
    const stolen = await newTask(b.token, { type_id: aLabels.types[0].id });
    expect([stolen.status, stolen.body.error.code]).toEqual([400, 'invalid_label']);
  });

  it('lists, labels and settings are scoped to the caller', async () => {
    const a = await signUp();
    const b = await signUp();
    await newTask(a.token);
    expect((await call(tasks.GET, 'GET', '/api/v1/tasks?date=2026-11-06', { token: b.token })).body.tasks).toHaveLength(0);
    await call(settings.PATCH, 'PATCH', '/api/v1/settings', { token: a.token, body: { daily_count_limit: 3 } });
    expect((await call(settings.GET, 'GET', '/api/v1/settings', { token: b.token })).body.daily_count_limit).toBe(10);
  });
});

describe('AI ids and cookies on the app API', () => {
  it('refuses an AI id on /api/v1, even alongside a valid session', async () => {
    const { token } = await signUp();
    const aiId = (await call(me.GET, 'GET', '/api/v1/me', { token })).body.ai_access_id;
    expect((await call(tasks.GET, 'GET', `/api/v1/tasks?uid=${aiId}`)).status).toBe(401);
    expect((await call(tasks.GET, 'GET', `/api/v1/tasks?uid=${aiId}`, { token })).status).toBe(401);
    expect((await call(tasks.GET, 'GET', '/api/v1/tasks', { headers: { authorization: `Bearer ${aiId}` } })).status).toBe(401);
  });

  it('cookie sessions work for reads but state-changing requests must be same-origin', async () => {
    const { token } = await signUp();
    const cookie = { cookie: `tr_session=${token}` };
    expect((await call(tasks.GET, 'GET', '/api/v1/tasks?date=2026-11-06', { headers: cookie })).status).toBe(200);
    const noOrigin = await call(tasks.POST, 'POST', '/api/v1/tasks', { headers: cookie, body: { title: 'x', due_date: '2026-11-06' } });
    expect([noOrigin.status, noOrigin.body.error.code]).toEqual([403, 'bad_origin']);
    const crossSite = await call(tasks.POST, 'POST', '/api/v1/tasks', { headers: { ...cookie, origin: 'https://evil.example' }, body: { title: 'x', due_date: '2026-11-06' } });
    expect(crossSite.status).toBe(403);
    const sameOrigin = await call(tasks.POST, 'POST', '/api/v1/tasks', { headers: { ...cookie, origin: BASE }, body: { title: 'x', due_date: '2026-11-06' } });
    expect(sameOrigin.status).toBe(201);
  });
});

describe('web cookie sessions', () => {
  const creds = () => ({ email: `web${++n}@example.com`, password: 'correct horse 9' });

  it('web clients get an httpOnly cookie and never a token in the body; logout clears the cookie and the session', async () => {
    const r = await call(register.POST, 'POST', '/api/v1/auth/register', {
      body: creds(),
      headers: { 'x-tr-web': '1', 'x-forwarded-for': `10.2.0.${n}` },
    });
    expect(r.status).toBe(201);
    expect(r.body.token).toBeUndefined();
    const setCookie = r.headers.get('set-cookie')!;
    expect(setCookie).toMatch(/^tr_session=[^;]+/);
    expect(setCookie).toMatch(/HttpOnly/);
    expect(setCookie).toMatch(/SameSite=Lax/);
    expect(setCookie).not.toMatch(/Secure/); // plain http (local dev)

    const cookie = { cookie: setCookie.split(';')[0] };
    expect((await call(me.GET, 'GET', '/api/v1/me', { headers: cookie })).status).toBe(200);

    const out = await call(logoutRoute.POST, 'POST', '/api/v1/auth/logout', { headers: { ...cookie, origin: BASE } });
    expect(out.status).toBe(200);
    expect(out.headers.get('set-cookie')).toMatch(/Max-Age=0/);
    expect((await call(me.GET, 'GET', '/api/v1/me', { headers: cookie })).status).toBe(401);
  });

  it('marks the cookie Secure over https', async () => {
    const res = await register.POST(
      new Request('https://app.example.com/api/v1/auth/register', {
        method: 'POST',
        headers: { 'content-type': 'application/json', 'x-tr-web': '1', 'x-forwarded-for': '10.2.9.9' },
        body: JSON.stringify(creds()),
      }),
    );
    expect(res.headers.get('set-cookie')).toMatch(/; Secure/);
  });

  it('apps (no x-tr-web header) still get the token in the body and no cookie', async () => {
    const r = await call(register.POST, 'POST', '/api/v1/auth/register', { body: creds(), headers: { 'x-forwarded-for': `10.2.1.${n}` } });
    expect(r.body.token).toHaveLength(43);
    expect(r.headers.get('set-cookie')).toBeNull();
  });
});

describe('app version gate', () => {
  it('tells old apps to update (426) once MIN_APP_VERSION is raised', async () => {
    const { token } = await signUp();
    vi.stubEnv('MIN_APP_VERSION', '1.2.0');
    const old = await call(tasks.GET, 'GET', '/api/v1/tasks?date=2026-11-06', { token, headers: { 'x-app-version': '1.1.9+3' } });
    expect([old.status, old.body.error.code]).toEqual([426, 'upgrade_required']);
    expect((await call(tasks.GET, 'GET', '/api/v1/tasks?date=2026-11-06', { token, headers: { 'x-app-version': '1.2.0' } })).status).toBe(200);
    expect((await call(tasks.GET, 'GET', '/api/v1/tasks?date=2026-11-06', { token })).status).toBe(200); // header absent: not blocked
  });
});
