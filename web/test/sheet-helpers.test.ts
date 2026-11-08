import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import type { SheetView } from '../lib/services/sheet';
import { fmtClock } from '../lib/web/format';
import {
  cellLabel,
  chipLabel,
  dayName,
  dayTotals,
  filterDays,
  habitMeta,
  isEmptyMonth,
  isFullDay,
  isMissedDay,
  isTogglable,
  monthRange,
  nextMonth,
  nextStatus,
  pctText,
  prevMonth,
  sheetPath,
  shortDate,
  startPrefix,
  withStatus,
} from '../lib/web/sheet';

// A real response of GET /api/v1/sheet (Mon 2 Nov .. Sun 8 Nov 2026, today = Fri 6 Nov), the contract the Sheet tab renders.
const sheet = JSON.parse(readFileSync(join(__dirname, 'fixtures/sheet.json'), 'utf8')) as SheetView;
const day = (date: string) => sheet.days.find((d) => d.date === date)!;

describe('sheet months', () => {
  it('gives the first and last day of a month', () => {
    expect(monthRange('2026-11-06')).toEqual({ from: '2026-11-01', to: '2026-11-30' });
    expect(monthRange('2026-07-31')).toEqual({ from: '2026-07-01', to: '2026-07-31' });
    expect(monthRange('2026-11-01')).toEqual({ from: '2026-11-01', to: '2026-11-30' });
  });

  it('knows February in leap and non-leap years, and century years', () => {
    expect(monthRange('2028-02-10').to).toBe('2028-02-29');
    expect(monthRange('2026-02-10').to).toBe('2026-02-28');
    expect(monthRange('2100-02-10').to).toBe('2100-02-28'); // divisible by 100, not by 400
    expect(monthRange('2000-02-10').to).toBe('2000-02-29');
  });

  it('handles December and January across the year boundary', () => {
    expect(monthRange('2026-12-15')).toEqual({ from: '2026-12-01', to: '2026-12-31' });
    expect(nextMonth('2026-12-15')).toBe('2027-01-01');
    expect(prevMonth('2027-01-20')).toBe('2026-12-01');
  });

  it('moves to the previous and next month (always the 1st)', () => {
    expect(prevMonth('2026-11-06')).toBe('2026-10-01');
    expect(nextMonth('2026-11-06')).toBe('2026-12-01');
    expect(nextMonth(prevMonth('2026-03-31'))).toBe('2026-03-01');
    expect(nextMonth('2028-01-31')).toBe('2028-02-01'); // no day-of-month overflow
  });

  it('every month fits the API window of 92 days', () => {
    for (const m of ['2026-01-01', '2026-02-01', '2026-07-01', '2026-12-01', '2028-02-01']) {
      const { from, to } = monthRange(m);
      expect((Date.parse(to) - Date.parse(from)) / 86_400_000 + 1).toBeLessThanOrEqual(92);
    }
  });

  it('builds the request path: the default window, or an explicit month', () => {
    expect(sheetPath(null)).toBe('/sheet');
    expect(sheetPath('2026-10-01')).toBe('/sheet?from=2026-10-01&to=2026-10-31');
    expect(sheetPath('2028-02-01')).toBe('/sheet?from=2028-02-01&to=2028-02-29');
  });
});

