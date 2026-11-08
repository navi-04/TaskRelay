import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskrelay/data/models.dart';
import 'package:taskrelay/features/today/task_card.dart';
import 'package:taskrelay/features/today/task_form.dart';

import 'support.dart';

// Every task can have an optional start time and end time. With both, the length is theirs; with one, the estimate stands.

Task fx(String id, [Map<String, dynamic> changes = const {}]) {
  final base = (fixture('day-view')['tasks'] as List).cast<Map<String, dynamic>>().firstWhere((t) => t['id'] == id);
  return Task.fromJson({...base, ...changes});
}

Future<FakeServer> openForm(WidgetTester tester, {Task? task, FakeServer? server}) async {
  tester.view.physicalSize = const Size(1080, 4800);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  final s = server ?? FakeServer();
  await pumpWith(
    tester,
    Scaffold(body: TaskFormSheet(task: task, date: '2026-11-06', today: '2026-11-06', labels: Labels.fromJson(fixture('labels') as Json), prefill: null)),
    server: s,
  );
  await tester.pumpAndSettle();
  return s;
}

/// The one request of this kind the fake server saw, as JSON.
Map<String, dynamic> sent(FakeServer s, String method, String path) => jsonDecode(s.where(method, path).single.body) as Map<String, dynamic>;

