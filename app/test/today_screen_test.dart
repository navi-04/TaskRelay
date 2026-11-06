import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskrelay/features/today/today_screen.dart';

import 'support.dart';

/// A 360dp-wide phone. Tall by default so a whole day is on screen (logic tests); pass a real height to test layout.
void phone(WidgetTester tester, {double heightDp = 2400}) {
  tester.view.physicalSize = Size(1080, heightDp * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

Future<FakeServer> open(WidgetTester tester, {Map<String, Reply>? overrides, ThemeMode mode = ThemeMode.light, FakeBridge? bridge, double heightDp = 2400}) async {
  phone(tester, heightDp: heightDp);
  final server = FakeServer(overrides: overrides);
  await pumpWith(tester, const TodayScreen(), server: server, mode: mode, bridge: bridge);
  await tester.pumpAndSettle();
  return server;
}

Map<String, dynamic> body(Seen s) => jsonDecode(s.body) as Map<String, dynamic>;

Future<void> openMenu(WidgetTester tester, String title, String item) async {
  await tester.tap(find.byTooltip('More for $title'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(item).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows a loading skeleton, then the day: summary, Top 3, overdue and the other tasks', (tester) async {
    phone(tester);
    final server = FakeServer();
    await pumpWith(tester, const TodayScreen(), server: server);
    expect(find.bySemanticsLabel('Loading'), findsOneWidget); // first frame: skeleton, not a blank screen
    await tester.pumpAndSettle();

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Team standup'), findsOneWidget);
    expect(find.textContaining('Top 3 for today'), findsOneWidget);
    expect(find.textContaining('Overdue · 1'), findsOneWidget);
    expect(find.text('Renew passport'), findsOneWidget);
    expect(find.text('Write quarterly report'), findsOneWidget);
    expect(find.byIcon(Icons.local_fire_department_outlined), findsWidgets); // streak or habit streak (an icon, never an emoji)
    expect(find.text('Add task'), findsWidgets); // the FAB
  });

  testWidgets('lays out without overflow on a small phone with the largest text size, in both themes', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      await open(tester, mode: mode, heightDp: 640);
      expect(find.text('Team standup'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '$mode');
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('renders in the Black theme too', (tester) async {
    await open(tester, mode: ThemeMode.dark);
    expect(find.text('Team standup'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed load shows a message and Retry, and Retry recovers', (tester) async {
    var offline = true;
    await open(tester, overrides: {'GET /tasks': (_) => offline ? throw const SocketException('offline') : FakeServer.json(fixture('day-view'))});
    expect(find.textContaining('Can’t reach TaskRelay'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Team standup'), findsNothing);

    offline = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Team standup'), findsOneWidget);
  });

  testWidgets('an empty day shows an empty state, not a blank list', (tester) async {
    final empty = {
      'date': '2026-11-06', 'today': '2026-11-06', 'tasks': [], 'top': [],
      'summary': {'planned': 0, 'done': 0, 'planned_min': 0, 'done_min': 0},
      'overdue': {'items': [], 'count': 0},
    };
    await open(tester, overrides: {'GET /tasks': (_) => FakeServer.json(empty)});
    expect(find.text('A clear day'), findsOneWidget);
    expect(find.text('Nothing planned'), findsOneWidget);
    expect(find.textContaining('Overdue'), findsNothing);
  });

  testWidgets('going over the daily limit says so in words (not only with a bar)', (tester) async {
    final tight = {...(fixture('settings') as Map<String, dynamic>), 'daily_time_limit_min': 60};
    await open(tester, overrides: {'GET /settings': (_) => FakeServer.json(tight)});
    expect(find.textContaining('over your daily limit'), findsOneWidget);
  });

  testWidgets('ticking a task sends an idempotent "done" for that exact day and asks the phone to re-sync', (tester) async {
    final bridge = FakeBridge();
    final server = await open(tester, bridge: bridge);
    await tester.tap(find.bySemanticsLabel('Mark done: Write quarterly report'));
    await tester.pumpAndSettle();

    final put = server.where('PUT', '/tasks/fx-task-report/days/2026-11-06').single;
    expect(body(put), {'status': 'done'});
    expect(bridge.syncRequests, greaterThan(0));
    // and the screen was refreshed from the server afterwards
    expect(server.where('GET', '/tasks').length, greaterThanOrEqualTo(2));
  });

  testWidgets('a failed tick is reported and nothing pretends it worked', (tester) async {
    await open(tester, overrides: {'PUT /tasks/fx-task-report/days/2026-11-06': (_) => FakeServer.error(500, 'internal', 'boom')});
    await tester.tap(find.bySemanticsLabel('Mark done: Write quarterly report'));
    await tester.pumpAndSettle();
    expect(find.textContaining('server had a problem'), findsOneWidget);
    expect(find.bySemanticsLabel('Mark done: Write quarterly report'), findsOneWidget); // still not done
  });

  testWidgets('deleting a one-off asks first, then offers Undo, and Undo restores it', (tester) async {
    final server = await open(tester);
    await openMenu(tester, 'Write quarterly report', 'Delete');
    expect(find.text('Delete “Write quarterly report”?'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Delete'));
    await tester.pumpAndSettle();

    final del = server.where('DELETE', '/tasks/fx-task-report').single;
    expect(del.query, {'scope': 'all'});
    expect(find.text('Deleted “Write quarterly report”'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(server.where('POST', '/tasks/fx-task-report/restore'), hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('deleting a repeating task offers the three scopes; ending the series is undone by putting the old end date back', (tester) async {
    final server = await open(tester);
    await openMenu(tester, 'Gym', 'Delete');
    expect(find.textContaining('Just Fri, 6 Nov'), findsOneWidget);
    expect(find.text('This and all following days'), findsOneWidget);
    expect(find.text('The whole series'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'This and all following days'));
    await tester.pumpAndSettle();
    expect(server.where('DELETE', '/tasks/fx-task-gym').single.query, {'scope': 'from:2026-11-06'});

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    final patch = server.where('PATCH', '/tasks/fx-task-gym').single;
    expect(body(patch), {'recur_until': null});
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('skipping one day of a repeating task is undone by reopening that day', (tester) async {
    final server = await open(tester);
    await openMenu(tester, 'Gym', 'Delete');
    await tester.tap(find.widgetWithText(OutlinedButton, 'Just Fri, 6 Nov'));
    await tester.pumpAndSettle();
    expect(server.where('DELETE', '/tasks/fx-task-gym').single.query, {'scope': 'day:2026-11-06'});

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(body(server.where('PUT', '/tasks/fx-task-gym/days/2026-11-06').single), {'status': 'open'});
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('starring a task replaces the Top 3 with the old list plus the new task, in order', (tester) async {
    final server = await open(tester);
    await tester.tap(find.byTooltip('Add to Top 3').first);
    await tester.pumpAndSettle();
    final put = server.where('PUT', '/days/2026-11-06/top').single;
    expect((body(put)['task_ids'] as List).take(2), ['fx-task-standup', 'fx-task-gym']); // existing order kept
    expect((body(put)['task_ids'] as List).length, 3);
  });

  testWidgets('when the Top 3 is full the other stars are disabled and say why', (tester) async {
    final day = fixture('day-view') as Map<String, dynamic>;
    final tasks = (day['tasks'] as List).map((t) => {...(t as Map<String, dynamic>)}).toList();
    const ranked = ['fx-task-standup', 'fx-task-gym', 'fx-task-meditate']; // exactly three starred; the report is not
    for (final t in tasks) {
      final i = ranked.indexOf(t['id'] as String);
      t['top_position'] = i < 0 ? null : i + 1;
    }
    final full = {...day, 'tasks': tasks, 'top': ranked};
    final server = await open(tester, overrides: {'GET /tasks': (_) => FakeServer.json(full)});
    expect(find.byTooltip('Your Top 3 is full'), findsOneWidget); // only the un-starred task's star
    expect(find.byTooltip('Remove from Top 3'), findsNWidgets(3)); // starred ones can always be un-starred

    await tester.tap(find.byTooltip('Your Top 3 is full'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(server.where('PUT', '/days/2026-11-06/top'), isEmpty);
  });

  testWidgets('"Move all to today" moves the overdue tasks and Undo moves each back to its own day', (tester) async {
    final server = await open(tester);
    await tester.tap(find.text('Move all to today'));
    await tester.pumpAndSettle();
    final move = server.where('POST', '/tasks/move').single;
    expect(body(move), {'ids': ['fx-task-old'], 'to': '2026-11-06'});

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    final moves = server.where('POST', '/tasks/move').toList();
    expect(body(moves.last), {'ids': ['fx-task-old'], 'to': '2026-11-01'});
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('quick add creates the task for the viewed day with a client-chosen id, then clears the box', (tester) async {
    final server = await open(tester);
    await tester.enterText(find.byType(TextField).first, '  Call the dentist  ');
    await tester.tap(find.byTooltip('Add task'));
    await tester.pumpAndSettle();

    final post = server.where('POST', '/tasks').single;
    final b = body(post);
    expect(b['title'], 'Call the dentist');
    expect(b['due_date'], '2026-11-06');
    expect(b['duration_min'], 30);
    expect(b['id'], matches(RegExp(r'^[0-9a-f-]{36}$')));
    expect((tester.widget<TextField>(find.byType(TextField).first)).controller!.text, isEmpty);
  });

  testWidgets('an empty quick-add does nothing', (tester) async {
    final server = await open(tester);
    await tester.tap(find.byTooltip('Add task'));
    await tester.pumpAndSettle();
    expect(server.where('POST', '/tasks'), isEmpty);
  });

  testWidgets('tasks changed by Claude carry a visible badge', (tester) async {
    final day = fixture('day-view') as Map<String, dynamic>;
    final tasks = (day['tasks'] as List).map((t) => {...(t as Map<String, dynamic>)}).toList();
    tasks.firstWhere((t) => t['id'] == 'fx-task-report')
      ..['updated_by'] = 'ai'
      ..['updated_at'] = DateTime.now().toUtc().toIso8601String();
    await open(tester, overrides: {'GET /tasks': (_) => FakeServer.json({...day, 'tasks': tasks})});
    expect(find.text('Claude'), findsOneWidget);
  });
}
