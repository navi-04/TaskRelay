import type { Client, InStatement } from '@libsql/client';
import { createHash, randomBytes, scrypt as scryptCb, timingSafeEqual } from 'node:crypto';
import { ApiError, conflict, forbidden, tooMany } from '../errors';
import { seedLabelStatements } from './labels';
import { clear, enforce, hit, retryAfter } from './rateLimit';
import { bumpVersion } from './version';

export interface UserDto {
  id: string;
  email: string;
  timezone: string;
}

/** The authenticated user of a session; `data_version` is the change counter the phone feed's ETag uses. */
export interface SessionUser extends UserDto {
  data_version: number;
}

export interface MeDto extends UserDto {
  ai_access_id: string;
  ai_access_enabled: boolean;
  ai_last_used_at: string | null;
}

const SESSION_DAYS = 90;
const DAY_MS = 86_400_000;

// ───────────────────────────── passwords ─────────────────────────────

const SCRYPT = { N: 16384, r: 8, p: 1, keylen: 64 };

function scryptAsync(password: string, salt: Buffer, n: number, r: number, p: number, keylen: number): Promise<Buffer> {
  return new Promise((resolve, reject) =>
    scryptCb(password, salt, keylen, { N: n, r, p, maxmem: 64 * 1024 * 1024 }, (err, key) => (err ? reject(err) : resolve(key))),
  );
}

export async function hashPassword(password: string): Promise<string> {
  const salt = randomBytes(16);
  const key = await scryptAsync(password, salt, SCRYPT.N, SCRYPT.r, SCRYPT.p, SCRYPT.keylen);
  return ['scrypt', SCRYPT.N, SCRYPT.r, SCRYPT.p, salt.toString('base64url'), key.toString('base64url')].join('$');
}

export async function verifyPassword(password: string, stored: string): Promise<boolean> {
  const [alg, n, r, p, salt, hash] = stored.split('$');
  if (alg !== 'scrypt') return false;
  const expected = Buffer.from(hash, 'base64url');
  const actual = await scryptAsync(password, Buffer.from(salt, 'base64url'), Number(n), Number(r), Number(p), expected.length);
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}

// Verified against when the email is unknown, so timing and the error are identical either way.
let dummyHash: Promise<string> | undefined;
const getDummyHash = () => (dummyHash ??= hashPassword('not-a-real-password'));

// ───────────────────────────── sessions ─────────────────────────────

const sha256 = (s: string) => createHash('sha256').update(s).digest('hex');

/** The stored identifier of a session token (the raw token is never stored). */
export const sessionTokenHash = sha256;

function sessionStatement(userId: string, now: Date): { token: string; statement: InStatement } {
  const token = randomBytes(32).toString('base64url');
  return {
    token,
    statement: {
      sql: 'INSERT INTO sessions (token_hash, user_id, expires_at, last_used) VALUES (?, ?, ?, ?)',
      args: [sha256(token), userId, new Date(now.getTime() + SESSION_DAYS * DAY_MS).toISOString(), now.toISOString()],
    },
  };
}

/** The signed-in user for a session token, or null. Extends the session (sliding) at most once a day. */
export async function authenticateSession(db: Client, token: string, now: Date): Promise<SessionUser | null> {
  if (!token) return null;
  const rs = await db.execute({
    sql: `SELECT s.expires_at, s.last_used, u.id, u.email, u.timezone, u.data_version
          FROM sessions s JOIN users u ON u.id = s.user_id WHERE s.token_hash = ?`,
    args: [sha256(token)],
  });
  if (rs.rows.length === 0) return null;
  const r = rs.rows[0];
  if (Date.parse(String(r.expires_at)) <= now.getTime()) {
    await db.execute({ sql: 'DELETE FROM sessions WHERE token_hash = ?', args: [sha256(token)] });
    return null;
  }
  if (now.getTime() - Date.parse(String(r.last_used)) > DAY_MS) {
    await db.execute({
      sql: 'UPDATE sessions SET last_used = ?, expires_at = ? WHERE token_hash = ?',
      args: [now.toISOString(), new Date(now.getTime() + SESSION_DAYS * DAY_MS).toISOString(), sha256(token)],
    });
  }
  return { id: String(r.id), email: String(r.email), timezone: String(r.timezone), data_version: Number(r.data_version) };
}

