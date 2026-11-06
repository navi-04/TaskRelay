import { describe, expect, it } from 'vitest';
import { addMonths, dayKind, monthGrid, monthStart, STREAK_BADGES } from '../lib/web/calendar';
import { fmtMin, plural, repeatLabel, shiftDate, weekdayIndex } from '../lib/web/format';

describe('web format helpers', () => {
  it('formats minutes and plurals', () => {
    expect([fmtMin(5), fmtMin(60), fmtMin(90), fmtMin(125)]).toEqual(['5m', '1h', '1h 30m', '2h 5m']);
    expect([plural(1, 'task'), plural(0, 'task'), plural(3, 'day')]).toEqual(['1 task', '0 tasks', '3 days']);
  });

  it('does date math on calendar days across months, years and leap days', () => {
    expect(shiftDate('2026-11-30', 1)).toBe('2026-12-01');
    expect(shiftDate('2026-01-01', -1)).toBe('2025-12-31');
    expect(shiftDate('2028-02-28', 1)).toBe('2028-02-29');
    expect(weekdayIndex('2026-11-02')).toBe(0); // Monday
    expect(weekdayIndex('2026-11-08')).toBe(6); // Sunday
  });

  it('labels repeats', () => {
    expect(repeatLabel({ recur: 'none', recur_days: null })).toBe('');
    expect(repeatLabel({ recur: 'daily', recur_days: null })).toBe('Every day');
    expect(repeatLabel({ recur: 'daily', recur_days: [1, 2, 3, 4, 5] })).toBe('Weekdays');
    expect(repeatLabel({ recur: 'daily', recur_days: [6, 7] })).toBe('Weekends');
    expect(repeatLabel({ recur: 'daily', recur_days: [1, 3, 5] })).toBe('Mon Wed Fri');
  });
});

describe('calendar grid', () => {
  it('builds whole Monday-first weeks that contain exactly the month', () => {
    const grid = monthGrid('2026-11-15'); // Nov 2026 starts on a Sunday
    expect(grid.length % 7).toBe(0);
    expect(grid[0].date).toBe('2026-10-26'); // the Monday before
    expect(grid[0].inMonth).toBe(false);
    expect(grid.filter((d) => d.inMonth).map((d) => d.date)).toEqual(Array.from({ length: 30 }, (_, i) => `2026-11-${String(i + 1).padStart(2, '0')}`));
    expect(grid.length).toBeLessThanOrEqual(42); // fits the API's 62-day cap
  });

  it('handles a month that starts on Monday (no leading days) and February in a leap year', () => {
    expect(monthGrid('2026-06-10')[0]).toEqual({ date: '2026-06-01', inMonth: true });
    const feb = monthGrid('2028-02-10');
    expect(feb.filter((d) => d.inMonth)).toHaveLength(29);
    expect(feb.length).toBe(35);
  });

  it('moves between months across year boundaries', () => {
    expect(addMonths('2026-12-15', 1)).toBe('2027-01-01');
    expect(addMonths('2026-01-31', -1)).toBe('2025-12-01');
    expect(addMonths('2026-11-15', 0)).toBe('2026-11-01');
    expect(monthStart('2026-11-25')).toBe('2026-11-01');
  });

  it('classifies days; today and the future are never "missed"', () => {
    const today = '2026-11-06';
    expect(dayKind({ planned: 0, done: 0 }, '2026-11-01', today)).toBe('none');
    expect(dayKind({ planned: 3, done: 3 }, '2026-11-01', today)).toBe('full');
    expect(dayKind({ planned: 3, done: 1 }, '2026-11-01', today)).toBe('partial');
    expect(dayKind({ planned: 3, done: 0 }, '2026-11-01', today)).toBe('missed');
    expect(dayKind({ planned: 3, done: 0 }, today, today)).toBe('planned');
    expect(dayKind({ planned: 3, done: 0 }, '2026-11-09', today)).toBe('planned');
    expect(dayKind({ planned: 2, done: 2 }, today, today)).toBe('full');
  });

  it('has an ascending streak ladder', () => {
    const days = STREAK_BADGES.map((b) => b.days);
    expect(days).toEqual([...days].sort((a, b) => a - b));
  });
});
