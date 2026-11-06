import { createClient, type Client } from '@libsql/client';
import { migrate } from '../lib/migrate';
import type { Actor, Ctx } from '../lib/ctx';
import { registerUser } from '../lib/services/auth';
import type { TaskCreate } from '../lib/validation';
import { taskCreate } from '../lib/validation';

export async function makeDb(): Promise<Client> {
  const db = createClient({ url: ':memory:' });
  await migrate(db);
  return db;
}

/** A controllable clock; `ctx.now()` follows it. */
export function makeClock(iso = '2026-11-06T12:00:00Z') {
  let t = new Date(iso);
  return {
    now: () => new Date(t),
    set(next: string) {
      t = new Date(next);
    },
  };
}
export type Clock = ReturnType<typeof makeClock>;

export interface TestUser {
  id: string;
  email: string;
  ctx: (actor?: Actor) => Ctx;
}

let counter = 0;

export async function makeUser(db: Client, clock: Clock, opts: { email?: string; tz?: string } = {}): Promise<TestUser> {
  const email = opts.email ?? `user${++counter}@example.com`;
  const tz = opts.tz ?? 'UTC';
  const { user } = await registerUser(db, { email, password: 'correct horse 9', timezone: tz }, { ip: `ip-${counter}`, now: clock.now() });
  return {
    id: user.id,
    email,
    ctx: (actor = 'app') => ({ db, userId: user.id, tz, actor, now: clock.now }),
  };
}

export const BASE = 'http://localhost';

export interface CallOpts {
  token?: string;
  body?: unknown;
  headers?: Record<string, string>;
}

/** Invoke a Next route handler directly with a real Request; returns status, parsed body and headers. */
export async function call(
  handler: unknown,
  method: string,
  path: string,
  opts: CallOpts = {},
  params?: Record<string, string>,
): Promise<{ status: number; body: any; headers: Headers }> {
  const headers: Record<string, string> = { 'content-type': 'application/json', ...opts.headers };
  if (opts.token) headers.authorization = `Bearer ${opts.token}`;
  const req = new Request(BASE + path, { method, headers, body: opts.body === undefined ? undefined : JSON.stringify(opts.body) });
  const res: Response = await (handler as (r: Request, c: unknown) => Promise<Response>)(req, { params: Promise.resolve(params ?? {}) });
  const text = await res.text();
  let body: unknown = text;
  try {
    body = text ? JSON.parse(text) : null;
  } catch {
    // plain-text responses (e.g. the markdown manual) stay as text
  }
  return { status: res.status, body, headers: res.headers };
}

/** Parse through the real schema so tests use the same defaults the API applies. */
export const task = (input: Partial<TaskCreate> & { title: string; due_date: string }): TaskCreate => taskCreate.parse(input);
