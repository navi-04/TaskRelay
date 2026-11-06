import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskrelay/features/today/today_screen.dart';
import 'package:taskrelay/shared/widgets.dart';
import 'package:taskrelay/state/providers.dart';

import 'support.dart';

// Offline with data already on screen: the data must stay, and a banner must say the refresh failed (and be readable).

double lum(int v) {
  final c = v / 255;
  return c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

void main() {
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('a failed refresh keeps the day on screen and shows a readable banner in ${mode == ThemeMode.light ? 'White' : 'Black'}', (tester) async {
      tester.view.physicalSize = const Size(1080, 3000);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      var offline = false;
      final key = GlobalKey();
      final container = await pumpWith(
        tester,
        RepaintBoundary(key: key, child: const TodayScreen()),
        server: FakeServer(overrides: {'GET /tasks': (_) => offline ? throw const SocketException('offline') : FakeServer.json(fixture('day-view'))}),
        mode: mode,
      );
      await tester.pumpAndSettle();
      expect(find.text('Team standup'), findsOneWidget);

      offline = true;
      container.invalidate(dayViewProvider);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(find.text('Team standup'), findsOneWidget, reason: 'the stale day stays on screen');
      expect(find.byType(ErrorBanner), findsOneWidget);
      expect(find.textContaining('Couldn’t refresh'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      // …and it is actually drawn: its own rectangle has text-vs-page contrast.
      final outer = tester.getRect(find.byKey(key));
      final rect = tester.getRect(find.byType(ErrorBanner));
      final bytes = await tester.runAsync(() async {
        final image = await tester.renderObject<RenderRepaintBoundary>(find.byKey(key)).toImage(pixelRatio: 2.0);
        return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      });
      final width = (outer.width * 2).round();
      final bins = List<int>.filled(16, 0);
      var total = 0;
      for (var y = ((rect.top - outer.top) * 2).floor(); y < ((rect.bottom - outer.top) * 2).ceil(); y++) {
        for (var x = ((rect.left - outer.left) * 2).floor(); x < ((rect.right - outer.left) * 2).ceil(); x++) {
          bins[bytes!.getUint8((y * width + x) * 4) >> 4]++;
          total++;
        }
      }
      final tones = [for (var i = 0; i < 16; i++) if (bins[i] >= total * 0.01) i * 16 + 8];
      var best = 1.0;
      for (final a in tones) {
        for (final b in tones) {
          best = math.max(best, (math.max(lum(a), lum(b)) + 0.05) / (math.min(lum(a), lum(b)) + 0.05));
        }
      }
      expect(best, greaterThanOrEqualTo(3.0), reason: 'banner drawn with tones $tones (rect $rect)');
    });
  }
}
