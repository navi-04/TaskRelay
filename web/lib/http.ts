import { z, ZodError, type ZodType } from 'zod';
import type { Ctx } from './ctx';
import { getDb } from './db';
import { ApiError, badRequest, forbidden, unauthorized } from './errors';
import { dateStr } from './validation';
import { authenticateAi, authenticateSession, type SessionUser } from './services/auth';
import { enforce } from './services/rateLimit';
import { todayFor } from './time';

export const SESSION_COOKIE = 'tr_session';

/** Headers for every /api/ai/* response: the AI id can sit in the URL, so keep it out of caches, referrers and search. */
export const AI_HEADERS = {
  'Cache-Control': 'no-store',
  'Referrer-Policy': 'no-referrer',
  'X-Robots-Tag': 'noindex, nofollow',
} as const;

export function json(data: unknown, status = 200, headers: HeadersInit = {}): Response {
  return Response.json(data, { status, headers: { 'Cache-Control': 'no-store', ...headers } });
}

export function errorResponse(e: unknown, headers: HeadersInit = {}): Response {
  if (e instanceof ApiError) {
    const extra: Record<string, string> = e.status === 429 ? { 'Retry-After': '60' } : {};
    return json({ error: { code: e.code, message: e.message } }, e.status, { ...headers, ...extra });
  }
  if (e instanceof ZodError) {
    return json(
      {
        error: {
          code: 'validation_error',
          message: z.prettifyError(e),
          issues: e.issues.map((i) => ({ path: i.path.join('.'), message: i.message })),
        },
      },
      400,
      headers,
    );
  }
  // Log the message only: request URLs may contain an AI access id.
  console.error('unhandled error:', e instanceof Error ? e.message : 'unknown');
  return json({ error: { code: 'internal', message: 'Something went wrong' } }, 500, headers);
}

/** Run a route body and turn any thrown error into the standard `{ error: { code, message } }` response. */
export async function handle(fn: () => Promise<Response>, headers: HeadersInit = {}): Promise<Response> {
  try {
    return await fn();
  } catch (e) {
    return errorResponse(e, headers);
  }
}

export async function readBody<T>(req: Request, schema: ZodType<T>): Promise<T> {
  let raw: unknown;
  try {
    raw = await req.json();
  } catch {
    throw badRequest('Body must be valid JSON', 'invalid_json');
  }
  return schema.parse(raw);
}

export const queryDate = (url: URL, name: string): string | undefined => {
  const v = url.searchParams.get(name);
  return v == null ? undefined : dateStr.parse(v);
};

/** An integer query parameter within [min, max]; `fallback` when absent. */
export function queryInt(url: URL, name: string, min: number, max: number, fallback: number): number {
  const raw = url.searchParams.get(name);
  if (raw == null || raw === '') return fallback;
  const n = Number(raw);
  if (!Number.isInteger(n) || n < min || n > max) throw badRequest(`${name} must be a whole number from ${min} to ${max}`, 'invalid_query');
  return n;
}

/** The search text: 2-100 characters after trimming. */
export function querySearch(url: URL): string {
  const q = (url.searchParams.get('q') ?? '').trim();
  if (q.length < 2 || q.length > 100) throw badRequest('q must be 2 to 100 characters', 'invalid_query');
  return q;
}

export function clientIp(req: Request): string {
  return req.headers.get('x-forwarded-for')?.split(',')[0].trim() || req.headers.get('x-real-ip') || 'unknown';
}

const bearer = (req: Request): string | null => {
  const h = req.headers.get('authorization');
  return h?.toLowerCase().startsWith('bearer ') ? h.slice(7).trim() : null;
};

function cookie(req: Request, name: string): string | null {
  for (const part of (req.headers.get('cookie') ?? '').split(';')) {
    const [k, ...v] = part.trim().split('=');
    if (k === name) return decodeURIComponent(v.join('='));
  }
  return null;
}

const versionParts = (v: string) => v.split(/[.+-]/).slice(0, 3).map((n) => Number.parseInt(n, 10) || 0);

