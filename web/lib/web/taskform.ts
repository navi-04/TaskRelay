// Pure rules of the task form (unit-tested): the start/end pair, and the request body for a new task or an edit.
// The server stays the judge; these mirror its rules (lib/validation.ts, lib/services/tasks.ts) so the form can say no first.

import type { TaskDto } from '../services/tasks';
import { minutesBetween } from '../timeblock';

/** Same words as the server's, so the message reads the same whichever side caught it. */
export const END_BEFORE_START = 'End time must be after the start time';

/**
 * Why a start/end pair cannot be saved, or null. Either side may be '' (not set); both are "HH:mm" from a time input,
 * so they compare as text, exactly as the server compares them. A block never runs overnight.
 */
export const timesError = (start: string, end: string): string | null => (start && end && end <= start ? END_BEFORE_START : null);

/** The length of the block when both times are set and in order; null otherwise (then the task's own estimate applies). */
export const blockMinutes = (start: string, end: string): number | null => (start && end && end > start ? minutesBetween(start, end) : null);

export interface RepeatFields {
  recur: 'none' | 'daily';
  recur_days: number[] | null;
  recur_until: string | null;
}

/** What the form holds: the raw values of its controls ('' = not chosen / not set). */
export interface TaskFormState {
  title: string;
  notes: string;
  /** The estimate; ignored while both times are set. */
  minutes: number;
  typeId: string;
  priorityId: string;
  dueDate: string;
  alarm: string;
  startTime: string;
  endTime: string;
  kind: 'alarm' | 'notification';
  repeat: RepeatFields;
}

/** The fields of a task as the API takes them. duration_min is left out while both times are set. */
export type TaskFields = Pick<
  TaskDto,
  'title' | 'notes' | 'type_id' | 'priority_id' | 'due_date' | 'alarm_time' | 'start_time' | 'end_time' | 'reminder_kind' | 'recur' | 'recur_days' | 'recur_until'
> & { duration_min?: number };

/**
 * Every field of the form as the API takes it. With a start and an end the length is theirs and the server works it out,
 * so no duration_min goes along (a different one would be refused). A time that is not set is null, which also removes it on an edit.
 */
export function taskFields(s: TaskFormState): TaskFields {
  return {
    title: s.title.trim(),
    notes: s.notes.trim() === '' ? null : s.notes,
    ...(s.startTime && s.endTime ? {} : { duration_min: s.minutes }),
    type_id: s.typeId || null,
    priority_id: s.priorityId || null,
    due_date: s.dueDate,
    alarm_time: s.alarm || null,
    start_time: s.startTime || null,
    end_time: s.endTime || null,
    reminder_kind: s.kind,
    ...s.repeat,
  };
}

/**
 * What an edit sends: only the fields that differ from the saved task. Nothing stale is written back over a change made
 * elsewhere (the phone, Claude), and a task that keeps its start and end is never sent a duration that fights them.
 * An empty result means there is nothing to save.
 */
export function changedFields(next: TaskFields, saved: TaskDto): Partial<TaskFields> {
  const differs = ([key, value]: [string, unknown]) => JSON.stringify(value) !== JSON.stringify(saved[key as keyof TaskDto]);
  return Object.fromEntries(Object.entries(next).filter(differs)) as Partial<TaskFields>;
}
