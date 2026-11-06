import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskrelay/data/models.dart';
import 'package:taskrelay/features/today/task_form.dart';

import 'support.dart';

// The real form on a real phone showed blank labels on its unselected chips in the White theme, while the control gallery in
// monochrome_test.dart (plain chips on a bare Scaffold) passed. So this drives the actual TaskFormSheet.

double lum(int v) {
  final c = v / 255;
  return c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

void main() {
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('the task form chips show their labels in ${mode == ThemeMode.light ? 'White' : 'Black'}, selected or not', (tester) async {
      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      await pumpWith(
        tester,
        RepaintBoundary(
          key: key,
          child: Scaffold(body: TaskFormSheet(task: null, date: '2026-11-06', today: '2026-11-06', labels: Labels.fromJson(fixture('labels') as Json), prefill: null)),
        ),
        server: FakeServer(),
        mode: mode,
      );
      await tester.pumpAndSettle();

      final outer = tester.getRect(find.byKey(key));
      final bytes = await tester.runAsync(() async {
        final image = await tester.renderObject<RenderRepaintBoundary>(find.byKey(key)).toImage(pixelRatio: 2.0);
        return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      });
      final width = (outer.width * 2).round();

      double contrastInside(Rect full) {
        final r = Rect.fromCenter(center: full.center, width: full.width * 0.7, height: full.height * 0.45);
        final bins = List<int>.filled(16, 0);
        var total = 0;
        for (var y = ((r.top - outer.top) * 2).floor(); y < ((r.bottom - outer.top) * 2).ceil(); y++) {
          for (var x = ((r.left - outer.left) * 2).floor(); x < ((r.right - outer.left) * 2).ceil(); x++) {
            bins[bytes!.getUint8((y * width + x) * 4) >> 4]++;
            total++;
          }
        }
        final tones = [for (var i = 0; i < 16; i++) if (bins[i] >= total * 0.015) i * 16 + 8];
        var best = 1.0;
        for (final a in tones) {
          for (final b in tones) {
            best = math.max(best, (math.max(lum(a), lum(b)) + 0.05) / (math.min(lum(a), lum(b)) + 0.05));
          }
        }
        return best;
      }

      final chips = find.byType(ChoiceChip);
      expect(chips, findsWidgets);
      final bad = <String>[];
      for (final chip in tester.widgetList<ChoiceChip>(chips)) {
        final label = ((chip.label as Text).data)!;
        final rect = tester.getRect(find.widgetWithText(ChoiceChip, label).first);
        final c = contrastInside(rect);
        if (c < 3.0) bad.add('"$label" selected=${chip.selected} contrast=${c.toStringAsFixed(2)}');
      }
      expect(bad, isEmpty, reason: 'chips whose label cannot be read');
    });
  }
}
