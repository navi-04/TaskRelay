import type { Row } from '@libsql/client';
import type { Ctx } from '../ctx';
import type { SettingsPatch } from '../validation';
import { writeBatch } from './version';

export interface SettingsDto {
  estimation_mode: 'time' | 'count';
  daily_time_limit_min: number;
  daily_count_limit: number;
  daily_reminder_on: boolean;
  daily_reminder_hour: number;
  daily_reminder_min: number;
  end_of_day_on: boolean;
  end_of_day_hour: number;
  end_of_day_min: number;
  carry_over_alerts: boolean;
}

const BOOLS = ['daily_reminder_on', 'end_of_day_on', 'carry_over_alerts'] as const;
const COLUMNS = [
  'estimation_mode',
  'daily_time_limit_min',
  'daily_count_limit',
  'daily_reminder_on',
  'daily_reminder_hour',
  'daily_reminder_min',
  'end_of_day_on',
  'end_of_day_hour',
  'end_of_day_min',
  'carry_over_alerts',
] as const;

function toDto(r: Row): SettingsDto {
  const out: Record<string, unknown> = {};
  for (const c of COLUMNS) {
    out[c] = (BOOLS as readonly string[]).includes(c) ? Number(r[c]) === 1 : c === 'estimation_mode' ? String(r[c]) : Number(r[c]);
  }
  return out as unknown as SettingsDto;
}

export async function getSettings(ctx: Ctx): Promise<SettingsDto> {
  const select = () => ctx.db.execute({ sql: `SELECT ${COLUMNS.join(', ')} FROM settings WHERE user_id = ?`, args: [ctx.userId] });
  let rs = await select();
  if (rs.rows.length === 0) {
    // The row is created at registration; this heals a missing one (never expected in practice).
    await writeBatch(ctx, [{ sql: 'INSERT OR IGNORE INTO settings (user_id) VALUES (?)', args: [ctx.userId] }]);
    rs = await select();
  }
  return toDto(rs.rows[0]);
}

export async function patchSettings(ctx: Ctx, patch: SettingsPatch): Promise<SettingsDto> {
  const sets: string[] = [];
  const args: Array<string | number> = [];
  for (const c of COLUMNS) {
    const v = patch[c];
    if (v === undefined) continue;
    sets.push(`${c} = ?`);
    args.push(typeof v === 'boolean' ? (v ? 1 : 0) : v);
  }
  await writeBatch(ctx, [
    { sql: 'INSERT OR IGNORE INTO settings (user_id) VALUES (?)', args: [ctx.userId] },
    ...(sets.length > 0 ? [{ sql: `UPDATE settings SET ${sets.join(', ')} WHERE user_id = ?`, args: [...args, ctx.userId] }] : []),
  ]);
  return getSettings(ctx);
}
