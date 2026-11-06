import { describe, expect, it } from 'vitest';
import { createClient } from '@libsql/client';
import { copyFileSync, mkdtempSync, readdirSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { migrate, splitStatements } from '../lib/migrate';

const REAL_DIR = path.join(process.cwd(), 'db', 'migrations');

describe('migrations', () => {
  it('upgrades a database that only has 0001 without touching existing rows', async () => {
    const db = createClient({ url: ':memory:' });
    const only0001 = mkdtempSync(path.join(os.tmpdir(), 'tr-mig-'));
    copyFileSync(path.join(REAL_DIR, '0001_init.sql'), path.join(only0001, '0001_init.sql'));
    expect(await migrate(db, only0001)).toEqual(['0001_init.sql']);

    // Rows exactly as the deployed 0001 schema would hold them
    await db.batch(
      [
        { sql: `INSERT INTO users (id, email, password_hash, ai_access_id, created_at) VALUES ('u1', 'a@x.io', 'h', 'ai-1', '2026-11-01T00:00:00Z')`, args: [] },
        { sql: `INSERT INTO tasks (id, user_id, title, due_date, recur, created_at, updated_at) VALUES ('t-old-0001', 'u1', 'old', '2026-11-02', 'daily', '2026-11-01T00:00:00Z', '2026-11-01T00:00:00Z')`, args: [] },
        { sql: `INSERT INTO task_days (task_id, user_id, date, status, updated_at) VALUES ('t-old-0001', 'u1', '2026-11-03', 'done', '2026-11-03T00:00:00Z')`, args: [] },
      ],
      'write',
    );

    const applied = await migrate(db);
    expect(applied).not.toContain('0001_init.sql');
    expect(applied[0]).toBe('0002_foundations.sql');

    const task = (await db.execute(`SELECT title, recur, recur_days FROM tasks WHERE id = 't-old-0001'`)).rows[0];
    expect([String(task.title), String(task.recur), task.recur_days]).toEqual(['old', 'daily', null]); // existing rows keep working
    expect(Number((await db.execute(`SELECT data_version FROM users WHERE id = 'u1'`)).rows[0].data_version)).toBe(0);
    expect((await db.execute(`SELECT status FROM task_days WHERE task_id = 't-old-0001'`)).rows[0].status).toBe('done');

    const indexes = (await db.execute(`SELECT name FROM sqlite_schema WHERE type = 'index'`)).rows.map((r) => String(r.name));
    expect(indexes).toEqual(expect.arrayContaining(['tasks_recurring', 'tasks_deleted', 'tasks_user_due']));

    expect(await migrate(db)).toEqual([]); // second run is a no-op
  });

  it('the new column enforces its bitmask range', async () => {
    const db = createClient({ url: ':memory:' });
    await migrate(db);
    const insert = (days: number) =>
      db.execute({
        sql: `INSERT INTO tasks (id, user_id, title, due_date, recur, recur_days, created_at, updated_at)
              VALUES (?, 'u1', 't', '2026-11-02', 'daily', ?, 'x', 'x')`,
        args: [`t-mask-${days}`, days],
      });
    await expect(insert(0)).rejects.toThrow();
    await expect(insert(128)).rejects.toThrow();
    await expect(insert(127)).resolves.toBeTruthy();
    await expect(insert(1)).resolves.toBeTruthy();
  });

  it('every migration file is numbered, ordered and splits into statements', () => {
    const files = readdirSync(REAL_DIR).filter((f) => f.endsWith('.sql')).sort();
    expect(files.length).toBeGreaterThanOrEqual(2);
    files.forEach((f, i) => expect(f.startsWith(String(i + 1).padStart(4, '0') + '_'), f).toBe(true));
    expect(splitStatements('-- c\nCREATE TABLE a (x INTEGER);\nCREATE INDEX i ON a (x);\n')).toEqual([
      'CREATE TABLE a (x INTEGER)',
      'CREATE INDEX i ON a (x)',
    ]);
  });
});
