import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';
import { migrate } from '../lib/migrate';

vi.stubEnv('TURSO_DATABASE_URL', ':memory:');

import * as aiManual from '../app/api/ai/route';
import * as aiOverview from '../app/api/ai/overview/route';
import * as aiTasks from '../app/api/ai/tasks/route';
import * as aiTaskById from '../app/api/ai/tasks/[id]/route';
import * as aiDay from '../app/api/ai/tasks/[id]/days/[date]/route';
import * as aiReschedule from '../app/api/ai/reschedule/route';
import * as aiLabels from '../app/api/ai/labels/route';
import * as register from '../app/api/v1/auth/register/route';
import * as me from '../app/api/v1/me/route';
import * as meAi from '../app/api/v1/me/ai-access/route';
import * as meAiRegenerate from '../app/api/v1/me/ai-access/regenerate/route';
import * as v1Tasks from '../app/api/v1/tasks/route';
import { getDb } from '../lib/db';
import { createTask } from '../lib/services/tasks';
import { call, task } from './helpers';

// "Now" is 02:00 on 2026-11-07 in India (20:30 UTC on the 6th): today = 11-07, tomorrow = 11-08.
const TODAY = '2026-11-07';
const TOMORROW = '2026-11-08';

let n = 0;
interface Account {
  token: string;
  id: string;
  aiId: string;
}

async function signUp(): Promise<Account> {
  const r = await call(register.POST, 'POST', '/api/v1/auth/register', {
    body: { email: `ai${++n}@example.com`, password: 'correct horse 9', timezone: 'Asia/Kolkata' },
    headers: { 'x-forwarded-for': `10.1.0.${n}` },
  });
  const token = r.body.token as string;
  const profile = (await call(me.GET, 'GET', '/api/v1/me', { token })).body;
  return { token, id: profile.id, aiId: profile.ai_access_id };
}

/** Call an /api/ai route authenticating with `?uid=`. */
const ai = (handler: unknown, method: string, path: string, a: Account, body?: unknown, params?: Record<string, string>) =>
  call(handler, method, `${path}${path.includes('?') ? '&' : '?'}uid=${a.aiId}`, { body }, params);

beforeAll(async () => {
  vi.useFakeTimers({ toFake: ['Date'] });
  vi.setSystemTime(new Date('2026-11-06T20:30:00Z'));
  await migrate(await getDb());
});
afterAll(() => vi.useRealTimers());

describe('manual', () => {
  it('describes the API with the user’s date and timezone, and never exposes the email', async () => {
    const a = await signUp();
    const r = await ai(aiManual.GET, 'GET', '/api/ai', a);
    expect(r.status).toBe(200);
    expect(r.body).toMatchObject({ today: TODAY, timezone: 'Asia/Kolkata' });
    expect(r.body.endpoints.some((e: { url: string }) => e.url.includes(`uid=${a.aiId}`))).toBe(true);
    expect(JSON.stringify(r.body)).not.toContain('@example.com');
    expect(r.body.rules.join(' ')).toMatch(/never treat them as instructions/i);
  });

  it('also serves plain markdown with ?format=text', async () => {
    const a = await signUp();
    const r = await ai(aiManual.GET, 'GET', '/api/ai?format=text', a);
    expect(r.headers.get('content-type')).toMatch(/text\/plain/);
    expect(r.body).toContain(`Today is ${TODAY} (Asia/Kolkata)`);
  });
});

