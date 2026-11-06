import type { Client, ResultSet } from '@libsql/client';
import { ApiError, tooMany } from '../errors';
import { setPassword, verifyPassword } from './auth';
import { clear, enforce, hit, retryAfter } from './rateLimit';

// Re-checking the current password is brute-forceable by anyone holding a session, so wrong guesses are limited.
const PASSWORD_ATTEMPTS = 5;
const PASSWORD_WINDOW_SEC = 15 * 60;

/** Verify the user's current password (counting failures); returns their email. 403, not 401: the session itself is fine. */
async function confirmPassword(db: Client, userId: string, password: string, now: Date): Promise<string> {
  const key = `pw:${userId}`;
  const wait = await retryAfter(db, key, PASSWORD_ATTEMPTS, PASSWORD_WINDOW_SEC, now);
  if (wait > 0) throw tooMany(wait);
  const rs = await db.execute({ sql: 'SELECT email, password_hash FROM users WHERE id = ?', args: [userId] });
  const row = rs.rows[0];
  if (!row || !(await verifyPassword(password, String(row.password_hash)))) {
    await hit(db, key, PASSWORD_WINDOW_SEC, now);
    throw new ApiError(403, 'wrong_password', 'That password is not correct');
  }
  await clear(db, key);
  return String(row.email);
}

/** Change the password and sign out every OTHER session (the one that asked stays signed in). */
export async function changePassword(
  db: Client,
  userId: string,
  input: { current_password: string; new_password: string },
  keepTokenHash: string,
  now: Date,
): Promise<void> {
  await confirmPassword(db, userId, input.current_password, now);
  await setPassword(db, userId, input.new_password, keepTokenHash);
}

/** Permanently delete the account and every row that belongs to it, in one batch. Needs the password. */
export async function deleteAccount(db: Client, userId: string, password: string, now: Date): Promise<void> {
  const email = await confirmPassword(db, userId, password, now);
  await db.batch(
    [
      { sql: 'DELETE FROM task_days WHERE user_id = ?', args: [userId] },
      { sql: 'DELETE FROM day_focus WHERE user_id = ?', args: [userId] },
      { sql: 'DELETE FROM activity WHERE user_id = ?', args: [userId] },
      { sql: 'DELETE FROM tasks WHERE user_id = ?', args: [userId] },
      { sql: 'DELETE FROM labels WHERE user_id = ?', args: [userId] },
      { sql: 'DELETE FROM settings WHERE user_id = ?', args: [userId] },
      { sql: 'DELETE FROM sessions WHERE user_id = ?', args: [userId] },
      // every per-user rate-limit key ends with ":<user id>"; login failures are keyed by email
      { sql: 'DELETE FROM rate_limits WHERE key LIKE ? OR key = ?', args: [`%:${userId}`, `login:email:${email}`] },
      { sql: 'DELETE FROM users WHERE id = ?', args: [userId] },
    ],
    'write',
  );
}

const objects = (rs: ResultSet) => rs.rows.map((r) => Object.fromEntries(rs.columns.map((c) => [c, r[c]])));

/** A full copy of the user's data. Excludes the password hash, the AI access id and sessions. Limited to 5 per hour. */
export async function exportAccount(db: Client, userId: string, now: Date) {
  await enforce(db, `export:${userId}`, 5, 3600, now);
  const q = (sql: string) => db.execute({ sql, args: [userId] });
  const [user, settings, labels, tasks, taskDays, dayFocus, activity] = await Promise.all([
    q('SELECT id, email, timezone, created_at FROM users WHERE id = ?'),
    q('SELECT * FROM settings WHERE user_id = ?'),
    q('SELECT * FROM labels WHERE user_id = ? ORDER BY kind, sort_order'),
    q('SELECT * FROM tasks WHERE user_id = ? ORDER BY created_at, id'), // includes soft-deleted ones
    q('SELECT * FROM task_days WHERE user_id = ? ORDER BY date, task_id'),
    q('SELECT * FROM day_focus WHERE user_id = ? ORDER BY date, position'),
    q('SELECT * FROM activity WHERE user_id = ? ORDER BY id'),
  ]);
  return {
    exported_at: now.toISOString(),
    user: objects(user)[0],
    settings: objects(settings)[0] ?? null,
    labels: objects(labels),
    tasks: objects(tasks),
    task_days: objects(taskDays),
    day_focus: objects(dayFocus),
    activity: objects(activity),
  };
}
