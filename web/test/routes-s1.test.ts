import { afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
import { migrate } from '../lib/migrate';

vi.stubEnv('TURSO_DATABASE_URL', ':memory:');

import * as aiManual from '../app/api/ai/route';
import * as aiTasks from '../app/api/ai/tasks/route';
import * as aiTaskById from '../app/api/ai/tasks/[id]/route';
import * as aiRestore from '../app/api/ai/tasks/[id]/restore/route';
import * as aiTop from '../app/api/ai/days/[date]/top/route';
import * as aiSearch from '../app/api/ai/search/route';
import * as aiHabits from '../app/api/ai/habits/route';
import * as aiReview from '../app/api/ai/review/route';
import * as aiActivity from '../app/api/ai/activity/route';
import * as register from '../app/api/v1/auth/register/route';
import * as login from '../app/api/v1/auth/login/route';
import * as me from '../app/api/v1/me/route';
import * as mePassword from '../app/api/v1/me/password/route';
import * as meExport from '../app/api/v1/me/export/route';
import * as tasks from '../app/api/v1/tasks/route';
import * as taskById from '../app/api/v1/tasks/[id]/route';
import * as taskRestore from '../app/api/v1/tasks/[id]/restore/route';
import * as top from '../app/api/v1/days/[date]/top/route';
import * as search from '../app/api/v1/search/route';
import * as activity from '../app/api/v1/activity/route';
import * as sync from '../app/api/v1/sync/route';
import * as habits from '../app/api/v1/habits/route';
import * as review from '../app/api/v1/review/route';
import { getDb } from '../lib/db';
import { call } from './helpers';

let n = 0;
interface Account {
  token: string;
  aiId: string;
  id: string;
}

async function signUp(tz = 'UTC'): Promise<Account> {
  const r = await call(register.POST, 'POST', '/api/v1/auth/register', {
    body: { email: `s1-${++n}@example.com`, password: 'correct horse 9', timezone: tz },
    headers: { 'x-forwarded-for': `10.3.0.${n}` },
  });
  expect(r.status).toBe(201);
  const profile = (await call(me.GET, 'GET', '/api/v1/me', { token: r.body.token })).body;
  return { token: r.body.token, aiId: profile.ai_access_id, id: profile.id };
}
const v1 = (a: Account, handler: unknown, method: string, path: string, body?: unknown, params?: Record<string, string>, headers?: Record<string, string>) =>
  call(handler, method, path, { token: a.token, body, headers }, params);
const ai = (a: Account, handler: unknown, method: string, path: string, body?: unknown, params?: Record<string, string>) =>
  call(handler, method, `${path}${path.includes('?') ? '&' : '?'}uid=${a.aiId}`, { body }, params);

const TODAY = new Date().toISOString().slice(0, 10); // accounts are UTC
const newTask = (a: Account, id: string, extra: Record<string, unknown> = {}) =>
  v1(a, tasks.POST, 'POST', '/api/v1/tasks', { id, title: `task ${id}`, due_date: TODAY, ...extra });

beforeAll(async () => {
  await migrate(await getDb());
});
afterEach(() => {
  vi.unstubAllEnvs();
  vi.stubEnv('TURSO_DATABASE_URL', ':memory:');
});

describe('weekday repeats over the API', () => {
  it('creates a weekly task and rejects bad weekday lists and weekdays on a one-off', async () => {
    const a = await signUp();
    const ok = await newTask(a, 'wk-task-0001', { recur: 'daily', recur_days: [1, 3, 5] });
    expect([ok.status, ok.body.recur_days]).toEqual([201, [1, 3, 5]]);
    for (const bad of [[0], [8], [], [1, 1], ['mon']]) {
      expect((await newTask(a, 'wk-bad-0001', { recur: 'daily', recur_days: bad })).status, JSON.stringify(bad)).toBe(400);
    }
    const oneOff = await newTask(a, 'wk-one-0001', { recur: 'none', recur_days: [1] });
    expect([oneOff.status, oneOff.body.error.code]).toEqual([422, 'invalid_recurrence']);
  });
});

describe("Today's Top 3 over the API", () => {
  it('sets the list, returns the day, and rejects >3, strangers’ tasks and signed-out calls', async () => {
    const a = await signUp();
    const b = await signUp();
    const ids = ['top-task-0001', 'top-task-0002', 'top-task-0003', 'top-task-0004'];
    for (const id of ids) await newTask(a, id);
    const params = { date: TODAY };

    const set = await v1(a, top.PUT, 'PUT', `/api/v1/days/${TODAY}/top`, { task_ids: [ids[1], ids[0]] }, params);
    expect(set.status).toBe(200);
    expect(set.body.top).toEqual([ids[1], ids[0]]);
    expect(set.body.tasks.find((t: { id: string }) => t.id === ids[1]).top_position).toBe(1);

    expect((await v1(a, top.PUT, 'PUT', `/api/v1/days/${TODAY}/top`, { task_ids: ids }, params)).status).toBe(400);
    expect((await v1(b, top.PUT, 'PUT', `/api/v1/days/${TODAY}/top`, { task_ids: [ids[0]] }, params)).status).toBe(404);
    expect((await call(top.PUT, 'PUT', `/api/v1/days/${TODAY}/top`, { body: { task_ids: [] } }, params)).status).toBe(401);
    expect((await v1(a, top.PUT, 'PUT', `/api/v1/days/${TODAY}/top`, { task_ids: [] }, params)).body.top).toEqual([]);
  });
});

describe('search, undo and the AI activity feed', () => {
  it('search needs 2+ characters, finds tasks, and is limited to 30 per minute', async () => {
    const a = await signUp();
    await newTask(a, 'srch-task-0001', { title: 'Quarterly invoice run' });
    expect((await v1(a, search.GET, 'GET', '/api/v1/search?q=a')).status).toBe(400);
    const r = await v1(a, search.GET, 'GET', '/api/v1/search?q=invoice');
    expect([r.status, r.body.items.map((t: { id: string }) => t.id), r.body.has_more]).toEqual([200, ['srch-task-0001'], false]);
    for (let i = 0; i < 29; i++) await v1(a, search.GET, 'GET', '/api/v1/search?q=invoice');
    expect((await v1(a, search.GET, 'GET', '/api/v1/search?q=invoice')).status).toBe(429);
  });

  it('delete then restore, and a stranger cannot restore it', async () => {
    const a = await signUp();
    const b = await signUp();
    await newTask(a, 'undo-task-0001');
    await v1(a, taskById.DELETE, 'DELETE', '/api/v1/tasks/undo-task-0001', undefined, { id: 'undo-task-0001' });
    expect((await v1(b, taskRestore.POST, 'POST', '/api/v1/tasks/undo-task-0001/restore', undefined, { id: 'undo-task-0001' })).status).toBe(404);
    const back = await v1(a, taskRestore.POST, 'POST', '/api/v1/tasks/undo-task-0001/restore', undefined, { id: 'undo-task-0001' });
    expect([back.status, back.body.id]).toEqual([200, 'undo-task-0001']);
  });

  it('the user sees what Claude changed (and not their own edits), and can undo an AI delete', async () => {
    const a = await signUp();
    await newTask(a, 'mine-task-0001'); // app edit: not logged
    const made = await ai(a, aiTasks.POST, 'POST', '/api/ai/tasks', { title: 'AI made this', due_date: 'today' });
    await ai(a, aiTaskById.DELETE, 'DELETE', `/api/ai/tasks/${made.body.id}`, undefined, { id: made.body.id });

    const feed = await v1(a, activity.GET, 'GET', '/api/v1/activity');
    expect(feed.body.items.map((i: { kind: string }) => i.kind)).toEqual(['deleted', 'created']);
    expect(feed.body.items[0]).toMatchObject({ title: 'AI made this', actor: 'ai', task_id: made.body.id });

    const restored = await v1(a, taskRestore.POST, 'POST', `/api/v1/tasks/${made.body.id}/restore`, undefined, { id: made.body.id });
    expect(restored.status).toBe(200);
    // the same feed is available to the assistant itself
    expect((await ai(a, aiActivity.GET, 'GET', '/api/ai/activity')).body.items.length).toBe(2); // restore by the app user is not logged
  });
});

describe('the phone feed (/sync)', () => {
  it('returns an ETag, answers 304 when nothing changed, and a new ETag after any change', async () => {
    const a = await signUp();
    await newTask(a, 'sync-task-0001', { alarm_time: '23:59' });
    const first = await v1(a, sync.GET, 'GET', '/api/v1/sync?days=14');
    expect(first.status).toBe(200);
    const etag = first.headers.get('etag')!;
    expect(etag).toMatch(/^W\/"\d+\.\d{4}-\d{2}-\d{2}\.14"$/);
    expect(first.body).toMatchObject({ version: etag, window: { truncated: false }, today: { planned: 1 } });
    expect(first.body.alarms.map((x: { task_id: string }) => x.task_id)).toEqual(['sync-task-0001']);

    const again = await v1(a, sync.GET, 'GET', '/api/v1/sync?days=14', undefined, undefined, { 'if-none-match': etag });
    expect([again.status, again.body, again.headers.get('etag')]).toEqual([304, null, etag]);

    await newTask(a, 'sync-task-0002');
    const changed = await v1(a, sync.GET, 'GET', '/api/v1/sync?days=14', undefined, undefined, { 'if-none-match': etag });
    expect(changed.status).toBe(200);
    expect(changed.headers.get('etag')).not.toBe(etag);

    // a timezone change also moves "today", so the phone must refetch
    const etag2 = changed.headers.get('etag')!;
    await v1(a, me.PATCH, 'PATCH', '/api/v1/me', { timezone: 'Pacific/Kiritimati' });
    const tz = await v1(a, sync.GET, 'GET', '/api/v1/sync?days=14', undefined, undefined, { 'if-none-match': etag2 });
    expect(tz.status).toBe(200);
  });

  it('validates days, requires a session, and refuses an AI id', async () => {
    const a = await signUp();
    expect((await v1(a, sync.GET, 'GET', '/api/v1/sync?days=15')).status).toBe(400);
    expect((await v1(a, sync.GET, 'GET', '/api/v1/sync?days=0')).status).toBe(400);
    expect((await call(sync.GET, 'GET', '/api/v1/sync')).status).toBe(401);
    expect((await call(sync.GET, 'GET', `/api/v1/sync?uid=${a.aiId}`)).status).toBe(401);
  });

  it('only counts full payloads against the 120/hour limit, never a 304', async () => {
    const a = await signUp();
    const first = await v1(a, sync.GET, 'GET', '/api/v1/sync');
    const etag = first.headers.get('etag')!;
    for (let i = 0; i < 130; i++) expect((await v1(a, sync.GET, 'GET', '/api/v1/sync', undefined, undefined, { 'if-none-match': etag })).status).toBe(304);
  });
});

describe('habits and review over the API', () => {
  it('return their shapes and are scoped to the caller', async () => {
    const a = await signUp();
    const b = await signUp();
    await newTask(a, 'habit-task-0001', { recur: 'daily', due_date: '2026-10-01' });
    const h = await v1(a, habits.GET, 'GET', '/api/v1/habits?days=14');
    expect(h.body.habits).toHaveLength(1);
    expect(h.body.habits[0]).toMatchObject({ task_id: 'habit-task-0001', last7: expect.any(Array) });
    expect((await v1(b, habits.GET, 'GET', '/api/v1/habits')).body.habits).toEqual([]);
    expect((await v1(a, habits.GET, 'GET', '/api/v1/habits?days=3')).status).toBe(400);

    const r = await v1(a, review.GET, 'GET', '/api/v1/review');
    expect(r.status).toBe(200);
    expect(r.body).toMatchObject({ totals: expect.any(Object), days: expect.any(Array), plan_prompt: expect.any(String) });
    expect((await v1(b, review.GET, 'GET', '/api/v1/review')).body.totals.planned).toBe(0);
    expect((await v1(a, review.GET, 'GET', '/api/v1/review?week_start=2099-01-01')).status).toBe(400);
  });
});

describe('account endpoints', () => {
  it('change password: needs the current password, keeps this session, revokes the others', async () => {
    const a = await signUp();
    const email = (await call(me.GET, 'GET', '/api/v1/me', { token: a.token })).body.email;
    const other = (await call(login.POST, 'POST', '/api/v1/auth/login', { body: { email, password: 'correct horse 9' } })).body.token;

    expect((await v1(a, mePassword.POST, 'POST', '/api/v1/me/password', { current_password: 'nope nope nope', new_password: 'another good password' })).status).toBe(403);
    expect((await v1(a, mePassword.POST, 'POST', '/api/v1/me/password', { current_password: 'correct horse 9', new_password: 'short' })).status).toBe(400);
    expect((await v1(a, mePassword.POST, 'POST', '/api/v1/me/password', { current_password: 'correct horse 9', new_password: 'another good password' })).status).toBe(200);

    expect((await call(me.GET, 'GET', '/api/v1/me', { token: a.token })).status).toBe(200);
    expect((await call(me.GET, 'GET', '/api/v1/me', { token: other })).status).toBe(401);
    expect((await call(login.POST, 'POST', '/api/v1/auth/login', { body: { email, password: 'another good password' } })).status).toBe(200);
  });

  it('export is a JSON attachment without secrets', async () => {
    const a = await signUp();
    await newTask(a, 'exp-task-0001');
    const res = await meExport.GET(new Request('http://localhost/api/v1/me/export', { headers: { authorization: `Bearer ${a.token}` } }));
    expect(res.headers.get('content-disposition')).toMatch(/attachment; filename="taskrelay-export\.json"/);
    const text = await res.text();
    expect(JSON.parse(text).tasks.map((t: { id: string }) => t.id)).toEqual(['exp-task-0001']);
    expect(text).not.toMatch(/password_hash|ai_access_id|token_hash/);
  });

  it('delete account: wrong password 403; right password deletes everything, clears the cookie and signs out', async () => {
    const a = await signUp();
    await newTask(a, 'del-task-0001');
    expect((await v1(a, me.DELETE, 'DELETE', '/api/v1/me', { password: 'wrong wrong' })).status).toBe(403);
    const del = await v1(a, me.DELETE, 'DELETE', '/api/v1/me', { password: 'correct horse 9' });
    expect(del.status).toBe(200);
    expect(del.headers.get('set-cookie')).toMatch(/Max-Age=0/);
    expect((await call(me.GET, 'GET', '/api/v1/me', { token: a.token })).status).toBe(401);
    expect((await ai(a, aiManual.GET, 'GET', '/api/ai')).status).toBe(401); // the AI id died with the account
    const left = await (await getDb()).execute({ sql: 'SELECT COUNT(*) AS n FROM tasks WHERE user_id = ?', args: [a.id] });
    expect(Number(left.rows[0].n)).toBe(0);
  });
});

describe('AI API: weekday names, Top 3, search, habits, review, restore', () => {
  it('accepts weekdays by name and defaults recur to "daily"', async () => {
    const a = await signUp();
    const named = await ai(a, aiTasks.POST, 'POST', '/api/ai/tasks', { title: 'Gym', due_date: 'today', recur_days: ['mon', 'Wednesday', 'FRI'] });
    expect([named.status, named.body.recur, named.body.recur_days, named.body.repeat_on]).toEqual([201, 'daily', [1, 3, 5], ['Mon', 'Wed', 'Fri']]);
    const weekdays = await ai(a, aiTasks.POST, 'POST', '/api/ai/tasks', { title: 'Standup', due_date: 'today', recur_days: 'weekdays' });
    expect(weekdays.body.recur_days).toEqual([1, 2, 3, 4, 5]);
    const weekends = await ai(a, aiTasks.POST, 'POST', '/api/ai/tasks', { title: 'Long run', due_date: 'today', recur_days: 'weekends' });
    expect(weekends.body.repeat_on).toEqual(['Sat', 'Sun']);
    const everyDay = await ai(a, aiTaskById.PATCH, 'PATCH', `/api/ai/tasks/${named.body.id}`, { recur_days: 'daily' }, { id: named.body.id });
    expect(everyDay.body.recur_days).toBeNull();

    const bad = await ai(a, aiTasks.POST, 'POST', '/api/ai/tasks', { title: 'x', due_date: 'today', recur_days: ['someday'] });
    expect([bad.status, bad.body.error.code]).toEqual([400, 'invalid_recur_days']);
    expect(bad.body.error.message).toContain('mon..sun');
  });

  it('sets the Top 3, searches, lists habits and the review, and restores a deleted task', async () => {
    const a = await signUp();
    const t = (await ai(a, aiTasks.POST, 'POST', '/api/ai/tasks', { title: 'Write proposal', due_date: 'today' })).body;
    const h = (await ai(a, aiTasks.POST, 'POST', '/api/ai/tasks', { title: 'Meditate', due_date: 'today', recur: 'daily' })).body;

    const topRes = await ai(a, aiTop.PUT, 'PUT', '/api/ai/days/today/top', { task_ids: [t.id] }, { date: 'today' });
    expect([topRes.status, topRes.body.top.map((x: { title: string }) => x.title)]).toEqual([200, ['Write proposal']]);
    expect((await ai(a, aiTop.PUT, 'PUT', '/api/ai/days/today/top', { task_ids: [1, 2] }, { date: 'today' })).status).toBe(400);

    expect((await ai(a, aiSearch.GET, 'GET', '/api/ai/search?q=proposal')).body.tasks.map((x: { title: string }) => x.title)).toEqual(['Write proposal']);
    expect((await ai(a, aiHabits.GET, 'GET', '/api/ai/habits')).body.habits.map((x: { title: string }) => x.title)).toEqual(['Meditate']);
    expect((await ai(a, aiReview.GET, 'GET', '/api/ai/review')).body).toMatchObject({ totals: expect.any(Object), plan_prompt: expect.any(String) });

    await ai(a, aiTaskById.DELETE, 'DELETE', `/api/ai/tasks/${h.id}`, undefined, { id: h.id });
    const back = await ai(a, aiRestore.POST, 'POST', `/api/ai/tasks/${h.id}/restore`, undefined, { id: h.id });
    expect([back.status, back.body.title]).toEqual([200, 'Meditate']);
  });

  it('the manual documents every new capability', async () => {
    const a = await signUp();
    const m = (await ai(a, aiManual.GET, 'GET', '/api/ai')).body;
    const urls: string = m.endpoints.map((e: { method: string; url: string }) => `${e.method} ${e.url}`).join('\n');
    for (const needle of ['PUT ', '/api/ai/days/{date}/top', '/api/ai/search', '/api/ai/habits', '/api/ai/review', '/api/ai/activity', '/api/ai/tasks/{id}/restore']) {
      expect(urls, needle).toContain(needle);
    }
    expect(Object.keys(m.fields)).toEqual(expect.arrayContaining(['recur_days', 'repeat_on', 'top_position', 'updated_by']));
    expect(m.rules.join(' ')).toMatch(/Top 3/);
    expect(JSON.stringify(m)).not.toContain('@example.com');
  });
});

describe('scope isolation for the new routes', () => {
  it('an AI id is refused on every new app route; a session is refused on every new AI route', async () => {
    const a = await signUp();
    const appRoutes: Array<[unknown, string, string]> = [
      [search.GET, 'GET', '/api/v1/search?q=ab'], [activity.GET, 'GET', '/api/v1/activity'], [sync.GET, 'GET', '/api/v1/sync'],
      [habits.GET, 'GET', '/api/v1/habits'], [review.GET, 'GET', '/api/v1/review'], [meExport.GET, 'GET', '/api/v1/me/export'],
      [mePassword.POST, 'POST', '/api/v1/me/password'], [me.DELETE, 'DELETE', '/api/v1/me'],
    ];
    for (const [handler, method, path] of appRoutes) {
      const viaUid = await call(handler, method, `${path}${path.includes('?') ? '&' : '?'}uid=${a.aiId}`);
      const viaBearer = await call(handler, method, path, { headers: { authorization: `Bearer ${a.aiId}` } });
      expect([viaUid.status, viaBearer.status], `${method} ${path}`).toEqual([401, 401]);
    }
    const aiRoutes: Array<[unknown, string, string]> = [
      [aiSearch.GET, 'GET', '/api/ai/search?q=ab'], [aiHabits.GET, 'GET', '/api/ai/habits'], [aiReview.GET, 'GET', '/api/ai/review'],
      [aiActivity.GET, 'GET', '/api/ai/activity'],
    ];
    for (const [handler, method, path] of aiRoutes) {
      expect((await call(handler, method, path, { token: a.token })).status, path).toBe(401);
      expect((await call(handler, method, `${path}${path.includes('?') ? '&' : '?'}uid=${a.token}`)).status, path).toBe(401);
    }
  });

  it('user B sees none of user A’s tasks through search, sync, habits, review or activity', async () => {
    const a = await signUp();
    const b = await signUp();
    await newTask(a, 'iso-task-0001', { title: 'confidential plan', alarm_time: '10:00', recur: 'daily' });
    await ai(a, aiTasks.POST, 'POST', '/api/ai/tasks', { title: 'confidential ai task', due_date: 'today' });

    expect((await v1(b, search.GET, 'GET', '/api/v1/search?q=confidential')).body.items).toEqual([]);
    const feed = (await v1(b, sync.GET, 'GET', '/api/v1/sync')).body;
    expect([feed.alarms, feed.today.planned]).toEqual([[], 0]);
    expect((await v1(b, habits.GET, 'GET', '/api/v1/habits')).body.habits).toEqual([]);
    expect((await v1(b, review.GET, 'GET', '/api/v1/review')).body.totals.planned).toBe(0);
    expect((await v1(b, activity.GET, 'GET', '/api/v1/activity')).body.items).toEqual([]);
    expect((await v1(b, taskRestore.POST, 'POST', '/api/v1/tasks/iso-task-0001/restore', undefined, { id: 'iso-task-0001' })).status).toBe(404);
  });
});
