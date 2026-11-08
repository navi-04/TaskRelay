// Small pure helpers shared by the web UI (and unit-tested).

export const WEEKDAYS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'] as const;

export const fmtMin = (m: number): string => (m >= 60 ? `${Math.floor(m / 60)}h${m % 60 ? ` ${m % 60}m` : ''}` : `${m}m`);

/** Calendar-day arithmetic on 'YYYY-MM-DD' strings (UTC midnights; never local time). */
export function shiftDate(date: string, days: number): string {
  const [y, m, d] = date.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d + days)).toISOString().slice(0, 10);
}

/** 0 = Monday .. 6 = Sunday. */
export function weekdayIndex(date: string): number {
  const [y, m, d] = date.split('-').map(Number);
  return (new Date(Date.UTC(y, m - 1, d)).getUTCDay() + 6) % 7;
}

/** "Mon, 6 Nov" in the viewer's locale. Noon avoids any timezone shifting the day. */
export const fmtDay = (date: string): string =>
  new Date(`${date}T12:00:00`).toLocaleDateString(undefined, { weekday: 'short', day: 'numeric', month: 'short' });

export const fmtMonth = (date: string): string =>
  new Date(`${date}T12:00:00`).toLocaleDateString(undefined, { month: 'long', year: 'numeric' });

/** "Every day", "Mon Wed Fri" or '' for a one-off. */
export function repeatLabel(t: { recur: string; recur_days: number[] | null }): string {
  if (t.recur === 'none') return '';
  if (!t.recur_days) return 'Every day';
  if (t.recur_days.join() === '1,2,3,4,5') return 'Weekdays';
  if (t.recur_days.join() === '6,7') return 'Weekends';
  return t.recur_days.map((d) => WEEKDAYS[d - 1]).join(' ');
}

/** 24h "HH:mm" -> the viewer's preferred clock ("9:30 AM" or "09:30"). */
export function fmtClock(hhmm: string): string {
  const [h, m] = hhmm.split(':').map(Number);
  return new Date(2000, 0, 1, h, m).toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' });
}

/**
 * A task's time block as one compact label, in the same clock as its reminder time:
 * "9:00 AM–10:30 AM" (start and end), "from 9:00 AM" (a start alone), "by 5:00 PM" (an end alone is a deadline).
 * '' when the task has neither.
 */
export function fmtTimeBlock(t: { start_time: string | null; end_time: string | null }): string {
  if (t.start_time && t.end_time) return `${fmtClock(t.start_time)}–${fmtClock(t.end_time)}`;
  if (t.start_time) return `from ${fmtClock(t.start_time)}`;
  if (t.end_time) return `by ${fmtClock(t.end_time)}`;
  return '';
}

/** "45 min", "2 h" or "1 h 30 min": a length spelled out for a sentence (fmtMin is the compact form used on chips). */
export function fmtDuration(m: number): string {
  const h = Math.floor(m / 60);
  const rest = m % 60;
  if (h === 0) return `${rest} min`;
  return rest === 0 ? `${h} h` : `${h} h ${rest} min`;
}

/** Pluralise: plural(1, 'task') -> "1 task"; plural(3, 'task') -> "3 tasks". */
export const plural = (n: number, word: string): string => `${n} ${word}${n === 1 ? '' : 's'}`;

export const pad2 = (n: number) => String(n).padStart(2, '0');
