// The ONE definition of "does a task occur on this day".
// The TS function (writes, expansion) and the SQL fragment (reads) below must agree;
// test/recurrence.test.ts checks them against each other over hundreds of random tasks and dates.

export interface Recurring {
  recur: string;
  due_date: string;
  recur_until: string | null;
  /** Weekday bitmask, Mon=bit0..Sun=bit6; null = every day. */
  recur_days: number | null;
}

/** 0 = Monday .. 6 = Sunday for a 'YYYY-MM-DD' date. Computed on UTC midnight, never local time. */
export function weekdayIndex(date: string): number {
  const [y, m, d] = date.split('-').map(Number);
  return (new Date(Date.UTC(y, m - 1, d)).getUTCDay() + 6) % 7;
}

export function occursOn(t: Recurring, date: string): boolean {
  if (t.recur === 'none') return t.due_date === date;
  if (t.due_date > date) return false;
  if (t.recur_until != null && date > t.recur_until) return false;
  return t.recur_days == null || (t.recur_days & (1 << weekdayIndex(date))) !== 0;
}

/**
 * SQL for the same rule. `t` is the tasks alias, `d` a SQL expression for the day
 * (a named parameter like ':d' or a column like 'days.d').
 * SQLite's strftime('%w') is Sunday=0, so the Monday-based bit index is (w + 6) % 7.
 */
export function occursSql(t = 't', d = ':d'): string {
  return `( (${t}.recur = 'none' AND ${t}.due_date = ${d})
         OR (${t}.recur = 'daily' AND ${t}.due_date <= ${d}
             AND (${t}.recur_until IS NULL OR ${t}.recur_until >= ${d})
             AND (${t}.recur_days IS NULL
                  OR (${t}.recur_days & (1 << ((CAST(strftime('%w', ${d}) AS INTEGER) + 6) % 7))) <> 0)) )`;
}

/** [1..7] (1=Mon) -> bitmask. Null, undefined and "every day" all normalise to null. Callers reject empty lists first. */
export function daysToMask(days: readonly number[] | null | undefined): number | null {
  if (!days || days.length === 0) return null;
  let mask = 0;
  for (const d of days) mask |= 1 << (d - 1);
  return mask === 127 ? null : mask;
}

/** Bitmask -> ascending [1..7] (1=Mon), or null for every day. */
export function maskToDays(mask: number | null | undefined): number[] | null {
  if (mask == null) return null;
  const days: number[] = [];
  for (let i = 0; i < 7; i++) if (mask & (1 << i)) days.push(i + 1);
  return days;
}

/** The first date a repeating task occurs (its start date may not be in the mask), or null if it never does. */
export function firstOccurrence(t: Recurring): string | null {
  const [y, m, d] = t.due_date.split('-').map(Number);
  for (let i = 0; i < 7; i++) {
    const day = new Date(Date.UTC(y, m - 1, d + i)).toISOString().slice(0, 10);
    if (occursOn(t, day)) return day;
  }
  return null;
}
