import { beforeEach, describe, expect, it } from 'vitest';
import type { Client } from '@libsql/client';
import {
  authenticateAi,
  authenticateSession,
  getMe,
  login,
  logout,
  regenerateAiAccess,
  registerUser,
  setAiEnabled,
  setPassword,
} from '../lib/services/auth';
import { listLabels } from '../lib/services/labels';
import { getSettings } from '../lib/services/settings';
import { ApiError } from '../lib/errors';
import { makeClock, makeDb, type Clock } from './helpers';

let db: Client;
let clock: Clock;
const env = (ip = '1.1.1.1') => ({ ip, now: clock.now() });
const PW = 'correct horse 9';

beforeEach(async () => {
  db = await makeDb();
  clock = makeClock('2026-11-06T12:00:00Z');
});

const apiError = async (p: Promise<unknown>) => {
  const e = await p.then(
    () => null,
    (err) => err,
  );
  expect(e).toBeInstanceOf(ApiError);
  return e as ApiError;
};

describe('register', () => {
  it('creates the user with settings, default labels and a working session', async () => {
    const { token, user } = await registerUser(db, { email: 'A@Example.com ', password: PW, timezone: 'Asia/Kolkata' }, env());
    expect(user.email).toBe('a@example.com');
    expect((await authenticateSession(db, token, clock.now()))?.id).toBe(user.id);
    const ctx = { db, userId: user.id, tz: user.timezone, actor: 'app' as const, now: clock.now };
    const labels = await listLabels(ctx);
    expect(labels.types).toHaveLength(8);
    expect(labels.priorities.map((p) => p.label)).toEqual(['Low', 'Medium', 'High', 'Critical']);
    expect((await getSettings(ctx)).daily_time_limit_min).toBe(480);
    expect(await getMe(db, user.id)).toMatchObject({ ai_access_enabled: true });
  });

  it('rejects a duplicate email regardless of case', async () => {
    await registerUser(db, { email: 'dup@example.com', password: PW }, env());
    const e = await apiError(registerUser(db, { email: 'DUP@example.com', password: PW }, env('2.2.2.2')));
    expect([e.status, e.code]).toEqual([409, 'email_taken']);
  });

  it('limits registrations per IP', async () => {
    for (let i = 0; i < 5; i++) await registerUser(db, { email: `u${i}@example.com`, password: PW }, env('9.9.9.9'));
    const e = await apiError(registerUser(db, { email: 'u6@example.com', password: PW }, env('9.9.9.9')));
    expect(e.status).toBe(429);
  });
});

describe('login', () => {
  beforeEach(async () => {
    await registerUser(db, { email: 'me@example.com', password: PW }, env('5.5.5.5'));
  });

  it('gives the same error for an unknown email and a wrong password', async () => {
    const unknown = await apiError(login(db, { email: 'nobody@example.com', password: PW }, env()));
    const wrong = await apiError(login(db, { email: 'me@example.com', password: 'wrong password' }, env()));
    expect([unknown.status, unknown.code, unknown.message]).toEqual([wrong.status, wrong.code, wrong.message]);
    expect(wrong.status).toBe(401);
  });

  it('locks the email out after 5 failures, even for the right password, until the window passes', async () => {
    for (let i = 0; i < 5; i++) await apiError(login(db, { email: 'me@example.com', password: 'nope-nope' }, env()));
    expect((await apiError(login(db, { email: 'me@example.com', password: PW }, env()))).status).toBe(429);
    clock.set('2026-11-06T12:16:00Z');
    expect((await login(db, { email: 'me@example.com', password: PW }, env())).token).toBeTruthy();
  });

  it('is case-insensitive on email', async () => {
    expect((await login(db, { email: ' ME@example.com', password: PW }, env())).user.email).toBe('me@example.com');
  });
});

describe('sessions', () => {
  it('expires after 90 days and logout revokes', async () => {
    const { token } = await registerUser(db, { email: 's@example.com', password: PW }, env());
    clock.set('2027-02-01T12:00:00Z'); // ~87 days: still valid (and slides forward)
    expect(await authenticateSession(db, token, clock.now())).not.toBeNull();
    clock.set('2027-06-01T12:00:00Z'); // >90 days since last use
    expect(await authenticateSession(db, token, clock.now())).toBeNull();

    const fresh = (await registerUser(db, { email: 't@example.com', password: PW }, env('3.3.3.3'))).token;
    await logout(db, fresh);
    expect(await authenticateSession(db, fresh, clock.now())).toBeNull();
  });

  it('changing the password signs out every session', async () => {
    const { token, user } = await registerUser(db, { email: 'p@example.com', password: PW }, env());
    await setPassword(db, user.id, 'a brand new password');
    expect(await authenticateSession(db, token, clock.now())).toBeNull();
    expect((await apiError(login(db, { email: 'p@example.com', password: PW }, env()))).status).toBe(401);
    expect((await login(db, { email: 'p@example.com', password: 'a brand new password' }, env())).token).toBeTruthy();
  });

  it('rejects garbage tokens', async () => {
    expect(await authenticateSession(db, 'not-a-token', clock.now())).toBeNull();
    expect(await authenticateSession(db, '', clock.now())).toBeNull();
  });
});

describe('AI access id', () => {
  it('resolves a valid id, rejects unknown (401) and switched-off (403)', async () => {
    const { user } = await registerUser(db, { email: 'ai@example.com', password: PW }, env());
    const { ai_access_id } = await getMe(db, user.id);
    expect(ai_access_id.length).toBeGreaterThanOrEqual(40);
    expect((await authenticateAi(db, ai_access_id, clock.now())).id).toBe(user.id);
    expect((await apiError(authenticateAi(db, 'x'.repeat(43), clock.now()))).status).toBe(401);
    await setAiEnabled(db, user.id, false);
    const off = await apiError(authenticateAi(db, ai_access_id, clock.now()));
    expect([off.status, off.code]).toEqual([403, 'ai_access_disabled']);
  });

  it('regenerating kills the old id immediately', async () => {
    const { user } = await registerUser(db, { email: 'r@example.com', password: PW }, env());
    const oldId = (await getMe(db, user.id)).ai_access_id;
    const newId = await regenerateAiAccess(db, user.id);
    expect(newId).not.toBe(oldId);
    expect((await apiError(authenticateAi(db, oldId, clock.now()))).status).toBe(401);
    expect((await authenticateAi(db, newId, clock.now())).id).toBe(user.id);
  });

  it('a session token is not an AI id', async () => {
    const { token } = await registerUser(db, { email: 'x@example.com', password: PW }, env());
    expect((await apiError(authenticateAi(db, token, clock.now()))).status).toBe(401);
  });

  it('records last use at most once a minute', async () => {
    const { user } = await registerUser(db, { email: 'l@example.com', password: PW }, env());
    const id = (await getMe(db, user.id)).ai_access_id;
    await authenticateAi(db, id, clock.now());
    const first = (await getMe(db, user.id)).ai_last_used_at;
    clock.set('2026-11-06T12:00:30Z');
    await authenticateAi(db, id, clock.now());
    expect((await getMe(db, user.id)).ai_last_used_at).toBe(first);
    clock.set('2026-11-06T12:02:00Z');
    await authenticateAi(db, id, clock.now());
    expect((await getMe(db, user.id)).ai_last_used_at).not.toBe(first);
  });
});
