// The ONE definition of a task's time block (its start and end on the day it occurs).
// The phone (Kotlin) and the Dart app implement the same three rules; their tests use the same cases as test/timeblock.test.ts.
//
//   start + end        -> the block is [start, end]
//   start only         -> [start, start + duration_min], cut at midnight
//   end only / neither -> no block (an end alone is a deadline, not a slot you can occupy)

export interface Timed {
  start_time: string | null;
  end_time: string | null;
  duration_min: number;
}

/** 'HH:mm' -> minutes since midnight. */
export function toMinutes(hhmm: string): number {
  return Number(hhmm.slice(0, 2)) * 60 + Number(hhmm.slice(3, 5));
}

/** Minutes from `start` to `end` (both 'HH:mm'); callers have checked end > start. */
export const minutesBetween = (start: string, end: string): number => toMinutes(end) - toMinutes(start);

export interface Block {
  /** Minutes since midnight, 0..1439. */
  start: number;
  /** Minutes since midnight, exclusive, 1..1440. */
  end: number;
}

export function taskBlock(t: Timed): Block | null {
  if (!t.start_time) return null;
  const start = toMinutes(t.start_time);
  const end = t.end_time ? toMinutes(t.end_time) : Math.min(start + t.duration_min, 1440);
  return end > start ? { start, end } : null;
}