export async function logout(db: Client, token: string): Promise<void> {
  await db.execute({ sql: 'DELETE FROM sessions WHERE token_hash = ?', args: [sha256(token)] });
}

export async function revokeAllSessions(db: Client, userId: string): Promise<void> {
  await db.execute({ sql: 'DELETE FROM sessions WHERE user_id = ?', args: [userId] });
}

/**
 * Change a password and sign the user out everywhere, except (optionally) the session that asked for the change.
 * Pass `keepTokenHash` (see `sessionTokenHash`) to keep that one session signed in.
 */
export async function setPassword(db: Client, userId: string, newPassword: string, keepTokenHash?: string): Promise<void> {
  const hash = await hashPassword(newPassword);
  await db.batch(
    [
      { sql: 'UPDATE users SET password_hash = ? WHERE id = ?', args: [hash, userId] },
      keepTokenHash
        ? { sql: 'DELETE FROM sessions WHERE user_id = ? AND token_hash <> ?', args: [userId, keepTokenHash] }
        : { sql: 'DELETE FROM sessions WHERE user_id = ?', args: [userId] },
    ],
    'write',
  );
}

// ───────────────────────────── register / login ─────────────────────────────

export const newAiAccessId = () => randomBytes(32).toString('base64url');

interface Env {
  ip: string;
  now: Date;
}

export async function registerUser(
  db: Client,
  input: { email: string; password: string; timezone?: string },
  env: Env,
): Promise<{ token: string; user: UserDto }> {
  await enforce(db, `register:ip:${env.ip}`, 5, 3600, env.now);
  const email = input.email.trim().toLowerCase();
  const existing = await db.execute({ sql: 'SELECT 1 FROM users WHERE email = ?', args: [email] });
  if (existing.rows.length > 0) throw conflict('An account with this email already exists', 'email_taken');

  const id = crypto.randomUUID();
  const timezone = input.timezone ?? 'UTC';
  const nowIso = env.now.toISOString();
  const { token, statement } = sessionStatement(id, env.now);
  try {
    await db.batch(
      [
        {
          sql: `INSERT INTO users (id, email, password_hash, timezone, ai_access_id, created_at) VALUES (?, ?, ?, ?, ?, ?)`,
          args: [id, email, await hashPassword(input.password), timezone, newAiAccessId(), nowIso],
        },
        { sql: 'INSERT INTO settings (user_id) VALUES (?)', args: [id] },
        ...seedLabelStatements(id, nowIso),
        statement,
      ],
      'write',
    );
  } catch (e) {
    // Lost a race on the UNIQUE(email) constraint.
    if (String(e instanceof Error ? e.message : e).includes('UNIQUE')) throw conflict('An account with this email already exists', 'email_taken');
    throw e;
  }
  return { token, user: { id, email, timezone } };
}

const LOGIN_EMAIL_LIMIT = 5;
const LOGIN_IP_LIMIT = 20;
const LOGIN_WINDOW_SEC = 15 * 60;

export async function login(
  db: Client,
  input: { email: string; password: string },
  env: Env,
): Promise<{ token: string; user: UserDto }> {
  const email = input.email.trim().toLowerCase();
  const emailKey = `login:email:${email}`;
  const ipKey = `login:ip:${env.ip}`;
  const wait = Math.max(
    await retryAfter(db, emailKey, LOGIN_EMAIL_LIMIT, LOGIN_WINDOW_SEC, env.now),
    await retryAfter(db, ipKey, LOGIN_IP_LIMIT, LOGIN_WINDOW_SEC, env.now),
  );
  if (wait > 0) throw tooMany(wait);

  const rs = await db.execute({ sql: 'SELECT id, email, timezone, password_hash FROM users WHERE email = ?', args: [email] });
  const row = rs.rows[0];
  const ok = await verifyPassword(input.password, row ? String(row.password_hash) : await getDummyHash());
  if (!row || !ok) {
    await hit(db, emailKey, LOGIN_WINDOW_SEC, env.now);
    await hit(db, ipKey, LOGIN_WINDOW_SEC, env.now);
    throw new ApiError(401, 'invalid_credentials', 'Wrong email or password');
  }
  await clear(db, emailKey);
  const { token, statement } = sessionStatement(String(row.id), env.now);
  await db.execute(statement);
  return { token, user: { id: String(row.id), email: String(row.email), timezone: String(row.timezone) } };
}

