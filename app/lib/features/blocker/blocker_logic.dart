import '../../core/format.dart';
import '../../core/time.dart';
import '../../platform/platform_bridge.dart';

/// Popular social, video and feed apps, offered first in the picker when they are installed.
/// (Messaging apps are left out on purpose: people differ on whether those are a distraction.)
const suggestedPackages = <String>[
  'com.instagram.android',
  'com.google.android.youtube',
  'com.facebook.katana',
  'com.twitter.android',
  'com.snapchat.android',
  'com.zhiliaoapp.musically',
  'com.ss.android.ugc.trill',
  'com.reddit.frontpage',
  'com.netflix.mediaclient',
  'com.pinterest',
  'tv.twitch.android.app',
  'com.google.android.apps.youtube.music',
];

/// The most use times and apps the phone keeps (the native side enforces the same limits).
const maxUseWindows = 14;

/// The gaps of at least [minLength] minutes between [busy] blocks inside [from]..[to] (minutes since midnight, 6:00-23:00 by default).
List<TimeBlock> freeSlots(
  Iterable<TimeBlock> busy, {
  int from = 360,
  int to = 1380,
  int minLength = 30,
}) {
  final sorted = busy.where((b) => b.end > from && b.start < to).toList()
    ..sort((a, b) => a.start.compareTo(b.start));
  final out = <TimeBlock>[];
  var cursor = from;
  for (final b in sorted) {
    if (b.start - cursor >= minLength) out.add(TimeBlock(cursor, b.start));
    if (b.end > cursor) cursor = b.end;
  }
  if (to - cursor >= minLength) out.add(TimeBlock(cursor, to));
  return out;
}

/// One sentence for what the blocker is doing right now. [clock] turns a minute of the day into the device's clock style.
String blockerStatusText(
  BlockerDecision d, {
  required String Function(int minute) clock,
}) {
  switch (d.code) {
    case 'off':
      return 'Blocking is off.';
    case 'no_data':
      return 'Waiting for your tasks to sync. Nothing is blocked until they arrive.';
    case 'all_done':
      return 'Allowed: all your tasks are done.';
    case 'free_time':
      return 'Allowed: no task is running right now.';
    case 'in_window':
      return d.untilMin == null
          ? 'Allowed: this is a use time.'
          : 'Allowed until ${clock(d.untilMin!)}.';
    case 'tasks_left':
      final overdue = d.overdue > 0 ? ' and ${d.overdue} overdue' : '';
      return 'Blocked: ${plural(d.left, 'task')} left today$overdue.';
    case 'task_block':
      final until = d.untilMin == null ? '' : ' until ${clock(d.untilMin!)}';
      return d.title == null
          ? 'Blocked: a task is running$until.'
          : 'Blocked: “${d.title}” is running$until.';
    case 'outside_windows':
      return d.nextStartMin == null
          ? 'Blocked: no use time is left today.'
          : 'Blocked until ${clock(d.nextStartMin!)}.';
    default:
      return d.blocked ? 'Blocked.' : 'Allowed.';
  }
}

/// "6:00 PM – 7:30 PM · Every day" / "· Mon Wed Fri".
String useWindowLabel(
  UseWindow w, {
  required String Function(int minute) clock,
}) {
  final days = w.isEveryDay
      ? 'Every day'
      : repeatLabel(repeating: true, days: w.days);
  return '${clock(hhmmToMinutes(w.start))} – ${clock(hhmmToMinutes(w.end))} · $days';
}

/// Two windows that share a weekday and overlap in time (the list should not hold duplicates).
bool windowsOverlap(UseWindow a, UseWindow b) {
  if (!a.days.any(b.days.contains)) return false;
  return hhmmToMinutes(a.start) < hhmmToMinutes(b.end) &&
      hhmmToMinutes(b.start) < hhmmToMinutes(a.end);
}
