import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'time.dart';

/// "45m", "1h", "1h 30m".
String fmtMinutes(int m) => m >= 60 ? '${m ~/ 60}h${m % 60 == 0 ? '' : ' ${m % 60}m'}' : '${m}m';

/// "1 task", "3 tasks".
String plural(int n, String word) => '$n $word${n == 1 ? '' : 's'}';

/// "Mon, 6 Nov" in the device's language.
String fmtDay(String date) => DateFormat('EEE, d MMM').format(parseYmd(date));

String fmtDayLong(String date) => DateFormat('EEEE, d MMMM').format(parseYmd(date));

String fmtMonth(String date) => DateFormat.yMMMM().format(parseYmd(date));

/// Short weekday names, Monday first, in the device's language.
List<String> shortWeekdays() => List.generate(7, (i) => DateFormat.E().format(DateTime(2026, 11, 2 + i)));

/// "HH:mm" -> the device's clock style ("9:30 AM" or "09:30").
String fmtClock(BuildContext context, String hhmm) {
  final p = hhmm.split(':').map(int.parse).toList();
  return TimeOfDay(hour: p[0], minute: p[1]).format(context);
}

/// A task's time block as one label: "9:00 AM – 10:30 AM", "from 9:00 AM" (start only) or "by 5:00 PM" (end only). Null when it has neither.
String? fmtBlock(BuildContext context, {String? start, String? end}) {
  if (start != null && end != null) return '${fmtClock(context, start)} – ${fmtClock(context, end)}';
  if (start != null) return 'from ${fmtClock(context, start)}';
  if (end != null) return 'by ${fmtClock(context, end)}';
  return null;
}

/// 24h "HH:mm" from a TimeOfDay (what the API stores).
String toHhmm(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

TimeOfDay fromHhmm(String hhmm) {
  final p = hhmm.split(':').map(int.parse).toList();
  return TimeOfDay(hour: p[0], minute: p[1]);
}

/// "Mon Wed Fri", "Weekdays", "Weekends", "Every day" for a repeating task; '' for a one-off.
String repeatLabel({required bool repeating, List<int>? days}) {
  if (!repeating) return '';
  if (days == null) return 'Every day';
  final key = days.join(',');
  if (key == '1,2,3,4,5') return 'Weekdays';
  if (key == '6,7') return 'Weekends';
  final names = shortWeekdays();
  return days.map((d) => names[d - 1]).join(' ');
}

/// "2 min ago", "3 h ago", "4 d ago".
String ago(DateTime then, [DateTime? now]) {
  final mins = (now ?? DateTime.now()).difference(then).inMinutes;
  if (mins < 1) return 'just now';
  if (mins < 60) return '$mins min ago';
  if (mins < 1440) return '${(mins / 60).round()} h ago';
  return '${(mins / 1440).round()} d ago';
}