// ───────────────────────────── account / AI access ─────────────────────────────

export async function getMe(db: Client, userId: string): Promise<MeDto> {
  const rs = await db.execute({
    sql: 'SELECT id, email, timezone, ai_access_id, ai_access_enabled, ai_last_used_at FROM users WHERE id = ?',
    args: [userId],
  });
  const r = rs.rows[0];
  return {
    id: String(r.id),
    email: String(r.email),
    timezone: String(r.timezone),
    ai_access_id: String(r.ai_access_id),
    ai_access_enabled: Number(r.ai_access_enabled) === 1,
    ai_last_used_at: r.ai_last_used_at == null ? null : String(r.ai_last_used_at),
  };
}

export async function setTimezone(db: Client, userId: string, timezone: string): Promise<void> {
  // "Today" (and so every phone alarm and the /sync ETag) depends on the timezone: bump the version.
  await db.execute({
    sql: 'UPDATE users SET timezone = ?, data_version = data_version + 1 WHERE id = ?',
    args: [timezone, userId],
  });
}

/** A new random id; the old one stops working immediately. */
export async function regenerateAiAccess(db: Client, userId: string): Promise<string> {
  const id = newAiAccessId();
  await db.execute({ sql: 'UPDATE users SET ai_access_id = ?, ai_last_used_at = NULL WHERE id = ?', args: [id, userId] });
  return id;
}

export async function setAiEnabled(db: Client, userId: string, enabled: boolean): Promise<void> {
  await db.execute({ sql: 'UPDATE users SET ai_access_enabled = ? WHERE id = ?', args: [enabled ? 1 : 0, userId] });
}

/** Resolve an AI access ID to its user. Unknown -> 401, switched off -> 403. Records last use at most once a minute. */
export async function authenticateAi(db: Client, uid: string, now: Date): Promise<UserDto> {
  if (!uid || uid.length < 20) throw new ApiError(401, 'invalid_ai_id', 'Invalid AI access ID');
  const rs = await db.execute({
    sql: 'SELECT id, email, timezone, ai_access_enabled FROM users WHERE ai_access_id = ?',
    args: [uid],
  });
  if (rs.rows.length === 0) throw new ApiError(401, 'invalid_ai_id', 'Invalid AI access ID');
  const r = rs.rows[0];
  if (Number(r.ai_access_enabled) !== 1) throw forbidden('AI access is switched off in the app', 'ai_access_disabled');
  await db.execute({
    sql: 'UPDATE users SET ai_last_used_at = ? WHERE id = ? AND (ai_last_used_at IS NULL OR ai_last_used_at < ?)',
    args: [now.toISOString(), String(r.id), new Date(now.getTime() - 60_000).toISOString()],
  });
  return { id: String(r.id), email: String(r.email), timezone: String(r.timezone) };
}

/** Delete every task and per-day record of a user (the account, labels and settings stay). */
export async function deleteAllTasks(db: Client, userId: string): Promise<void> {
  await db.batch(
    [
      { sql: 'DELETE FROM task_days WHERE user_id = ?', args: [userId] },
      { sql: 'DELETE FROM day_focus WHERE user_id = ?', args: [userId] },
      { sql: 'DELETE FROM activity WHERE user_id = ?', args: [userId] },
      { sql: 'DELETE FROM tasks WHERE user_id = ?', args: [userId] },
      bumpVersion(userId),
    ],
    'write',
  );
}