/// Picks a time in the dialog the form opened: switches to typing, enters the hour, and confirms. (AM/PM keeps the picker's default.)
Future<void> pickHour(WidgetTester tester, int hour) async {
  await tester.tap(find.byIcon(Icons.keyboard_outlined));
  await tester.pumpAndSettle();
  // inside the dialog: the form behind it has text fields too
  await tester.enterText(find.descendant(of: find.byType(Dialog), matching: find.byType(TextField)).first, '$hour');
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

void main() {
  group('the form', () {
    testWidgets('a new task starts with no times and the usual duration controls', (tester) async {
      await openForm(tester);
      expect(find.text('Add start time'), findsOneWidget);
      expect(find.text('Add end time'), findsOneWidget);
      expect(find.text('Time needed (minutes)'), findsOneWidget);
      expect(find.textContaining('Takes'), findsNothing);
    });

    testWidgets('a task with both times shows the length they make, and the duration controls step aside', (tester) async {
      final s = await openForm(tester, task: fx('fx-task-gym')); // 18:00-19:00
      expect(find.textContaining('Start time: '), findsOneWidget);
      expect(find.textContaining('End time: '), findsOneWidget);
      expect(find.text('Takes 1h, from the start and end time.'), findsOneWidget);
      expect(find.text('Time needed (minutes)'), findsNothing);
      expect(find.widgetWithText(TextField, 'Minutes (1–1440)'), findsNothing);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final body = sent(s, 'PATCH', '/tasks/fx-task-gym');
      expect([body['start_time'], body['end_time'], body['duration_min']], ['18:00', '19:00', 60]);
    });

    testWidgets('removing the end keeps the length it made, as the server does, and sends null for the end', (tester) async {
      final s = await openForm(tester, task: fx('fx-task-standup')); // 09:30-09:45 -> 15 min
      await tester.tap(find.byTooltip('Remove end time'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Takes'), findsNothing);
      expect(find.text('Time needed (minutes)'), findsOneWidget);
      expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Minutes (1–1440)')).controller!.text, '15');

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final body = sent(s, 'PATCH', '/tasks/fx-task-standup');
      expect([body['start_time'], body['end_time'], body['duration_min']], ['09:30', null, 15]);
    });

    testWidgets('a start alone leaves the estimate to you', (tester) async {
      final s = await openForm(tester, task: fx('fx-task-report')); // 14:00, 90 min
      expect(find.textContaining('Takes'), findsNothing);
      expect(find.text('Time needed (minutes)'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final body = sent(s, 'PATCH', '/tasks/fx-task-report');
      expect([body['start_time'], body['end_time'], body['duration_min']], ['14:00', null, 90]);
    });

    testWidgets('an end that is not after the start is refused before anything is sent', (tester) async {
      final s = await openForm(tester, task: fx('fx-task-report', {'start_time': null})); // no times yet
      await tester.ensureVisible(find.text('Add start time'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add start time'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK')); // the picker opens on 9:00 AM
      await tester.pumpAndSettle();
      expect(find.textContaining('Start time: '), findsOneWidget);

      await tester.tap(find.text('Add end time'));
      await tester.pumpAndSettle();
      await pickHour(tester, 8); // 8:00 AM, before the 9:00 AM start
      expect(find.textContaining('End time must be after the start time.'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save')).onPressed, isNull);

      await tester.tap(find.widgetWithText(OutlinedButton, 'End time: 8:00 AM'));
      await tester.pumpAndSettle();
      await pickHour(tester, 10); // fixed
      expect(find.textContaining('End time must be after the start time.'), findsNothing);
      expect(find.text('Takes 1h, from the start and end time.'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final body = sent(s, 'PATCH', '/tasks/fx-task-report');
      expect([body['start_time'], body['end_time'], body['duration_min']], ['09:00', '10:00', 60]);
    });

    testWidgets('a start time offers to ring at the start', (tester) async {
      final s = await openForm(tester, task: fx('fx-task-gym', {'alarm_time': null}));
      await tester.ensureVisible(find.text('Remind me at the start time'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remind me at the start time'));
      await tester.pumpAndSettle();
      expect(find.text('Remind me at the start time'), findsNothing, reason: 'the reminder now equals the start');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(sent(s, 'PATCH', '/tasks/fx-task-gym')['alarm_time'], '18:00');
    });

    testWidgets('a server complaint about the end time shows under the fields and the form stays open', (tester) async {
      final server = FakeServer(overrides: {
        'PATCH /tasks/fx-task-gym': (_) => FakeServer.json({
              'error': {
                'code': 'validation_error',
                'message': 'Invalid',
                'issues': [
                  {'path': 'end_time', 'message': 'End time must be after the start time'},
                ],
              },
            }, 400),
      });
      await openForm(tester, task: fx('fx-task-gym'), server: server);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('End time must be after the start time'), findsOneWidget);
      expect(find.textContaining('Please fix the highlighted fields.'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget, reason: 'still open');
    });

    testWidgets('fits a small phone at the largest text size', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        tester.view.physicalSize = const Size(1080, 4800);
        tester.view.devicePixelRatio = 3.0;
        await pumpWith(
          tester,
          Scaffold(body: TaskFormSheet(task: fx('fx-task-gym'), date: '2026-11-06', today: '2026-11-06', labels: Labels.fromJson(fixture('labels') as Json), prefill: null)),
          server: FakeServer(),
          mode: mode,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$mode');
        await tester.pumpWidget(const SizedBox());
      }
    });
  });

  group('the task card', () {
    Future<void> show(WidgetTester tester, Task t) async {
      await pumpWith(
        tester,
        Scaffold(body: TaskCard(task: t, onToggle: () {}, onStar: () {}, onMenu: (_) {})),
        server: FakeServer(),
      );
      await tester.pumpAndSettle();
    }

    Finder chip(String text) => find.text(text);

    testWidgets('both times: one block label, no separate duration', (tester) async {
      await show(tester, fx('fx-task-gym')); // 18:00-19:00, 60 min
      expect(chip('6:00 PM – 7:00 PM'), findsOneWidget);
      expect(chip('1h'), findsNothing);
    });

    testWidgets('a start alone: "from", and the estimate stays visible', (tester) async {
      await show(tester, fx('fx-task-report')); // 14:00, 90 min
      expect(chip('from 2:00 PM'), findsOneWidget);
      expect(chip('1h 30m'), findsOneWidget);
    });

    testWidgets('an end alone is a deadline: "by", and the estimate stays visible', (tester) async {
      await show(tester, fx('fx-task-report', {'start_time': null, 'end_time': '17:00'}));
      expect(chip('by 5:00 PM'), findsOneWidget);
      expect(chip('1h 30m'), findsOneWidget);
    });

    testWidgets('no times: just the estimate, as before', (tester) async {
      await show(tester, fx('fx-task-meditate'));
      expect(chip('10m'), findsOneWidget);
      expect(find.byIcon(Icons.schedule), findsNothing);
    });
  });
}
