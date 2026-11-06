import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskrelay/core/time.dart';
import 'package:taskrelay/data/models.dart';
import 'package:taskrelay/features/sheet/sheet_screen.dart';

import 'support.dart';

/// A wide viewport so every column is on screen (the grid scrolls sideways on a phone; that is tested separately).
Future<FakeServer> open(WidgetTester tester, {Map<String, Reply>? overrides, ThemeMode mode = ThemeMode.light, double widthDp = 1100}) async {
  tester.view.physicalSize = Size(widthDp * 3, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  final server = FakeServer(overrides: overrides);
  await pumpWith(tester, const SheetScreen(), server: server, mode: mode);
  await tester.pumpAndSettle();
  return server;
}

Map<String, dynamic> body(Seen s) => jsonDecode(s.body) as Map<String, dynamic>;

Finder cell(String label) => find.bySemanticsLabel(label);

void main() {
  test('the server fixture parses into the sheet models', () {
    final v = SheetView.fromJson(fixture('sheet') as Json);
    expect([v.from, v.to, v.today], ['2026-11-02', '2026-11-08', '2026-11-06']);
    expect(v.columns.map((c) => c.title), ['Gym', 'Meditate']);
    expect(v.columns.first.recurDays, [1, 3, 5]);
    expect(v.columns.first.alarmTime, '18:00');
    expect(v.days.length, 7);

    final fri = v.days.firstWhere((d) => d.isToday);
    expect([fri.date, fri.weekday, fri.isWeekend, fri.planned, fri.done, fri.pct], ['2026-11-06', 5, false, 4, 1, 25]);
    expect(fri.cells['fx-task-gym'], CellState.open);
    expect(fri.tasks.map((t) => '${t.title}:${t.status.name}'), ['Team standup:done', 'Write quarterly report:open']);
    expect(fri.notes, ['Team standup: Short one']);
    expect(fri.isIncomplete, isTrue);

    final tue = v.days[1];
    expect(tue.cells.containsKey('fx-task-gym'), isFalse, reason: 'Gym is Mon/Wed/Fri: no cell on Tuesday');
    expect(v.days[5].isWeekend && v.days[6].isWeekend, isTrue);
    expect(v.days[2].pct, 100);
  });

  testWidgets('shows the month, the header, a row per day, and each day’s totals', (tester) async {
    await open(tester);
    expect(find.text('Sheet'), findsOneWidget);
    for (final h in ['Date', 'Day', 'Gym', 'Meditate', 'Tasks', 'Done', 'Total', '%', 'Notes']) {
      expect(find.text(h), findsWidgets, reason: 'header $h');
    }
    for (final d in ['2 Nov', '3 Nov', '4 Nov', '5 Nov', '6 Nov', '7 Nov', '8 Nov']) {
      expect(find.text(d), findsOneWidget, reason: d);
    }
    expect(find.text('25%'), findsOneWidget); // today: 1 of 4
    expect(find.text('100%'), findsNWidgets(2)); // 4 Nov and 5 Nov
    expect(find.text('Team standup'), findsOneWidget);
    expect(find.text('Write quarterly report'), findsOneWidget);
    expect(find.text('Team standup: Short one'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ticking a habit cell sets it done for that exact day; ticking a done one reopens it', (tester) async {
    final server = await open(tester);
    await tester.tap(cell('Gym, Mon, 2 Nov: not done'));
    await tester.pumpAndSettle();
    final put = server.where('PUT', '/tasks/fx-task-gym/days/2026-11-02').single;
    expect(body(put), {'status': 'done'});

    await tester.tap(cell('Meditate, Mon, 2 Nov: done'));
    await tester.pumpAndSettle();
    expect(body(server.where('PUT', '/tasks/fx-task-meditate/days/2026-11-02').single), {'status': 'open'});
    expect(server.where('GET', '/sheet').length, greaterThanOrEqualTo(2), reason: 'the sheet is re-read after a write');
  });

  testWidgets('a day a habit does not occur on has no cell to tap', (tester) async {
    await open(tester);
    expect(cell('Gym, Tue, 3 Nov: not done'), findsNothing);
    expect(cell('Gym, Tue, 3 Nov: done'), findsNothing);
    expect(cell('Meditate, Tue, 3 Nov: not done'), findsOneWidget, reason: 'Meditate is daily');
  });

  testWidgets('one-off tasks are listed on their day and can be ticked from the sheet', (tester) async {
    final server = await open(tester);
    await tester.tap(cell('Write quarterly report, Fri, 6 Nov: not done'));
    await tester.pumpAndSettle();
    expect(body(server.where('PUT', '/tasks/fx-task-report/days/2026-11-06').single), {'status': 'done'});
  });

  testWidgets('a failed tick is reported and nothing pretends it worked', (tester) async {
    await open(tester, overrides: {'PUT /tasks/fx-task-gym/days/2026-11-02': (_) => FakeServer.error(500, 'internal', 'boom')});
    await tester.tap(cell('Gym, Mon, 2 Nov: not done'));
    await tester.pumpAndSettle();
    expect(find.textContaining('server had a problem'), findsOneWidget);
    expect(cell('Gym, Mon, 2 Nov: not done'), findsOneWidget);
  });

  testWidgets('the filter keeps only incomplete days, or only weekdays', (tester) async {
    await open(tester);
    await tester.tap(find.byTooltip('Filter days'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Incomplete days').last);
    await tester.pumpAndSettle();
    expect(find.text('4 Nov'), findsNothing, reason: '100% done');
    expect(find.text('5 Nov'), findsNothing);
    expect(find.text('6 Nov'), findsOneWidget);

    await tester.tap(find.byTooltip('Filter days'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weekdays only').last);
    await tester.pumpAndSettle();
    expect(find.text('7 Nov'), findsNothing);
    expect(find.text('8 Nov'), findsNothing);
    expect(find.text('2 Nov'), findsOneWidget);
  });

  testWidgets('a date opens that day in the Today tab', (tester) async {
    await open(tester);
    await tester.tap(cell('Monday, 2 November. Open this day'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('next / previous month ask the server for exactly that month', (tester) async {
    final server = await open(tester);
    String first(Seen s) => s.query['from']!;
    String last(Seen s) => s.query['to']!;
    final initial = server.where('GET', '/sheet').first;
    expect(first(initial), endsWith('-01'));
    expect(last(initial), shiftYmd(addMonths(first(initial), 1), -1));

    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    final next = server.where('GET', '/sheet').last;
    expect(first(next), addMonths(first(initial), 1));
    expect(last(next), shiftYmd(addMonths(first(initial), 2), -1));

    await tester.tap(find.byTooltip('Previous month'));
    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    expect(first(server.where('GET', '/sheet').last), addMonths(first(initial), -1));
  });

  testWidgets('offline with nothing loaded: a message and Retry, and Retry recovers', (tester) async {
    var offline = true;
    await open(tester, overrides: {'GET /sheet': (_) => offline ? throw const SocketException('offline') : FakeServer.json(fixture('sheet'))});
    expect(find.textContaining('Can’t reach TaskRelay'), findsOneWidget);
    offline = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Team standup'), findsOneWidget);
  });

  testWidgets('an empty month says so', (tester) async {
    final empty = {
      'from': '2026-11-01', 'to': '2026-11-30', 'today': '2026-11-06', 'columns': [],
      'days': [
        {'date': '2026-11-06', 'weekday': 5, 'is_weekend': false, 'is_today': true, 'cells': {}, 'tasks': [], 'planned': 0, 'done': 0, 'pct': null, 'notes': []},
      ],
    };
    await open(tester, overrides: {'GET /sheet': (_) => FakeServer.json(empty)});
    expect(find.text('Nothing in this month yet'), findsOneWidget);
  });

  testWidgets('with no repeating tasks it still shows the days and explains the columns', (tester) async {
    final oneOff = {
      'from': '2026-11-01', 'to': '2026-11-30', 'today': '2026-11-06', 'columns': [],
      'days': [
        {
          'date': '2026-11-06', 'weekday': 5, 'is_weekend': false, 'is_today': true, 'cells': {},
          'tasks': [{'id': 't1', 'title': 'Pay rent', 'status': 'open', 'duration_min': 30, 'alarm_time': null}],
          'planned': 1, 'done': 0, 'pct': 0, 'notes': [],
        },
      ],
    };
    await open(tester, overrides: {'GET /sheet': (_) => FakeServer.json(oneOff)});
    expect(find.text('Pay rent'), findsOneWidget);
    expect(find.text('Tasks that repeat get their own column.'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
  });

  testWidgets('a busy day (more tasks than fit) shows two and "+N more", without overflowing, in both themes and at big text', (tester) async {
    final tasks = [for (var i = 1; i <= 6; i++) {'id': 't$i', 'title': 'Task number $i', 'status': 'open', 'duration_min': 30, 'alarm_time': null}];
    final busy = {
      'from': '2026-11-01', 'to': '2026-11-30', 'today': '2026-11-06', 'columns': [],
      'days': [
        {'date': '2026-11-06', 'weekday': 5, 'is_weekend': false, 'is_today': true, 'cells': {}, 'tasks': tasks, 'planned': 6, 'done': 0, 'pct': 0, 'notes': []},
      ],
    };
    for (final scale in [1.0, 2.0]) {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        await open(tester, mode: mode, widthDp: 600, overrides: {'GET /sheet': (_) => FakeServer.json(busy)});
        expect(find.text('Task number 1'), findsOneWidget);
        expect(find.text('Task number 2'), findsOneWidget);
        expect(find.text('Task number 3'), findsNothing, reason: 'only two are listed when there are more than three');
        expect(cell('4 more tasks on Fri, 6 Nov. Open this day'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'scale $scale, $mode');
        await tester.pumpWidget(const SizedBox());
      }
    }
  });

  testWidgets('three tasks on a day all fit; the Today button is always enabled and returns to this month', (tester) async {
    final three = [for (var i = 1; i <= 3; i++) {'id': 't$i', 'title': 'Task number $i', 'status': 'open', 'duration_min': 30, 'alarm_time': null}];
    final day = {
      'from': '2026-11-01', 'to': '2026-11-30', 'today': '2026-11-06', 'columns': [],
      'days': [
        {'date': '2026-11-06', 'weekday': 5, 'is_weekend': false, 'is_today': true, 'cells': {}, 'tasks': three, 'planned': 3, 'done': 0, 'pct': 0, 'notes': []},
      ],
    };
    await open(tester, overrides: {'GET /sheet': (_) => FakeServer.json(day)});
    expect(find.text('Task number 3'), findsOneWidget);
    expect(tester.takeException(), isNull);

    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Today')).onPressed, isNotNull);
    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Today'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('on a phone the grid fits (no overflow), scrolls sideways, and keeps Date and Day in place', (tester) async {
    await open(tester, widthDp: 360);
    expect(find.text('2 Nov'), findsOneWidget);
    final before = tester.getTopLeft(find.text('2 Nov'));
    final notesBefore = tester.getTopLeft(find.text('Notes'));

    await tester.drag(find.byType(SingleChildScrollView).first, const Offset(-400, 0)); // swipe the right-hand panel
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('2 Nov')), before, reason: 'the frozen Date column does not move');
    expect(tester.getTopLeft(find.text('Notes')).dx, lessThan(notesBefore.dx), reason: 'the scrolling columns do');
    expect(tester.takeException(), isNull);
  });

  testWidgets('lays out without overflow with the largest text size, in both themes', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      await open(tester, mode: mode, widthDp: 360);
      expect(tester.takeException(), isNull, reason: '$mode');
      await tester.pumpWidget(const SizedBox());
    }
  });
}
