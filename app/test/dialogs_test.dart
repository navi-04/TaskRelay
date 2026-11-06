import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskrelay/features/profile/profile_screen.dart';

import 'support.dart';

// Regression: Profile -> edit a label -> Cancel showed Flutter's red error screen. The dialog's controller was disposed the moment
// `showDialog` returned, while the dialog was still animating out with its TextField on screen ("used after being disposed").
// A widget test fails on any such exception, so every dialog that takes text is driven through Cancel, and Save.

Future<FakeServer> openProfile(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 15000); // tall: the Profile list is lazy, and the labels card is far down
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  final server = FakeServer();
  await pumpWith(tester, const ProfileScreen(), server: server);
  await tester.pumpAndSettle();
  return server;
}

/// Everything is looked up inside the open dialog: the Profile screen behind it has its own Save buttons and text fields.
Finder inDialog(Finder f) => find.descendant(of: find.byType(AlertDialog), matching: f);

Future<void> openFromScreen(WidgetTester tester, String text) async {
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(inDialog(find.text(text)));
  await tester.pumpAndSettle();
}

void main() {
  group('label editor', () {
    testWidgets('Edit then Cancel closes the dialog cleanly (the reported red screen)', (tester) async {
      await openProfile(tester);
      await tester.tap(find.byTooltip('Rename Low'));
      await tester.pumpAndSettle();
      expect(find.text('Rename “Low”'), findsOneWidget);

      await tapText(tester, 'Cancel');
      expect(tester.takeException(), isNull);
      expect(find.text('Rename “Low”'), findsNothing);
    });

    testWidgets('Edit then Save sends the new name and closes cleanly', (tester) async {
      final server = await openProfile(tester);
      await tester.tap(find.byTooltip('Rename Low'));
      await tester.pumpAndSettle();
      await tester.enterText(inDialog(find.byType(TextField)), '  Someday  ');
      await tapText(tester, 'Save');

      expect(tester.takeException(), isNull);
      final patch = server.where('PATCH', '/labels/label-priority-1').single;
      expect(jsonDecode(patch.body), {'label': 'Someday'});
    });

    testWidgets('Saving the unchanged name sends nothing', (tester) async {
      final server = await openProfile(tester);
      await tester.tap(find.byTooltip('Rename Low'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Save');
      expect(tester.takeException(), isNull);
      expect(server.where('PATCH', '/labels/label-priority-1'), isEmpty);
    });
  });

  group('account dialogs', () {
    testWidgets('Change password: Cancel closes cleanly', (tester) async {
      await openProfile(tester);
      await openFromScreen(tester, 'Change password');
      expect(find.text('Current password'), findsOneWidget);
      await tapText(tester, 'Cancel');
      expect(tester.takeException(), isNull);
      expect(find.text('Current password'), findsNothing);
    });

    testWidgets('Change password: mismatch is explained and nothing is sent; a valid change succeeds and closes cleanly', (tester) async {
      final server = await openProfile(tester);
      await openFromScreen(tester, 'Change password');
      final fields = inDialog(find.byType(TextField));
      await tester.enterText(fields.at(0), 'old-password-1');
      await tester.enterText(fields.at(1), 'new-password-1');
      await tester.enterText(fields.at(2), 'something-else');
      await tapText(tester, 'Change');
      expect(find.textContaining('don’t match'), findsOneWidget);
      expect(server.where('POST', '/me/password'), isEmpty);

      await tester.enterText(fields.at(2), 'new-password-1');
      await tapText(tester, 'Change');
      expect(tester.takeException(), isNull);
      expect(jsonDecode(server.where('POST', '/me/password').single.body), {'current_password': 'old-password-1', 'new_password': 'new-password-1'});
      expect(find.text('Current password'), findsNothing);
      expect(find.textContaining('Password changed'), findsOneWidget);
    });

    testWidgets('Delete account: Cancel closes cleanly and deletes nothing', (tester) async {
      final server = await openProfile(tester);
      await openFromScreen(tester, 'Delete my account');
      expect(find.text('Delete your account?'), findsOneWidget);
      await tapText(tester, 'Cancel');
      expect(tester.takeException(), isNull);
      expect(find.text('Delete your account?'), findsNothing);
      expect(server.where('DELETE', '/me'), isEmpty);
    });
  });
}
