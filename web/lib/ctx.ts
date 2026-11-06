import type { Client } from '@libsql/client';

export type Actor = 'app' | 'ai';

/**
 * Everything a service function needs. Services take a Ctx first and scope every query
 * by `userId`; none accepts a bare id without it, so cross-user access is impossible.
 */
export interface Ctx {
  db: Client;
  userId: string;
  /** IANA timezone of the user; "today" is always derived from this. */
  tz: string;
  actor: Actor;
  now: () => Date;
}