describe('sheet row filters', () => {
  it('All keeps every row, and returns a copy', () => {
    const all = filterDays(sheet.days, 'all');
    expect(all.map((d) => d.date)).toEqual(sheet.days.map((d) => d.date));
    expect(all).not.toBe(sheet.days);
  });

  it('Weekdays only drops Saturday and Sunday', () => {
    expect(filterDays(sheet.days, 'weekdays').map((d) => d.date)).toEqual(['2026-11-02', '2026-11-03', '2026-11-04', '2026-11-05', '2026-11-06']);
  });

  it('Incomplete keeps days with something planned that is not done', () => {
    // 4 and 5 Nov are complete; the others still have something open
    expect(filterDays(sheet.days, 'incomplete').map((d) => d.date)).toEqual(['2026-11-02', '2026-11-03', '2026-11-06', '2026-11-07', '2026-11-08']);
  });

  it('Incomplete ignores days with nothing planned and days that only have skipped tasks', () => {
    const rows = [
      { is_weekend: false, planned: 0, done: 0, id: 'empty' },
      { is_weekend: false, planned: 0, done: 0, id: 'all-skipped' }, // skipped are not planned
      { is_weekend: false, planned: 2, done: 2, id: 'full' },
      { is_weekend: true, planned: 3, done: 1, id: 'partial' },
    ];
    expect(filterDays(rows, 'incomplete').map((d) => d.id)).toEqual(['partial']);
    expect(filterDays(rows, 'weekdays').map((d) => d.id)).toEqual(['empty', 'all-skipped', 'full']);
    expect(filterDays([], 'incomplete')).toEqual([]);
  });

  it('knows when a month has nothing in it', () => {
    expect(isEmptyMonth(sheet)).toBe(false);
    expect(isEmptyMonth({ columns: [], days: sheet.days.map((d) => ({ ...d, tasks: [] })) })).toBe(true);
    expect(isEmptyMonth({ columns: [], days: sheet.days })).toBe(false); // one-off tasks only: still a table
    expect(isEmptyMonth({ columns: sheet.columns, days: sheet.days.map((d) => ({ ...d, tasks: [] })) })).toBe(false); // habits only
  });
});

describe('tapping a cell', () => {
  it('sets an explicit next status: done <-> open, skipped -> open', () => {
    expect(nextStatus('open')).toBe('done');
    expect(nextStatus('done')).toBe('open');
    expect(nextStatus('skipped')).toBe('open');
  });

  it('only a scheduled habit has something to tap', () => {
    expect(isTogglable('open')).toBe(true);
    expect(isTogglable('done')).toBe(true);
    expect(isTogglable('skipped')).toBe(true);
    expect(isTogglable(undefined)).toBe(false);
    // Tue 3 Nov: Gym (Mon Wed Fri) is not scheduled, Meditate (every day) is
    expect(isTogglable(day('2026-11-03').cells['fx-task-gym'])).toBe(false);
    expect(isTogglable(day('2026-11-03').cells['fx-task-meditate'])).toBe(true);
  });
});

