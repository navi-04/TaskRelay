import { z } from 'zod';
import { isValidDate, isValidTimezone } from './time';

export const dateStr = z.string().refine(isValidDate, 'Must be a real calendar date as YYYY-MM-DD');
export const timeStr = z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/, 'Must be a 24h time as HH:mm');
export const idStr = z.string().regex(/^[A-Za-z0-9_-]{8,64}$/, 'Must be 8-64 chars: letters, digits, - or _');
const instant = z.string().refine((s) => !Number.isNaN(Date.parse(s)), 'Must be an ISO-8601 timestamp');
const timezone = z.string().refine(isValidTimezone, 'Must be an IANA timezone like Asia/Kolkata');

const taskFields = {
  title: z.string().trim().min(1).max(200),
  notes: z.string().max(4000).nullable(),
  duration_min: z.number().int().min(1).max(1440),
  type_id: idStr.nullable(),
  priority_id: idStr.nullable(),
  due_date: dateStr,
  alarm_time: timeStr.nullable(),
  reminder_kind: z.enum(['alarm', 'notification']),
  recur: z.enum(['none', 'daily']),
  recur_until: dateStr.nullable(),
};

export const taskCreate = z.strictObject({
  id: idStr.optional(),
  title: taskFields.title,
  notes: taskFields.notes.optional(),
  duration_min: taskFields.duration_min.default(30),
  type_id: taskFields.type_id.optional(),
  priority_id: taskFields.priority_id.optional(),
  due_date: taskFields.due_date,
  alarm_time: taskFields.alarm_time.optional(),
  reminder_kind: taskFields.reminder_kind.default('alarm'),
  recur: taskFields.recur.default('none'),
  recur_until: taskFields.recur_until.optional(),
});
export type TaskCreate = z.infer<typeof taskCreate>;

export const taskPatch = z
  .strictObject({
    title: taskFields.title,
    notes: taskFields.notes,
    duration_min: taskFields.duration_min,
    type_id: taskFields.type_id,
    priority_id: taskFields.priority_id,
    due_date: taskFields.due_date,
    alarm_time: taskFields.alarm_time,
    reminder_kind: taskFields.reminder_kind,
    recur: taskFields.recur,
    recur_until: taskFields.recur_until,
  })
  .partial()
  .refine((o) => Object.keys(o).length > 0, 'Provide at least one field to change');
export type TaskPatch = z.infer<typeof taskPatch>;

export const dayPut = z.strictObject({
  status: z.enum(['done', 'skipped', 'open']),
  note: z.string().max(1000).nullable().optional(),
  completed_at: instant.optional(),
});
export type DayPut = z.infer<typeof dayPut>;

export const movePost = z.strictObject({
  ids: z.array(idStr).min(1).max(50),
  to: dateStr,
});

export const register = z.strictObject({
  email: z.string().trim().toLowerCase().pipe(z.email().max(254)),
  password: z.string().min(8, 'At least 8 characters').max(128),
  timezone: timezone.optional(),
});

export const login = z.strictObject({
  email: z.string().trim().toLowerCase().max(254),
  password: z.string().min(1).max(128),
});

export const mePatch = z.strictObject({ timezone });
export const aiAccessPatch = z.strictObject({ enabled: z.boolean() });

const flag = z.boolean();
export const settingsPatch = z
  .strictObject({
    estimation_mode: z.enum(['time', 'count']),
    daily_time_limit_min: z.number().int().min(15).max(1440),
    daily_count_limit: z.number().int().min(1).max(100),
    daily_reminder_on: flag,
    daily_reminder_hour: z.number().int().min(0).max(23),
    daily_reminder_min: z.number().int().min(0).max(59),
    end_of_day_on: flag,
    end_of_day_hour: z.number().int().min(0).max(23),
    end_of_day_min: z.number().int().min(0).max(59),
    carry_over_alerts: flag,
  })
  .partial()
  .refine((o) => Object.keys(o).length > 0, 'Provide at least one setting to change');
export type SettingsPatch = z.infer<typeof settingsPatch>;

const argb = z.number().int().min(0).max(0xffffffff);
export const labelCreate = z.strictObject({
  kind: z.enum(['type', 'priority']),
  label: z.string().trim().min(1).max(40),
  color: argb.optional(),
});
export const labelPatch = z
  .strictObject({
    label: z.string().trim().min(1).max(40),
    color: argb,
    sort_order: z.number().int().min(0).max(1000),
  })
  .partial()
  .refine((o) => Object.keys(o).length > 0, 'Provide at least one field to change');

/** `all`, `day:YYYY-MM-DD` or `from:YYYY-MM-DD`. */
export const deleteScope = z
  .string()
  .regex(/^(all|day:\d{4}-\d{2}-\d{2}|from:\d{4}-\d{2}-\d{2})$/, 'Use all, day:YYYY-MM-DD or from:YYYY-MM-DD')
  .refine((s) => s === 'all' || isValidDate(s.split(':')[1]), 'Must contain a real calendar date');
