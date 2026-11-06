// Calendar-day helpers. A "date" is a local calendar day as 'YYYY-MM-DD', exactly what the API speaks.
// Day arithmetic goes through UTC midnights of the date parts (UTC has no DST), never `Duration(days: 1)`
// on a local DateTime (which is wrong across a DST change).

String _two(int n) => n.toString().padLeft(2, '0');

String ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

/// Local midnight of a 'YYYY-MM-DD' date.
DateTime parseYmd(String s) {
  final p = s.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

bool isYmd(String s) => RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s);

String todayYmd([DateTime? now]) => ymd(now ?? DateTime.now());

/// The date `days` after (or before, if negative) `date`.
String shiftYmd(String date, int days) {
  final p = date.split('-').map(int.parse).toList();
  return ymd(DateTime.utc(p[0], p[1], p[2] + days));
}

/// 0 = Monday .. 6 = Sunday.
int weekdayIndex(String date) {
  final p = date.split('-').map(int.parse).toList();
  return DateTime.utc(p[0], p[1], p[2]).weekday - 1; // Dart: Monday = 1 .. Sunday = 7
}

/// The first day of the month containing [date].
String monthStart(String date) => '${date.substring(0, 7)}-01';

/// The first day of the month [delta] months from [date]'s month.
String addMonths(String date, int delta) {
  final p = date.split('-').map(int.parse).toList();
  final total = p[0] * 12 + (p[1] - 1) + delta;
  return '${(total ~/ 12).toString().padLeft(4, '0')}-${_two(total % 12 + 1)}-01';
}

class GridDay {
  const GridDay(this.date, this.inMonth);
  final String date;

  /// False for the leading/trailing days that belong to the neighbouring months.
  final bool inMonth;
}

/// Whole Monday-first weeks (35 or 42 days) covering the month of [date]. A 42-day range fits the API's 62-day cap.
List<GridDay> monthGrid(String date) {
  final first = monthStart(date);
  final lead = weekdayIndex(first);
  final next = addMonths(first, 1);
  final daysInMonth = DateTime.utc(int.parse(next.substring(0, 4)), int.parse(next.substring(5, 7)), 1)
      .difference(DateTime.utc(int.parse(first.substring(0, 4)), int.parse(first.substring(5, 7)), 1))
      .inDays;
  final weeks = ((lead + daysInMonth) / 7).ceil();
  final start = shiftYmd(first, -lead);
  return List.generate(weeks * 7, (i) {
    final d = shiftYmd(start, i);
    return GridDay(d, d.substring(0, 7) == first.substring(0, 7));
  });
}

enum DayKind { none, planned, full, partial, missed }

/// How a day looks on the calendar. Today and future days with tasks are `planned`, never `missed`.
DayKind dayKind({required int planned, required int done, required String date, required String today}) {
  if (planned == 0) return DayKind.none;
  if (done == planned) return DayKind.full;
  if (date.compareTo(today) >= 0) return DayKind.planned;
  return done > 0 ? DayKind.partial : DayKind.missed;
}
