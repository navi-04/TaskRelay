import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskrelay/features/blocker/app_picker_screen.dart';
import 'package:taskrelay/features/blocker/blocker_card.dart';
import 'package:taskrelay/features/blocker/blocker_screen.dart';
import 'package:taskrelay/platform/platform_bridge.dart';
import 'package:taskrelay/state/providers.dart';

import 'support.dart';

/// A phone-sized window (360 x 800 dp).
void phone(WidgetTester tester, {double widthDp = 360}) {
  tester.view.physicalSize = Size(widthDp * 3, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

Future<FakeBridge> openBlocker(
  WidgetTester tester, {
  FakeBridge? bridge,
  ThemeMode mode = ThemeMode.light,
  GlobalKey? boundary,
  DateTime? now,
}) async {
  phone(tester);
  final b = bridge ?? FakeBridge();
  await pumpWith(
    tester,
    const BlockerScreen(),
    server: FakeServer(),
    bridge: b,
    mode: mode,
    boundary: boundary,
    overrides: [if (now != null) clockProvider.overrideWithValue(() => now)],
  );
  await tester.pumpAndSettle();
  return b;
}

Finder get masterSwitch => find.byType(Switch).first;

/// Scrolls a widget into view (the scroll only takes effect after a pump) so it can be tapped.
Future<void> reveal(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
}

void main() {
  group('the profile card', () {
    testWidgets('off: an invitation and a Set up button that opens the screen', (tester) async {
      phone(tester);
      await pumpWith(tester, const Scaffold(body: BlockerCard()), server: FakeServer());
      await tester.pumpAndSettle();
      expect(find.textContaining('Keep distracting apps closed until your tasks are done'), findsOneWidget);
      await tester.tap(find.text('Set up'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Block distracting apps'), findsOneWidget);
      expect(find.text('Apps to block'), findsOneWidget);
    });

    testWidgets('on: says how many apps and which rule, and warns when Accessibility is still off', (tester) async {
      phone(tester);
      final bridge = FakeBridge()
        ..blocker = const BlockerConfig(enabled: true, mode: BlockMode.freeTime, packages: ['com.instagram.android', 'com.android.chrome']);
      await pumpWith(tester, const Scaffold(body: BlockerCard()), server: FakeServer(), bridge: bridge);
      await tester.pumpAndSettle();
      expect(find.text('On: 2 apps, while a task is running.'), findsOneWidget);
      expect(find.textContaining('Needs Accessibility access'), findsOneWidget);
      expect(find.text('Manage'), findsOneWidget);

      bridge.serviceEnabled = true; // switched on in Android settings; the card re-reads on resume
      final container = ProviderScope.containerOf(tester.element(find.byType(BlockerCard)));
      container.invalidate(blockerStatusProvider);
      await tester.pumpAndSettle();
      expect(find.textContaining('Needs Accessibility access'), findsNothing);
    });
  });

  group('turning it on', () {
    testWidgets('explains the Accessibility Service first, and only opens Settings after Agree', (tester) async {
      final bridge = await openBlocker(tester);
      await tester.tap(masterSwitch);
      await tester.pumpAndSettle();

      expect(bridge.blocker.enabled, isTrue);
      expect(find.text('Allow TaskRelay to block apps'), findsOneWidget);
      final dialog = find.byType(AlertDialog);
      expect(find.descendant(of: dialog, matching: find.textContaining('does not read what is on your screen')), findsOneWidget);
      expect(find.descendant(of: dialog, matching: find.textContaining('stay on this phone')), findsOneWidget);
      expect(find.descendant(of: dialog, matching: find.textContaining('same for every accessibility service')), findsOneWidget);
      expect(bridge.accessibilityOpened, 0, reason: 'nothing opens before the user agrees');

      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(bridge.accessibilityOpened, 0);
      expect(find.textContaining('One more step'), findsOneWidget, reason: 'nothing is blocked yet, and the screen says so');

      await tester.tap(find.text('Turn on in Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agree and open settings'));
      await tester.pumpAndSettle();
      expect(bridge.accessibilityOpened, 1);
    });

    testWidgets('with the service already on there is no banner and no dialog, just what is happening now', (tester) async {
      final bridge = FakeBridge()..serviceEnabled = true;
      await openBlocker(tester, bridge: bridge);
      await tester.tap(masterSwitch);
      await tester.pumpAndSettle();
      expect(find.text('Allow TaskRelay to block apps'), findsNothing);
      expect(find.textContaining('One more step'), findsNothing);
      // no apps chosen yet: it says so instead of pretending to block
      expect(find.textContaining('Choose the apps to block below'), findsOneWidget);
    });

    testWidgets('shows the live decision once apps are chosen', (tester) async {
      final bridge = FakeBridge()
        ..serviceEnabled = true
        ..blocker = const BlockerConfig(enabled: true, packages: ['com.instagram.android']);
      await openBlocker(tester, bridge: bridge);
      expect(find.textContaining('Blocked: 3 tasks left today and 2 overdue.'), findsOneWidget);

      bridge.decision = const BlockerDecision(code: 'all_done');
      final container = ProviderScope.containerOf(tester.element(find.byType(BlockerScreen)));
      container.invalidate(blockerStatusProvider);
      await tester.pumpAndSettle();
      expect(find.textContaining('Allowed: all your tasks are done.'), findsOneWidget);
    });

    testWidgets('turning it off saves at once', (tester) async {
      final bridge = FakeBridge()
        ..serviceEnabled = true
        ..blocker = const BlockerConfig(enabled: true, packages: ['com.instagram.android']);
      await openBlocker(tester, bridge: bridge);
      await tester.tap(masterSwitch);
      await tester.pumpAndSettle();
      expect(bridge.blocker.enabled, isFalse);
      expect(bridge.blocker.packages, ['com.instagram.android'], reason: 'the apps are kept for next time');
    });
  });

  group('when to block', () {
    testWidgets('the three rules, each saved when picked; overdue and unlock-when-done follow their rule', (tester) async {
      final bridge = FakeBridge()..serviceEnabled = true;
      await openBlocker(tester, bridge: bridge);

      // until done (the default): overdue counts, and it can be switched off
      await reveal(tester, find.text('Count overdue tasks too'));
      expect(find.text('Count overdue tasks too'), findsOneWidget);
      await tester.tap(find.widgetWithText(SwitchListTile, 'Count overdue tasks too'));
      await tester.pumpAndSettle();
      expect(bridge.blocker.countOverdue, isFalse);

      await tester.tap(find.text('While a task is running'));
      await tester.pumpAndSettle();
      expect(bridge.blocker.mode, BlockMode.freeTime);
      expect(find.text('Count overdue tasks too'), findsNothing);
      expect(find.text('Use times'), findsNothing);

      await tester.tap(find.text('Only at times I choose'));
      await tester.pumpAndSettle();
      expect(bridge.blocker.mode, BlockMode.setTimes);
      expect(find.text('Use times'), findsOneWidget);
      await reveal(tester, find.text('Unlock everything when all tasks are done'));
      await tester.tap(find.widgetWithText(SwitchListTile, 'Unlock everything when all tasks are done'));
      await tester.pumpAndSettle();
      expect(bridge.blocker.unlockWhenDone, isTrue);
    });
  });

  group('use times', () {
    Future<FakeBridge> setTimesScreen(WidgetTester tester, {List<UseWindow> windows = const [], DateTime? now}) {
      final bridge = FakeBridge()
        ..serviceEnabled = true
        ..blocker = BlockerConfig(enabled: true, mode: BlockMode.setTimes, packages: const ['com.instagram.android'], windows: windows);
      return openBlocker(tester, bridge: bridge, now: now ?? DateTime(2026, 11, 6, 20, 0));
    }

    testWidgets('with none set, the apps stay blocked and the screen says so; adding one saves it', (tester) async {
      final bridge = await setTimesScreen(tester);
      expect(find.textContaining('stay blocked all day'), findsOneWidget);

      await reveal(tester, find.text('Add a use time'));
      await tester.tap(find.text('Add a use time'));
      await tester.pumpAndSettle();
      expect(find.text('Add a use time').evaluate().length, greaterThan(1), reason: 'the sheet title and the button');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(bridge.blocker.windows, [const UseWindow(start: '18:00', end: '19:00')]);
      expect(find.textContaining('Every day'), findsOneWidget);
      expect(find.textContaining('stay blocked all day'), findsNothing);
    });

    testWidgets('a use time that overlaps another is refused with a reason', (tester) async {
      await setTimesScreen(tester, windows: const [UseWindow(start: '18:00', end: '19:00')]);
      await reveal(tester, find.text('Add a use time'));
      await tester.tap(find.text('Add a use time'));
      await tester.pumpAndSettle();
      expect(find.textContaining('overlaps another use time'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save')).onPressed, isNull);
    });

    testWidgets('a use time needs at least one day', (tester) async {
      await setTimesScreen(tester);
      await reveal(tester, find.text('Add a use time'));
      await tester.tap(find.text('Add a use time'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'Mon'));
      await tester.tap(find.widgetWithText(FilterChip, 'Tue'));
      await tester.tap(find.widgetWithText(FilterChip, 'Wed'));
      await tester.tap(find.widgetWithText(FilterChip, 'Thu'));
      await tester.tap(find.widgetWithText(FilterChip, 'Fri'));
      await tester.tap(find.widgetWithText(FilterChip, 'Sat'));
      await tester.tap(find.widgetWithText(FilterChip, 'Sun'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Pick at least one day'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save')).onPressed, isNull);
      await tester.tap(find.text('Weekends'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
    });

    testWidgets('a use time can be edited and removed', (tester) async {
      final bridge = await setTimesScreen(tester, windows: const [UseWindow(start: '18:00', end: '19:00')]);
      await reveal(tester, find.textContaining('Every day'));
      await tester.tap(find.textContaining('Every day'));
      await tester.pumpAndSettle();
      expect(find.text('Edit use time'), findsOneWidget);
      await tester.tap(find.text('Weekdays'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(bridge.blocker.windows, [const UseWindow(start: '18:00', end: '19:00', days: [1, 2, 3, 4, 5])]);

      await tester.tap(find.byTooltip(RegExp('^Remove the use time')));
      await tester.pumpAndSettle();
      expect(bridge.blocker.windows, isEmpty);
    });

    testWidgets('suggests the gaps between today’s timed tasks, from now on, and a tap turns one into a use time', (tester) async {
      // the fixture day: 09:30-09:45, 14:00-15:30, 18:00-19:00. It is 10:00, so the gaps are 10-14, 15:30-18 and 19-23.
      final bridge = await setTimesScreen(tester, now: DateTime(2026, 11, 6, 10, 0));
      await reveal(tester, find.textContaining('Free for the rest of today'));
      expect(find.textContaining('Free for the rest of today'), findsOneWidget);
      expect(find.text('10:00 AM – 2:00 PM'), findsOneWidget);
      expect(find.text('3:30 PM – 6:00 PM'), findsOneWidget);
      expect(find.text('7:00 PM – 11:00 PM'), findsOneWidget);
      expect(find.text('9:30 AM – 9:45 AM'), findsNothing, reason: 'the past is not offered');

      await tester.tap(find.text('3:30 PM – 6:00 PM'));
      await tester.pumpAndSettle();
      expect(find.text('Add a use time'), findsWidgets); // the sheet opens pre-filled with the gap
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(bridge.blocker.windows, [const UseWindow(start: '15:30', end: '18:00')]);
    });
  });

  group('choosing the apps', () {
    Future<FakeBridge> openPicker(WidgetTester tester, {FakeBridge? bridge, ThemeMode mode = ThemeMode.light, GlobalKey? boundary}) async {
      phone(tester);
      final b = bridge ?? FakeBridge();
      await pumpWith(tester, const AppPickerScreen(), server: FakeServer(), bridge: b, mode: mode, boundary: boundary);
      await tester.pumpAndSettle();
      return b;
    }

    testWidgets('popular distractions that are installed come first, then everything else', (tester) async {
      await openPicker(tester);
      expect(find.text('Popular distractions'), findsOneWidget);
      expect(find.text('All apps'), findsOneWidget);
      final y = {for (final n in ['Instagram', 'YouTube', 'Calculator', 'Chrome']) n: tester.getTopLeft(find.text(n)).dy};
      expect(y['Instagram']! < y['YouTube']!, isTrue);
      expect(y['YouTube']! < y['Calculator']!, isTrue);
      expect(y['Calculator']! < y['Chrome']!, isTrue);
      expect(find.textContaining('Settings and Phone are never listed'), findsOneWidget);
    });

    testWidgets('ticking an app saves at once, unticking removes it', (tester) async {
      final bridge = await openPicker(tester);
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Instagram'));
      await tester.pumpAndSettle();
      expect(bridge.blocker.packages, ['com.instagram.android']);
      expect(find.textContaining('1 selected'), findsOneWidget);
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Chrome'));
      await tester.pumpAndSettle();
      expect(bridge.blocker.packages, ['com.instagram.android', 'com.android.chrome']);
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Instagram'));
      await tester.pumpAndSettle();
      expect(bridge.blocker.packages, ['com.android.chrome']);
    });

    testWidgets('search narrows the list', (tester) async {
      await openPicker(tester);
      await tester.enterText(find.byType(TextField), 'calc');
      await tester.pumpAndSettle();
      expect(find.text('Calculator'), findsOneWidget);
      expect(find.text('Instagram'), findsNothing);
      expect(find.text('Popular distractions'), findsNothing);
      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('No app matches that search.'), findsOneWidget);
    });

    testWidgets('at the limit, the rest cannot be ticked', (tester) async {
      final apps = [for (var i = 0; i <= maxBlockedApps; i++) InstalledApp(package: 'app.p$i', label: 'App ${i.toString().padLeft(2, '0')}')];
      final bridge = FakeBridge()
        ..apps = apps
        ..blocker = BlockerConfig(packages: [for (var i = 1; i <= maxBlockedApps; i++) 'app.p$i']);
      await openPicker(tester, bridge: bridge);
      expect(find.textContaining('up to $maxBlockedApps apps'), findsOneWidget);
      expect(tester.widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, 'App 00')).onChanged, isNull);
    });
  });

  group('black and white, in both themes', () {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      final name = mode == ThemeMode.light ? 'White' : 'Black';

      testWidgets('the screen, its banner, the set-times card and the dialogs have no coloured pixel in $name', (tester) async {
        final boundary = GlobalKey();
        final bridge = FakeBridge()
          ..blocker = const BlockerConfig(enabled: true, mode: BlockMode.setTimes, packages: ['com.instagram.android'], windows: [UseWindow(start: '18:00', end: '19:00', days: [1, 2, 3])]);
        await openBlocker(tester, bridge: bridge, mode: mode, boundary: boundary, now: DateTime(2026, 11, 6, 10, 0));

        Future<void> expectGrey(String what) async {
          final r = await colouredPixels(tester, boundary);
          expect(r.coloured, 0, reason: '$what: ${r.coloured} coloured pixels (max spread ${r.worst})');
        }

        await expectGrey('the screen with the "one more step" banner');
        expect(find.textContaining('One more step'), findsOneWidget);

        await tester.tap(find.text('Turn on in Settings'));
        await tester.pumpAndSettle();
        await expectGrey('the disclosure dialog');
        await tester.tap(find.text('Not now'));
        await tester.pumpAndSettle();

        bridge.serviceEnabled = true;
        ProviderScope.containerOf(tester.element(find.byType(BlockerScreen))).invalidate(blockerStatusProvider);
        await tester.pumpAndSettle();
        await expectGrey('the live status');

        await reveal(tester, find.text('Add a use time'));
        await tester.tap(find.text('Add a use time'));
        await tester.pumpAndSettle();
        await expectGrey('the use time sheet');
      });

      testWidgets('the app picker has no coloured pixel in $name', (tester) async {
        phone(tester);
        final boundary = GlobalKey();
        await pumpWith(tester, const AppPickerScreen(), server: FakeServer(), mode: mode, boundary: boundary);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(CheckboxListTile, 'Instagram'));
        await tester.pumpAndSettle();
        final r = await colouredPixels(tester, boundary);
        expect(r.coloured, 0, reason: '${r.coloured} coloured pixels (max spread ${r.worst})');
      });
    }
  });

  testWidgets('everything fits at the largest text size on a small phone, in both themes', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      final bridge = FakeBridge()
        ..serviceEnabled = true
        ..blocker = const BlockerConfig(enabled: true, mode: BlockMode.setTimes, packages: ['com.instagram.android', 'com.google.android.youtube'], windows: [UseWindow(start: '18:00', end: '19:30', days: [1, 3, 5])]);
      await openBlocker(tester, bridge: bridge, mode: mode, now: DateTime(2026, 11, 6, 10, 0));
      expect(tester.takeException(), isNull, reason: 'blocker screen in $mode');
      await reveal(tester, find.text('Add a use time'));
      await tester.tap(find.text('Add a use time'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'use time sheet in $mode');
      await tester.pumpWidget(const SizedBox());

      await pumpWith(tester, const AppPickerScreen(), server: FakeServer(), mode: mode);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'picker in $mode');
      await tester.pumpWidget(const SizedBox());
    }
  });
}
