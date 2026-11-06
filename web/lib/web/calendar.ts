import { pad2, shiftDate, weekdayIndex } from './format';

export interface GridDay {
  date: string;
  /** false for the leading/trailing days that belong to the neighbouring months. */
  inMonth: boolean;
}

/** The first day of the month containing `date`. */
export const monthStart = (date: string): string => `${date.slice(0, 7)}-01`;

/** First day of the month `delta` months from `date`'s month. */
export function addMonths(date: string, delta: number): string {
  const [y, m] = date.split('-').map(Number);
  const total = y * 12 + (m - 1) + delta;
  return `${Math.floor(total / 12)}-${pad2((total % 12) + 1)}-01`;
}

/** The calendar grid for a month: whole Monday-first weeks (35 or 42 days). A 42-day range fits the API's 62-day cap. */
export function monthGrid(date: string): GridDay[] {
  const first = monthStart(date);
  const lead = weekdayIndex(first);
  const next = addMonths(first, 1);
  const daysInMonth = Math.round((Date.parse(next) - Date.parse(first)) / 86_400_000);
  const weeks = Math.ceil((lead + daysInMonth) / 7);
  const start = shiftDate(first, -lead);
  return Array.from({ length: weeks * 7 }, (_, i) => {
    const d = shiftDate(start, i);
    return { date: d, inMonth: d.slice(0, 7) === first.slice(0, 7) };
  });
}

export type DayKind = 'none' | 'planned' | 'full' | 'partial' | 'missed';

/** How a day looks on the calendar. Today and future days with tasks are 'planned', never 'missed'. */
export function dayKind(day: { planned: number; done: number }, date: string, today: string): DayKind {
  if (day.planned === 0) return 'none';
  if (day.done === day.planned) return 'full';
  if (date >= today) return 'planned';
  return day.done > 0 ? 'partial' : 'missed';
}

/** Text for the status mark (a symbol, so colour is never the only cue) and a screen-reader label. */
export const DAY_MARK: Record<DayKind, { mark: string; label: string }> = {
  none: { mark: '', label: 'no tasks' },
  planned: { mark: '•', label: 'planned' },
  full: { mark: '✓', label: 'all done' },
  partial: { mark: '◐', label: 'partly done' },
  missed: { mark: '✕', label: 'missed' },
};

/** The streak ladder shown as achievements. */
export const STREAK_BADGES = [
  { days: 1, title: 'First Flame' },
  { days: 3, title: 'Quick Start' },
  { days: 7, title: 'Week Warrior' },
  { days: 14, title: 'Two Weeks' },
  { days: 30, title: 'Champion' },
  { days: 100, title: 'Diamond' },
] as const;
