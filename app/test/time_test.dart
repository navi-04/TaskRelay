import 'package:flutter_test/flutter_test.dart';
import 'package:taskrelay/core/format.dart';
import 'package:taskrelay/core/time.dart';

void main() {
  group('date arithmetic works on calendar days (never DST-shifted)', () {
    test('across months, years and a leap day', () {
      expect(shiftYmd('2026-11-30', 1), '2026-12-01');
      expect(shiftYmd('2026-01-01', -1), '2025-12-31');
      expect(shiftYmd('2028-02-28', 1), '2028-02-29');
      expect(shiftYmd('2027-02-28', 1), '2027-03-01');
    });

    test('across the days DST changes in New York and London', () {
      expect(shiftYmd('2026-03-07', 1), '2026-03-08'); // US spring forward
      expect(shiftYmd('2026-03-08', 1), '2026-03-09');
      expect(shiftYmd('2026-11-01', 1), '2026-11-02'); // US fall back
      expect(shiftYmd('2026-03-28', 1), '2026-03-29'); // UK spring forward
      expect(shiftYmd('2026-10-24', 2), '2026-10-26'); // UK fall back
    });

    test('weekday index is Monday-based', () {
      expect(weekdayIndex('2026-11-02'), 0);
      expect(weekdayIndex('2026-11-06'), 4);
      expect(weekdayIndex('2026-11-08'), 6);
      expect(weekdayIndex('2028-02-29'), 1);
    });

    test('ymd / parseYmd round-trip and validate', () {
      expect(ymd(DateTime(2026, 3, 5)), '2026-03-05');
      expect(ymd(parseYmd('2026-11-06')), '2026-11-06');
      expect(isYmd('2026-11-06'), isTrue);
      expect(isYmd('2026-1-6'), isFalse);
    });
  });

  group('month grid', () {
    test('whole Monday-first weeks containing exactly the month (November 2026 starts on a Sunday)', () {
      final g = monthGrid('2026-11-15');
      expect(g.length % 7, 0);
      expect(g.first.date, '2026-10-26');
      expect(g.first.inMonth, isFalse);
      final inMonth = g.where((d) => d.inMonth).map((d) => d.date).toList();
      expect(inMonth.length, 30);
      expect([inMonth.first, inMonth.last], ['2026-11-01', '2026-11-30']);
      expect(g.length, lessThanOrEqualTo(42)); // fits the API's 62-day cap
    });

    test('a month starting on Monday has no leading days; February of a leap year has 29', () {
      final jun = monthGrid('2026-06-10');
      expect([jun.first.date, jun.first.inMonth], ['2026-06-01', true]);
      final feb = monthGrid('2028-02-10');
      expect([feb.where((d) => d.inMonth).length, feb.length], [29, 35]);
    });

    test('month navigation crosses year boundaries', () {
      expect(addMonths('2026-12-15', 1), '2027-01-01');
      expect(addMonths('2026-01-31', -1), '2025-12-01');
      expect(monthStart('2026-11-25'), '2026-11-01');
    });

    test('day kinds: today and the future are never "missed"', () {
      DayKind k(int planned, int done, String date) => dayKind(planned: planned, done: done, date: date, today: '2026-11-06');
      expect(k(0, 0, '2026-11-01'), DayKind.none);
      expect(k(3, 3, '2026-11-01'), DayKind.full);
      expect(k(3, 1, '2026-11-01'), DayKind.partial);
      expect(k(3, 0, '2026-11-01'), DayKind.missed);
      expect(k(3, 0, '2026-11-06'), DayKind.planned);
      expect(k(3, 0, '2026-11-09'), DayKind.planned);
      expect(k(2, 2, '2026-11-06'), DayKind.full);
    });
  });

  group('formatting', () {
    test('minutes and plurals', () {
      expect([fmtMinutes(5), fmtMinutes(60), fmtMinutes(90), fmtMinutes(125)], ['5m', '1h', '1h 30m', '2h 5m']);
      expect([plural(1, 'task'), plural(0, 'task'), plural(3, 'day')], ['1 task', '0 tasks', '3 days']);
    });

    test('repeat labels', () {
      expect(repeatLabel(repeating: false), '');
      expect(repeatLabel(repeating: true), 'Every day');
      expect(repeatLabel(repeating: true, days: [1, 2, 3, 4, 5]), 'Weekdays');
      expect(repeatLabel(repeating: true, days: [6, 7]), 'Weekends');
      expect(repeatLabel(repeating: true, days: [1, 3, 5]), 'Mon Wed Fri');
    });

    test('relative times', () {
      final now = DateTime(2026, 11, 6, 12);
      expect(ago(now.subtract(const Duration(seconds: 20)), now), 'just now');
      expect(ago(now.subtract(const Duration(minutes: 5)), now), '5 min ago');
      expect(ago(now.subtract(const Duration(hours: 3)), now), '3 h ago');
      expect(ago(now.subtract(const Duration(days: 2)), now), '2 d ago');
    });

    test('Monday-first weekday names', () {
      final names = shortWeekdays();
      expect(names.length, 7);
      expect(names.first.toLowerCase(), startsWith('mon'));
      expect(names.last.toLowerCase(), startsWith('sun'));
    });
  });
}