describe('sheet text', () => {
  it('formats the date and the day name without any locale or local-time maths', () => {
    expect(shortDate('2026-11-06')).toBe('6 Nov');
    expect(shortDate('2026-01-01')).toBe('1 Jan');
    expect(shortDate('2026-12-31')).toBe('31 Dec');
    expect(dayName(day('2026-11-06'))).toBe('Fri 6 Nov');
    expect(dayName(day('2026-11-08'))).toBe('Sun 8 Nov');
  });

  it('names a tick button with the task, the day and the state', () => {
    const fri = day('2026-11-06');
    expect(cellLabel('Gym', fri, 'open')).toBe('Gym, Fri 6 Nov: not done');
    expect(cellLabel('Gym', fri, 'done')).toBe('Gym, Fri 6 Nov: done');
    expect(cellLabel('Gym', fri, 'skipped')).toBe('Gym, Fri 6 Nov: skipped');
  });

  it('describes a habit column with its repeat days', () => {
    const [gym, meditate] = sheet.columns;
    expect(habitMeta(gym)).toContain('Mon Wed Fri');
    expect(habitMeta(gym).split(' · ')).toHaveLength(2); // a time and the days
    expect(habitMeta(meditate)).toBe('Every day'); // no times at all: just the days
    expect(habitMeta({ alarm_time: null, start_time: null, end_time: null, recur_days: [1, 2, 3, 4, 5] })).toBe('Weekdays');
  });

  it('shows a habit column\'s time block in its header, in preference to the reminder time', () => {
    const [gym] = sheet.columns; // reminder 17:45, block 18:00 to 19:00, Mon Wed Fri
    expect([gym.alarm_time, gym.start_time, gym.end_time]).toEqual(['17:45', '18:00', '19:00']);
    expect(habitMeta(gym)).toBe(`${fmtClock('18:00')}–${fmtClock('19:00')} · Mon Wed Fri`); // an en dash
    expect(habitMeta(gym)).not.toContain(fmtClock('17:45')); // the reminder is not shown next to a block
  });

  it('covers every way a header can be timed: block, start only, end only (a deadline), reminder only, nothing', () => {
    const col = (alarm_time: string | null, start_time: string | null, end_time: string | null) => ({ alarm_time, start_time, end_time, recur_days: null });
    expect(habitMeta(col(null, '09:00', '10:30'))).toBe(`${fmtClock('09:00')}–${fmtClock('10:30')} · Every day`);
    expect(habitMeta(col('08:45', '09:00', '10:30'))).toBe(`${fmtClock('09:00')}–${fmtClock('10:30')} · Every day`); // block beats the reminder
    expect(habitMeta(col('08:45', '09:00', null))).toBe(`from ${fmtClock('09:00')} · Every day`); // a start alone also beats it
    expect(habitMeta(col('16:30', null, '17:00'))).toBe(`by ${fmtClock('17:00')} · Every day`); // so does an end alone
    expect(habitMeta(col('06:00', null, null))).toBe(`${fmtClock('06:00')} · Every day`); // no block: the reminder time, as before
    expect(habitMeta(col(null, null, null))).toBe('Every day'); // nothing: just the days
    expect(habitMeta({ ...col(null, '07:00', '07:30'), recur_days: [6, 7] })).toBe(`${fmtClock('07:00')}–${fmtClock('07:30')} · Weekends`);
  });

  it('prefixes a one-off task\'s chip with its start time, and says so to a screen reader', () => {
    const fri = day('2026-11-06');
    const sat = day('2026-11-07');
    const standup = fri.tasks.find((t) => t.id === 'fx-task-standup')!; // 09:30 to 09:45
    const report = fri.tasks.find((t) => t.id === 'fx-task-report')!; // from 14:00, no end
    const bug = sat.tasks[0]; // no times
    expect([standup.start_time, report.start_time, report.end_time, bug.start_time]).toEqual(['09:30', '14:00', null, null]);

    expect(startPrefix(standup)).toBe(fmtClock('09:30'));
    expect(startPrefix(report)).toBe(fmtClock('14:00'));
    expect(startPrefix(bug)).toBe(''); // no start time: nothing before the title
    expect(startPrefix({ start_time: null })).toBe('');

    expect(chipLabel(standup, fri, 'open')).toBe(`Team standup at ${fmtClock('09:30')}, Fri 6 Nov: not done`);
    expect(chipLabel(report, fri, 'done')).toBe(`Write quarterly report at ${fmtClock('14:00')}, Fri 6 Nov: done`);
    expect(chipLabel(bug, sat, 'skipped')).toBe('Fix login bug, Sat 7 Nov: skipped'); // unchanged without a start
    expect(chipLabel(bug, sat, 'open')).toBe(cellLabel(bug.title, sat, 'open'));
  });
});