/** Old installed apps are told to update (426) once the server sets MIN_APP_VERSION above them. */
function checkAppVersion(req: Request) {
  const min = process.env.MIN_APP_VERSION;
  const have = req.headers.get('x-app-version');
  if (!min || !have) return;
  const [a, b] = [versionParts(have), versionParts(min)];
  for (let i = 0; i < 3; i++) {
    if (a[i] !== b[i]) {
      if (a[i] < b[i]) throw new ApiError(426, 'upgrade_required', 'Please update TaskRelay to continue');
      return;
    }
  }
}

export interface AppAuth {
  ctx: Ctx;
  user: SessionUser;
  token: string;
}

/** Auth for /api/v1/*: a session as `Authorization: Bearer` (apps) or the httpOnly cookie (web). AI ids are refused here. */
export async function authApp(req: Request): Promise<AppAuth> {
  const url = new URL(req.url);
  if (url.searchParams.has('uid')) throw unauthorized('AI access IDs are not valid here');
  checkAppVersion(req);

  const fromBearer = bearer(req);
  const token = fromBearer ?? cookie(req, SESSION_COOKIE);
  if (!token) throw unauthorized();

  const db = await getDb();
  const user = await authenticateSession(db, token, new Date());
  if (!user) throw unauthorized();

  // Cookie sessions are ambient, so state-changing requests must come from our own origin.
  if (!fromBearer && !['GET', 'HEAD', 'OPTIONS'].includes(req.method)) {
    const origin = req.headers.get('origin');
    if (!origin || new URL(origin).host !== url.host) throw forbidden('Cross-site request blocked', 'bad_origin');
  }
  return { ctx: { db, userId: user.id, tz: user.timezone, actor: 'app', now: () => new Date() }, user, token };
}

/** Auth for /api/ai/*: the AI access id as `?uid=`, `X-AI-Id`, or Bearer. Session tokens are not valid here. */
export async function authAi(req: Request): Promise<Ctx> {
  const url = new URL(req.url);
  const uid = url.searchParams.get('uid') ?? req.headers.get('x-ai-id') ?? bearer(req) ?? '';
  const db = await getDb();
  const now = new Date();
  const user = await authenticateAi(db, uid, now);
  if (req.method === 'GET') await enforce(db, `ai:read:${user.id}`, 300, 60, now);
  else await enforce(db, `ai:write:${user.id}`, 60, 60, now);
  return { db, userId: user.id, tz: user.timezone, actor: 'ai', now: () => new Date() };
}

export const todayOf = (ctx: Ctx) => todayFor(ctx.now(), ctx.tz);

const COOKIE_MAX_AGE_SEC = 90 * 86_400;

/** The web UI keeps its session in an httpOnly cookie so page scripts (and any XSS) never see the token. */
export function sessionCookie(req: Request, token: string): string {
  const secure = new URL(req.url).protocol === 'https:' ? '; Secure' : '';
  return `${SESSION_COOKIE}=${encodeURIComponent(token)}; Path=/; HttpOnly; SameSite=Lax; Max-Age=${COOKIE_MAX_AGE_SEC}${secure}`;
}

export const clearedSessionCookie = (req: Request): string => sessionCookie(req, '').replace(/Max-Age=\d+/, 'Max-Age=0');

/** Web clients send `x-tr-web: 1` on login/register to get the cookie instead of a token in the body. */
export const isWebClient = (req: Request): boolean => req.headers.get('x-tr-web') === '1';

/** JSON response for /api/ai/*, with the no-store / no-referrer / noindex headers. */
export const aiJson = (data: unknown, status = 200): Response => json(data, status, AI_HEADERS);

/** Wrap an /api/ai/* route: authenticate by AI id, rate limit, and always attach the AI headers (even to errors). */
export const aiRoute = (req: Request, fn: (ctx: Ctx, url: URL) => Promise<Response>): Promise<Response> =>
  handle(async () => fn(await authAi(req), new URL(req.url)), AI_HEADERS);
