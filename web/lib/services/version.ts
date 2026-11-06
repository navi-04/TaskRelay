import type { InStatement, ResultSet } from '@libsql/client';
import type { Ctx } from '../ctx';

/** One more change the phone has not seen. The phone feed's ETag is built from this counter. */
export const bumpVersion = (userId: string): InStatement => ({
  sql: 'UPDATE users SET data_version = data_version + 1 WHERE id = ?',
  args: [userId],
});

/**
 * The ONLY way to write phone-visible data (tasks, task_days, labels, settings, top-3, timezone):
 * the statements and the version bump commit atomically, so a change can never be missed by /sync.
 * test/version.test.ts fails if a service writes through a bare `execute`.
 */
export function writeBatch(ctx: Ctx, statements: InStatement[]): Promise<ResultSet[]> {
  return ctx.db.batch([...statements, bumpVersion(ctx.userId)], 'write');
}