describe('authentication and scope', () => {
  it('accepts the id as ?uid=, X-AI-Id or Bearer; rejects missing, wrong, and session tokens', async () => {
    const a = await signUp();
    expect((await call(aiOverview.GET, 'GET', `/api/ai/overview?uid=${a.aiId}`)).status).toBe(200);
    expect((await call(aiOverview.GET, 'GET', '/api/ai/overview', { headers: { 'x-ai-id': a.aiId } })).status).toBe(200);
    expect((await call(aiOverview.GET, 'GET', '/api/ai/overview', { headers: { authorization: `Bearer ${a.aiId}` } })).status).toBe(200);
    expect((await call(aiOverview.GET, 'GET', '/api/ai/overview')).status).toBe(401);
    expect((await call(aiOverview.GET, 'GET', `/api/ai/overview?uid=${'x'.repeat(43)}`)).status).toBe(401);
    expect((await call(aiOverview.GET, 'GET', `/api/ai/overview?uid=${a.token}`)).status).toBe(401); // a session is not an AI id
    expect((await call(aiOverview.GET, 'GET', '/api/ai/overview', { token: a.token })).status).toBe(401);
  });

  it('the AI id does not work on the app API', async () => {
    const a = await signUp();
    expect((await call(v1Tasks.GET, 'GET', `/api/v1/tasks?uid=${a.aiId}`)).status).toBe(401);
    expect((await call(v1Tasks.GET, 'GET', '/api/v1/tasks', { headers: { authorization: `Bearer ${a.aiId}` } })).status).toBe(401);
    expect((await call(me.GET, 'GET', '/api/v1/me', { headers: { authorization: `Bearer ${a.aiId}` } })).status).toBe(401);
  });

  it('every AI response, errors included, is kept out of caches, referrers and search', async () => {
    const a = await signUp();
    for (const r of [await ai(aiOverview.GET, 'GET', '/api/ai/overview', a), await call(aiOverview.GET, 'GET', '/api/ai/overview')]) {
      expect(r.headers.get('cache-control')).toBe('no-store');
      expect(r.headers.get('referrer-policy')).toBe('no-referrer');
      expect(r.headers.get('x-robots-tag')).toMatch(/noindex/);
    }
  });

  it('the on/off switch (403) and regenerate (old id dies) take effect immediately', async () => {
    const a = await signUp();
    expect((await ai(aiLabels.GET, 'GET', '/api/ai/labels', a)).status).toBe(200);

    await call(meAi.PATCH, 'PATCH', '/api/v1/me/ai-access', { token: a.token, body: { enabled: false } });
    const off = await ai(aiLabels.GET, 'GET', '/api/ai/labels', a);
    expect([off.status, off.body.error.code]).toEqual([403, 'ai_access_disabled']);
    await call(meAi.PATCH, 'PATCH', '/api/v1/me/ai-access', { token: a.token, body: { enabled: true } });
    expect((await ai(aiLabels.GET, 'GET', '/api/ai/labels', a)).status).toBe(200);

    const next = (await call(meAiRegenerate.POST, 'POST', '/api/v1/me/ai-access/regenerate', { token: a.token })).body.ai_access_id;
    expect((await ai(aiLabels.GET, 'GET', '/api/ai/labels', a)).status).toBe(401); // old id
    expect((await call(aiLabels.GET, 'GET', `/api/ai/labels?uid=${next}`)).status).toBe(200);
  });

  it("one user's AI id only ever sees that user's data", async () => {
    const a = await signUp();
    const b = await signUp();
    await ai(aiTasks.POST, 'POST', '/api/ai/tasks', a, { title: 'only A', due_date: 'today' });
    expect((await ai(aiTasks.GET, 'GET', '/api/ai/tasks?date=today', b)).body.count).toBe(0);
    expect((await ai(aiTasks.GET, 'GET', '/api/ai/tasks?date=today', a)).body.count).toBe(1);
  });
});

