import 'package:flutter_test/flutter_test.dart';
import 'package:taskrelay/core/time.dart';
import 'package:taskrelay/data/models.dart';
import 'package:taskrelay/features/blocker/blocker_logic.dart';
import 'package:taskrelay/platform/platform_bridge.dart';

import 'support.dart';

String clock(int m) => minutesToHhmm(m);

void main() {
  group('taskBlock: the same rule as the server (web/lib/timeblock.ts) and the phone', () {
    TimeBlock? block(String? s, String? e, [int d = 30]) => taskBlock(startTime: s, endTime: e, durationMin: d);

    test('start and end give the block; start alone lasts the duration; an end alone or nothing is no block', () {
      expect(block('09:00', '10:30', 90), const TimeBlock(540, 630));
      expect(block('09:00', null, 45), const TimeBlock(540, 585));
      expect(block(null, '17:00'), isNull);
      expect(block(null, null), isNull);
    });

    test('a block that would run past midnight is cut at midnight', () {
      expect(block('23:30', null, 120), const TimeBlock(1410, 1440));
      expect(block('00:00', '23:59'), const TimeBlock(0, 1439));
    });

    test('a block with no length is not a block', () {
      expect(block('23:59', null, 30), const TimeBlock(1439, 1440));
      expect(block('10:00', '10:00'), isNull);
    });

    test('contains() is start-inclusive and end-exclusive', () {
      const b = TimeBlock(540, 600);
      expect([b.contains(539), b.contains(540), b.contains(599), b.contains(600)], [false, true, true, false]);
      expect(b.minutes, 60);
    });

    test('clock helpers round-trip, and the end of the day reads as 00:00', () {
      expect(hhmmToMinutes('07:05'), 425);
      expect(minutesToHhmm(425), '07:05');
      expect(minutesToHhmm(1440), '00:00');
    });

    test('a task from the real fixture knows its block', () {
      final tasks = (fixture('day-view')['tasks'] as List).map((t) => Task.fromJson(t as Map<String, dynamic>)).toList();
      final byId = {for (final t in tasks) t.id: t};
      expect(byId['fx-task-standup']!.block, const TimeBlock(570, 585)); // 09:30-09:45
      expect(byId['fx-task-report']!.block, const TimeBlock(840, 930)); // 14:00 + 90 min
      expect(byId['fx-task-gym']!.block, const TimeBlock(1080, 1140)); // 18:00-19:00
      expect(byId['fx-task-meditate']!.block, isNull);
    });

    test('an old server that sends no start/end still parses (both are null)', () {
      final j = Map<String, dynamic>.from((fixture('day-view')['tasks'] as List).first as Map)
        ..remove('start_time')
        ..remove('end_time');
      final t = Task.fromJson(j);
      expect([t.startTime, t.endTime, t.block], [null, null, null]);
    });
  });

  group('freeSlots: where no task is scheduled', () {
    const b = TimeBlock.new;

    test('the gaps between blocks, at least half an hour long', () {
      expect(freeSlots([b(540, 600), b(840, 930)]), [b(360, 540), b(600, 840), b(930, 1380)]);
      expect(freeSlots([b(360, 400), b(420, 1380)]), isEmpty); // a 20-minute gap is too short to plan on
    });

    test('overlapping and unsorted blocks are merged', () {
      expect(freeSlots([b(600, 700), b(540, 660), b(650, 720)]), [b(360, 540), b(720, 1380)]);
    });

    test('only from a given minute on (the rest of today), and blocks outside the day do not matter', () {
      expect(freeSlots([b(0, 300), b(1400, 1440)]), [b(360, 1380)]);
      expect(freeSlots([b(840, 930)], from: 900), [b(930, 1380)]);
      expect(freeSlots([], from: 1370), isEmpty);
    });
  });

  group('use windows', () {
    UseWindow w(String s, String e, [List<int> days = const [1, 2, 3, 4, 5, 6, 7]]) => UseWindow(start: s, end: e, days: days);

    test('overlap needs a shared weekday AND overlapping time', () {
      expect(windowsOverlap(w('18:00', '19:00'), w('18:30', '20:00')), isTrue);
      expect(windowsOverlap(w('18:00', '19:00'), w('19:00', '20:00')), isFalse); // touching is fine
      expect(windowsOverlap(w('18:00', '19:00', [1, 2]), w('18:00', '19:00', [3, 4])), isFalse);
      expect(windowsOverlap(w('18:00', '19:00', [1, 2]), w('18:30', '19:30', [2, 3])), isTrue);
    });

    test('labels say the days', () {
      expect(useWindowLabel(w('18:00', '19:30'), clock: clock), '18:00 – 19:30 · Every day');
      expect(useWindowLabel(w('07:00', '08:00', [1, 2, 3, 4, 5]), clock: clock), '07:00 – 08:00 · Weekdays');
      expect(useWindowLabel(w('07:00', '08:00', [6, 7]), clock: clock), '07:00 – 08:00 · Weekends');
    });
  });

  group('the blocker config crosses the channel intact', () {
    test('round trip', () {
      const c = BlockerConfig(
        enabled: true,
        mode: BlockMode.setTimes,
        countOverdue: false,
        unlockWhenDone: true,
        packages: ['com.instagram.android', 'com.google.android.youtube'],
        windows: [UseWindow(start: '18:00', end: '19:30', days: [1, 3, 5])],
      );
      final back = BlockerConfig.fromMap(c.toMap());
      expect(back.toMap(), c.toMap());
      expect(back.windows.single, c.windows.single);
      expect(c.toMap()['mode'], 'set_times');
    });

    test('missing or unknown values fall back to the safe defaults (off, until done, overdue counts)', () {
      final c = BlockerConfig.fromMap({'mode': 'nonsense'});
      expect([c.enabled, c.mode, c.countOverdue, c.unlockWhenDone, c.packages, c.windows], [false, BlockMode.untilDone, true, false, isEmpty, isEmpty]);
      expect(BlockerConfig.fromMap(null).enabled, isFalse);
    });

    test('the status carries the decision', () {
      final s = BlockerStatus.fromMap({
        'serviceEnabled': true,
        'enabled': true,
        'hasData': true,
        'snapshotDate': '2026-11-06',
        'decision': {'blocked': true, 'code': 'task_block', 'left': 2, 'overdue': 0, 'title': 'Deep work', 'until_min': 630},
      });
      expect([s.serviceEnabled, s.decision.blocked, s.decision.code, s.decision.title, s.decision.untilMin], [true, true, 'task_block', 'Deep work', 630]);
      expect(BlockerStatus.fromMap(null).serviceEnabled, isFalse);
    });
  });

  group('the one-line status', () {
    String text(Map<String, Object?> m) => blockerStatusText(BlockerDecision.fromMap(m), clock: clock);

    test('says what is blocked and why', () {
      expect(text({'blocked': true, 'code': 'tasks_left', 'left': 3, 'overdue': 2}), 'Blocked: 3 tasks left today and 2 overdue.');
      expect(text({'blocked': true, 'code': 'tasks_left', 'left': 1, 'overdue': 0}), 'Blocked: 1 task left today.');
      expect(text({'blocked': true, 'code': 'task_block', 'title': 'Deep work', 'until_min': 630}), 'Blocked: “Deep work” is running until 10:30.');
      expect(text({'blocked': true, 'code': 'outside_windows', 'next_start_min': 1080}), 'Blocked until 18:00.');
      expect(text({'blocked': true, 'code': 'outside_windows'}), 'Blocked: no use time is left today.');
    });

    test('says why apps are allowed', () {
      expect(text({'code': 'all_done'}), 'Allowed: all your tasks are done.');
      expect(text({'code': 'free_time'}), 'Allowed: no task is running right now.');
      expect(text({'code': 'in_window', 'until_min': 1170}), 'Allowed until 19:30.');
      expect(text({'code': 'no_data'}), contains('Nothing is blocked until they arrive'));
      expect(text({'code': 'off'}), 'Blocking is off.');
    });
  });
}
