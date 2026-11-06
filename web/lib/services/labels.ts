import type { InStatement, Row } from '@libsql/client';
import type { Ctx } from '../ctx';
import { badRequest, conflict, notFound } from '../errors';
import { writeBatch } from './version';

export type LabelKind = 'type' | 'priority';

export interface LabelDto {
  id: string;
  kind: LabelKind;
  label: string;
  color: number;
  sort_order: number;
}

const NEUTRAL = 0xff607d8b;
const DEFAULT_TYPES = ['Task', 'Bug', 'Feature', 'Story', 'Epic', 'Improvement', 'Subtask', 'Research'];
// Ascending sort_order = ascending importance (Critical sorts first in task lists).
const DEFAULT_PRIORITIES: Array<[string, number]> = [
  ['Low', 0xff2196f3],
  ['Medium', 0xffff9800],
  ['High', 0xfff44336],
  ['Critical', 0xffff5722],
];

/** Statements that seed a new user's labels; run inside the registration batch. */
export function seedLabelStatements(userId: string, nowIso: string): InStatement[] {
  const insert = (kind: LabelKind, label: string, color: number, order: number): InStatement => ({
    sql: 'INSERT INTO labels (id, user_id, kind, label, color, sort_order, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
    args: [crypto.randomUUID(), userId, kind, label, color, order, nowIso],
  });
  return [
    ...DEFAULT_TYPES.map((label, i) => insert('type', label, NEUTRAL, i)),
    ...DEFAULT_PRIORITIES.map(([label, color], i) => insert('priority', label, color, i)),
  ];
}

const toDto = (r: Row): LabelDto => ({
  id: String(r.id),
  kind: String(r.kind) as LabelKind,
  label: String(r.label),
  color: Number(r.color),
  sort_order: Number(r.sort_order),
});

export async function listLabels(ctx: Ctx): Promise<{ types: LabelDto[]; priorities: LabelDto[] }> {
  const rs = await ctx.db.execute({
    sql: 'SELECT id, kind, label, color, sort_order FROM labels WHERE user_id = ? ORDER BY kind, sort_order, created_at',
    args: [ctx.userId],
  });
  const all = rs.rows.map(toDto);
  return { types: all.filter((l) => l.kind === 'type'), priorities: all.filter((l) => l.kind === 'priority') };
}

/** A task may only reference labels of the right kind that belong to the same user. */
export async function assertOwnedLabel(ctx: Ctx, id: string | null | undefined, kind: LabelKind): Promise<void> {
  if (id == null) return;
  const rs = await ctx.db.execute({
    sql: 'SELECT 1 FROM labels WHERE id = ? AND user_id = ? AND kind = ?',
    args: [id, ctx.userId, kind],
  });
  if (rs.rows.length === 0) throw badRequest(`Unknown ${kind} id`, 'invalid_label');
}

export async function createLabel(
  ctx: Ctx,
  input: { kind: LabelKind; label: string; color?: number },
): Promise<LabelDto> {
  const id = crypto.randomUUID();
  await writeBatch(ctx, [
    {
      sql: `INSERT INTO labels (id, user_id, kind, label, color, sort_order, created_at)
            VALUES (?, ?, ?, ?, ?, COALESCE((SELECT MAX(sort_order) + 1 FROM labels WHERE user_id = ? AND kind = ?), 0), ?)`,
      args: [id, ctx.userId, input.kind, input.label, input.color ?? NEUTRAL, ctx.userId, input.kind, ctx.now().toISOString()],
    },
  ]);
  return getLabel(ctx, id);
}

async function getLabel(ctx: Ctx, id: string): Promise<LabelDto> {
  const rs = await ctx.db.execute({
    sql: 'SELECT id, kind, label, color, sort_order FROM labels WHERE id = ? AND user_id = ?',
    args: [id, ctx.userId],
  });
  if (rs.rows.length === 0) throw notFound('Label not found');
  return toDto(rs.rows[0]);
}

export async function updateLabel(
  ctx: Ctx,
  id: string,
  patch: { label?: string; color?: number; sort_order?: number },
): Promise<LabelDto> {
  await getLabel(ctx, id);
  const sets: string[] = [];
  const args: Array<string | number> = [];
  for (const key of ['label', 'color', 'sort_order'] as const) {
    if (patch[key] !== undefined) {
      sets.push(`${key} = ?`);
      args.push(patch[key]!);
    }
  }
  if (sets.length > 0) {
    await writeBatch(ctx, [{ sql: `UPDATE labels SET ${sets.join(', ')} WHERE id = ? AND user_id = ?`, args: [...args, id, ctx.userId] }]);
  }
  return getLabel(ctx, id);
}

/** Deleting a label detaches it from tasks (the UI shows a default); the last label of a kind can't be deleted. */
export async function deleteLabel(ctx: Ctx, id: string): Promise<void> {
  const label = await getLabel(ctx, id);
  const count = await ctx.db.execute({
    sql: 'SELECT COUNT(*) AS n FROM labels WHERE user_id = ? AND kind = ?',
    args: [ctx.userId, label.kind],
  });
  if (Number(count.rows[0].n) <= 1) throw conflict(`At least one ${label.kind} must remain`, 'last_label');
  const column = label.kind === 'type' ? 'type_id' : 'priority_id';
  await writeBatch(ctx, [
    { sql: `UPDATE tasks SET ${column} = NULL WHERE user_id = ? AND ${column} = ?`, args: [ctx.userId, id] },
    { sql: 'DELETE FROM labels WHERE id = ? AND user_id = ?', args: [id, ctx.userId] },
  ]);
}