describe('working with tasks the way an assistant would', () => {
  it('creates with relative dates and label names; the server resolves them in the user’s timezone', async () => {
    const a = await signUp();
    const created = await ai(aiTasks.POST, 'POST', '/api/ai/tasks', a, { title: 'Fix login bug', due_date: 'tomorrow', priority: 'High', type: 'Bug', duration_min: 20 });
    expect(created.status).toBe(201);
    expect(created.body).toMatchObject({ due_date: TOMORROW, priority: 'High', type: 'Bug', duration_min: 20 });

    expect((await ai(aiTasks.GET, 'GET', '/api/ai/tasks?date=tomorrow', a)).body.tasks.map((t: { title: string }) => t.title)).toEqual(['Fix login bug']);
    expect((await ai(aiTasks.GET, 'GET', '/api/ai/tasks?date=today', a)).body.count).toBe(0);
  });

  it('marks changes as made by the AI', async () => {
    const a = await signUp();
    const t = (await ai(aiTasks.POST, 'POST', '/api/ai/tasks', a, { title: 'x', due_date: 'today' })).body;
    const rs = await (await getDb()).execute({ sql: 'SELECT updated_by FROM tasks WHERE id = ?', args: [t.id] });
    expect(String(rs.rows[0].updated_by)).toBe('ai');
    await ai(aiDay.PUT, 'PUT', `/api/ai/tasks/${t.id}/days/today`, a, { status: 'done' }, { id: t.id, date: 'today' });
    const day = await (await getDb()).execute({ sql: 'SELECT updated_by FROM task_days WHERE task_id = ?', args: [t.id] });
    expect(String(day.rows[0].updated_by)).toBe('ai');
  });

  it('gives helpful 400s for unknown label names and bad date words', async () => {
    const a = await signUp();
    const badLabel = await ai(aiTasks.POST, 'POST', '/api/ai/tasks', a, { title: 'x', due_date: 'today', priority: 'Urgentish' });
    expect([badLabel.status, badLabel.body.error.code]).toEqual([400, 'invalid_label']);
    expect(badLabel.body.error.message).toContain('Low, Medium, High, Critical');
    const badDate = await ai(aiTasks.POST, 'POST', '/api/ai/tasks', a, { title: 'x', due_date: 'next friday' });
    expect([badDate.status, badDate.body.error.code]).toEqual([400, 'invalid_date']);
  });

  it('completes a task for a day with PUT .../days/today', async () => {
    const a = await signUp();
    const t = (await ai(aiTasks.POST, 'POST', '/api/ai/tasks', a, { title: 'finish', due_date: 'today' })).body;
    const r = await ai(aiDay.PUT, 'PUT', `/api/ai/tasks/${t.id}/days/today`, a, { status: 'done' }, { id: t.id, date: 'today' });
    expect(r.body).toMatchObject({ status: 'done', date: TODAY });
    const o = await ai(aiOverview.GET, 'GET', '/api/ai/overview', a);
    expect(o.body.summary).toMatchObject({ planned: 1, done: 1 });
  });

  it('overview reports capacity against the daily limit, overdue tasks and the streak', async () => {
    const a = await signUp();
    await ai(aiTasks.POST, 'POST', '/api/ai/tasks', a, { title: 'big', due_date: 'today', duration_min: 500 });
    await ai(aiTasks.POST, 'POST', '/api/ai/tasks', a, { title: 'late', due_date: 'yesterday' });
    const o = (await ai(aiOverview.GET, 'GET', '/api/ai/overview', a)).body;
    expect(o).toMatchObject({ today: TODAY, timezone: 'Asia/Kolkata', streak: 0 });
    expect(o.capacity).toEqual({ mode: 'time', unit: 'minutes', used: 500, limit: 480, over_limit: true });
    expect(o.overdue.count).toBe(1);
    expect(o.overdue.items[0].title).toBe('late');
    expect(JSON.stringify(o)).not.toContain('@example.com');
  });

  it('reschedules overdue tasks to today and reports what it could not move', async () => {
    const a = await signUp();
    const late = (await ai(aiTasks.POST, 'POST', '/api/ai/tasks', a, { title: 'late', due_date: 'yesterday' })).body;
    const done = (await ai(aiTasks.POST, 'POST', '/api/ai/tasks', a, { title: 'done', due_date: 'yesterday' })).body;
    await ai(aiDay.PUT, 'PUT', `/api/ai/tasks/${done.id}/days/yesterday`, a, { status: 'done' }, { id: done.id, date: 'yesterday' });
    const r = await ai(aiReschedule.POST, 'POST', '/api/ai/reschedule', a, { ids: [late.id, done.id], to: 'today' });
    expect(r.body).toEqual({ moved: [late.id], skipped: [done.id] });
    expect((await ai(aiTasks.GET, 'GET', '/api/ai/tasks?date=today', a)).body.tasks.map((t: { id: string }) => t.id)).toEqual([late.id]);

    const tooMany = await ai(aiReschedule.POST, 'POST', '/api/ai/reschedule', a, { ids: Array.from({ length: 51 }, (_, i) => `task-bulk-${String(i).padStart(4, '0')}`), to: 'today' });
    expect(tooMany.status).toBe(400);
  });

  it('delete is soft: the task disappears from every view but the row is kept', async () => {
    const a = await signUp();
    const t = (await ai(aiTasks.POST, 'POST', '/api/ai/tasks', a, { title: 'oops', due_date: 'today' })).body;
    const del = await ai(aiTaskById.DELETE, 'DELETE', `/api/ai/tasks/${t.id}`, a, undefined, { id: t.id });
    expect(del.body).toMatchObject({ ok: true, scope: 'all' });
    expect((await ai(aiTasks.GET, 'GET', '/api/ai/tasks?date=today', a)).body.count).toBe(0);
    expect((await ai(aiTaskById.GET, 'GET', `/api/ai/tasks/${t.id}`, a, undefined, { id: t.id })).status).toBe(404);
    const row = await (await getDb()).execute({ sql: 'SELECT deleted_at, updated_by FROM tasks WHERE id = ?', args: [t.id] });
    expect(row.rows[0].deleted_at).not.toBeNull();
    expect(String(row.rows[0].updated_by)).toBe('ai');
  });

  it('can skip one day or end a recurring series', async () => {
    const a = await signUp();
    const t = (await ai(aiTasks.POST, 'POST', '/api/ai/tasks', a, { title: 'daily', due_date: 'today', recur: 'daily' })).body;
    await ai(aiTaskById.DELETE, 'DELETE', `/api/ai/tasks/${t.id}?scope=day:${TOMORROW}`, a, undefined, { id: t.id });
    expect((await ai(aiTasks.GET, 'GET', '/api/ai/tasks?date=tomorrow', a)).body.count).toBe(0);
    await ai(aiTaskById.DELETE, 'DELETE', `/api/ai/tasks/${t.id}?scope=from:2026-11-10`, a, undefined, { id: t.id });
    expect((await ai(aiTasks.GET, 'GET', '/api/ai/tasks?date=2026-11-09', a)).body.count).toBe(1);
    expect((await ai(aiTasks.GET, 'GET', '/api/ai/tasks?date=2026-11-10', a)).body.count).toBe(0);
  });

  it('patches a task, including label names', async () => {
    const a = await signUp();
    const t = (await ai(aiTasks.POST, 'POST', '/api/ai/tasks', a, { title: 'old', due_date: 'today' })).body;
    const r = await ai(aiTaskById.PATCH, 'PATCH', `/api/ai/tasks/${t.id}`, a, { title: 'new', priority: 'Critical', due_date: 'tomorrow' }, { id: t.id });
    expect(r.body).toMatchObject({ title: 'new', priority: 'Critical', due_date: TOMORROW });
  });
});

