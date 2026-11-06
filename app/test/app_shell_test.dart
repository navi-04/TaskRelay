import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskrelay/features/shell/app_shell.dart';
import 'package:taskrelay/platform/platform_bridge.dart';

import 'support.dart';

Future<void> openShell(WidgetTester tester, SyncStatus status) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await pumpWith(tester, const AppShell(), server: FakeServer(), bridge: FakeBridge(status: status));
  await tester.pumpAndSettle();
}

void main() {
  group('permission banner', () {
    testWidgets('is not shown to someone with nothing to ring, even if permissions are missing', (tester) async {
      await openShell(tester, const SyncStatus(signedIn: true, armedCount: 0, notificationsAllowed: false, exactAlarmAllowed: false));
      expect(find.textContaining('Allow “'), findsNothing);
    });

    testWidgets('is shown once alarms are armed and a permission is missing; names the most important one', (tester) async {
      await openShell(tester, const SyncStatus(signedIn: true, armedCount: 2, notificationsAllowed: false, exactAlarmAllowed: false));
      expect(find.textContaining('Allow “Notifications”'), findsOneWidget);
      expect(find.text('Fix'), findsOneWidget);
    });

    testWidgets('does not nag about exact alarms: task alarms use setAlarmClock, which does not need that permission', (tester) async {
      await openShell(tester, const SyncStatus(signedIn: true, armedCount: 1, exactAlarmAllowed: false));
      expect(find.textContaining('Allow “'), findsNothing);
    });

    testWidgets('moves on to the full-screen permission once notifications are allowed', (tester) async {
      await openShell(tester, const SyncStatus(signedIn: true, armedCount: 1, exactAlarmAllowed: false, fullScreenIntentAllowed: false));
      expect(find.textContaining('Allow “Full-screen alarms”'), findsOneWidget);
    });

    testWidgets('can be dismissed', (tester) async {
      await openShell(tester, const SyncStatus(signedIn: true, armedCount: 1, fullScreenIntentAllowed: false));
      expect(find.textContaining('Allow “Full-screen alarms”'), findsOneWidget);
      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Allow “'), findsNothing);
    });

    testWidgets('is not shown when everything is allowed', (tester) async {
      await openShell(tester, const SyncStatus(signedIn: true, armedCount: 5));
      expect(find.textContaining('Allow “'), findsNothing);
    });
  });

  testWidgets('the widget "+" opens the add form even when the app was already running', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final bridge = FakeBridge();
    await pumpWith(tester, const AppShell(), server: FakeServer(), bridge: bridge);
    await tester.pumpAndSettle();
    expect(find.text('New task'), findsNothing, reason: 'no form at startup');

    // the user taps the widget's "+" while TaskRelay is in the background, then it comes forward
    for (final s in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    bridge.pendingLaunchAction = 'add';
    for (final s in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    await tester.pumpAndSettle();
    expect(find.text('New task'), findsOneWidget, reason: 'the add form is open');
    expect(bridge.pendingLaunchAction, isNull, reason: 'consumed, so a later resume does not reopen the form');
  });

  testWidgets('four tabs, and back from another tab returns to Today first', (tester) async {
    await openShell(tester, const SyncStatus(signedIn: true));
    for (final label in ['Today', 'Calendar', 'Sheet', 'Profile']) {
      expect(find.text(label), findsWidgets);
    }
    await tester.tap(find.text('Profile').last);
    await tester.pumpAndSettle();
    expect(find.text('Appearance'), findsOneWidget);

    await tester.binding.handlePopRoute(); // the system back button
    await tester.pumpAndSettle();
    expect(find.text('Appearance'), findsNothing);
    expect(find.text('Team standup'), findsOneWidget); // Today again
  });
}