describe('sheet totals', () => {
  it('shows an en dash when nothing is planned, a percentage otherwise', () => {
    expect(pctText({ pct: null })).toBe('–');
    expect(pctText({ pct: 0 })).toBe('0%');
    expect(pctText(day('2026-11-06'))).toBe('25%');
  });

  it('inverts only a fully done day, and emphasises only past days with something not done', () => {
    expect(isFullDay({ pct: 100 })).toBe(true);
    expect(isFullDay({ pct: 99 })).toBe(false);
    expect(isFullDay({ pct: null })).toBe(false);

    const today = sheet.today;
    expect(isMissedDay(day('2026-11-02'), today)).toBe(true); // past, 1 of 2
    expect(isMissedDay(day('2026-11-03'), today)).toBe(true); // past, 0 of 1
    expect(isMissedDay(day('2026-11-04'), today)).toBe(false); // past, complete
    expect(isMissedDay(day('2026-11-06'), today)).toBe(false); // today is not missed yet
    expect(isMissedDay(day('2026-11-07'), today)).toBe(false); // the future is not missed
    expect(isMissedDay({ date: '2026-11-01', planned: 0, done: 0 }, today)).toBe(false);
  });

  it('counts like the server: skipped is not planned, and an empty day has no percentage', () => {
    expect(dayTotals({}, [])).toEqual({ planned: 0, done: 0, pct: null });
    expect(dayTotals({ a: 'done', b: 'open', c: 'skipped' }, [])).toEqual({ planned: 2, done: 1, pct: 50 });
    expect(dayTotals({ a: 'skipped' }, [])).toEqual({ planned: 0, done: 0, pct: null });
    expect(dayTotals({ a: 'done' }, [{ id: 't', title: 'T', status: 'open', duration_min: 5, alarm_time: null, start_time: null, end_time: null }])).toEqual({ planned: 2, done: 1, pct: 50 });
    expect(dayTotals({ a: 'done', b: 'done', c: 'open' }, [])).toEqual({ planned: 3, done: 2, pct: 67 });
  });

  it('agrees with the server on every row of a real response', () => {
    for (const d of sheet.days) expect(dayTotals(d.cells, d.tasks)).toEqual({ planned: d.planned, done: d.done, pct: d.pct });
  });
});

describe('optimistic update', () => {
  it('flips a habit cell and recomputes that day only', () => {
    const next = withStatus(sheet, 'fx-task-gym', '2026-11-06', 'done');
    const d = next.days.find((x) => x.date === '2026-11-06')!;
    expect(d.cells['fx-task-gym']).toBe('done');
    expect(d.cells['fx-task-meditate']).toBe('open');
    expect({ planned: d.planned, done: d.done, pct: d.pct }).toEqual({ planned: 4, done: 2, pct: 50 });
    // untouched days keep their identity, and the original is not mutated
    expect(next.days.find((x) => x.date === '2026-11-05')).toBe(day('2026-11-05'));
    expect(day('2026-11-06').cells['fx-task-gym']).toBe('open');
  });

  it('flips a one-off task', () => {
    const next = withStatus(sheet, 'fx-task-report', '2026-11-06', 'done');
    const d = next.days.find((x) => x.date === '2026-11-06')!;
    expect(d.tasks.map((t) => t.status)).toEqual(['done', 'done']);
    expect(d.done).toBe(2);
    // and back again
    const back = withStatus(next, 'fx-task-report', '2026-11-06', 'open').days.find((x) => x.date === '2026-11-06')!;
    expect({ planned: back.planned, done: back.done, pct: back.pct }).toEqual({ planned: 4, done: 1, pct: 25 });
  });

  it('reopening a skipped cell makes it planned again', () => {
    const skipped = withStatus(sheet, 'fx-task-meditate', '2026-11-03', 'skipped');
    expect(day('2026-11-03').planned).toBe(1);
    const d = skipped.days.find((x) => x.date === '2026-11-03')!;
    expect({ planned: d.planned, done: d.done, pct: d.pct }).toEqual({ planned: 0, done: 0, pct: null });
    const reopened = withStatus(skipped, 'fx-task-meditate', '2026-11-03', nextStatus('skipped')).days.find((x) => x.date === '2026-11-03')!;
    expect(reopened.cells['fx-task-meditate']).toBe('open');
    expect(reopened.planned).toBe(1);
  });

  it('ignores a task that is not on that day (never invents a cell)', () => {
    const next = withStatus(sheet, 'fx-task-gym', '2026-11-03', 'done'); // Gym is not scheduled on a Tuesday
    expect(next.days.find((x) => x.date === '2026-11-03')).toBe(day('2026-11-03'));
    expect(withStatus(sheet, 'nope', '2026-11-06', 'done').days).toEqual(sheet.days);
  });
});