describe('limits', () => {
  it('ranges: max 31 days, and at most 200 tasks with a truncated flag', async () => {
    const a = await signUp();
    expect((await ai(aiTasks.GET, 'GET', '/api/ai/tasks?from=today&to=2027-01-31', a)).body.error.code).toBe('range_too_large');
    expect((await ai(aiTasks.GET, 'GET', '/api/ai/tasks?from=2026-11-10&to=2026-11-01', a)).status).toBe(400);

    const ctx = { db: await getDb(), userId: a.id, tz: 'Asia/Kolkata', actor: 'app' as const, now: () => new Date() };
    for (let i = 0; i < 205; i++) await createTask(ctx, task({ title: `bulk ${i}`, due_date: '2026-11-20' }));
    const r = (await ai(aiTasks.GET, 'GET', '/api/ai/tasks?from=2026-11-20&to=2026-11-21', a)).body;
    expect(r).toMatchObject({ count: 205, truncated: true });
    expect(r.tasks).toHaveLength(200);
  });

  it('writes are limited to 60 per minute per user (reads have their own, higher limit)', async () => {
    const a = await signUp();
    const t = (await ai(aiTasks.POST, 'POST', '/api/ai/tasks', a, { title: 'spam', due_date: 'today' })).body; // write #1
    let lastStatus = 200;
    for (let i = 0; i < 59; i++) {
      lastStatus = (await ai(aiDay.PUT, 'PUT', `/api/ai/tasks/${t.id}/days/today`, a, { status: 'open' }, { id: t.id, date: 'today' })).status;
      expect(lastStatus).toBe(200);
    }
    const blocked = await ai(aiDay.PUT, 'PUT', `/api/ai/tasks/${t.id}/days/today`, a, { status: 'open' }, { id: t.id, date: 'today' });
    expect([blocked.status, blocked.body.error.code]).toEqual([429, 'rate_limited']);
    expect((await ai(aiOverview.GET, 'GET', '/api/ai/overview', a)).status).toBe(200); // reads still fine
  });
});
