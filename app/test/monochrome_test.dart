import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taskrelay/app.dart';
import 'package:taskrelay/core/theme/app_theme.dart';
import 'package:taskrelay/features/auth/auth_screen.dart';
import 'package:taskrelay/features/calendar/calendar_screen.dart';
import 'package:taskrelay/features/onboarding/onboarding_screen.dart';
import 'package:taskrelay/features/profile/profile_screen.dart';
import 'package:taskrelay/features/review/review_screen.dart';
import 'package:taskrelay/features/search/search_screen.dart';
import 'package:taskrelay/features/sheet/sheet_screen.dart';
import 'package:taskrelay/features/today/today_screen.dart';
import 'package:taskrelay/state/providers.dart';

import 'support.dart';

// The product is strictly black and white, in a White theme and a Black theme the user can choose.
// These tests make that a property of the build, not of anyone's memory:
//   1. the theme values are pure greys, and readable;
//   2. no source file can introduce a hue (colour literal, named colour, or an emoji, which Android draws in colour);
//   3. real screens, rendered in both themes, contain no coloured pixel;
//   4. the choice in Profile really changes the running app, and survives a restart.

bool isGrey(Color c) => (c.r - c.g).abs() < 1e-6 && (c.g - c.b).abs() < 1e-6;

double contrast(Color a, Color b) {
  final l1 = a.computeLuminance(), l2 = b.computeLuminance();
  final hi = l1 > l2 ? l1 : l2, lo = l1 > l2 ? l2 : l1;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('theme values', () {
    for (final entry in {'White': AppTheme.light(), 'Black': AppTheme.dark()}.entries) {
      final theme = entry.value;
      final tr = theme.extension<TrColors>()!;
      final s = theme.colorScheme;

      test('${entry.key}: every colour role is a pure grey', () {
        final roles = <String, Color>{
          'primary': s.primary, 'onPrimary': s.onPrimary, 'primaryContainer': s.primaryContainer, 'onPrimaryContainer': s.onPrimaryContainer,
          'secondary': s.secondary, 'onSecondary': s.onSecondary, 'secondaryContainer': s.secondaryContainer, 'onSecondaryContainer': s.onSecondaryContainer,
          'tertiary': s.tertiary, 'onTertiary': s.onTertiary, 'tertiaryContainer': s.tertiaryContainer, 'onTertiaryContainer': s.onTertiaryContainer,
          'error': s.error, 'onError': s.onError, 'errorContainer': s.errorContainer, 'onErrorContainer': s.onErrorContainer,
          'surface': s.surface, 'onSurface': s.onSurface, 'onSurfaceVariant': s.onSurfaceVariant,
          'surfaceContainerLowest': s.surfaceContainerLowest, 'surfaceContainerLow': s.surfaceContainerLow, 'surfaceContainer': s.surfaceContainer,
          'surfaceContainerHigh': s.surfaceContainerHigh, 'surfaceContainerHighest': s.surfaceContainerHighest,
          'outline': s.outline, 'outlineVariant': s.outlineVariant, 'shadow': s.shadow, 'scrim': s.scrim,
          'inverseSurface': s.inverseSurface, 'onInverseSurface': s.onInverseSurface, 'inversePrimary': s.inversePrimary, 'surfaceTint': s.surfaceTint,
          'scaffold': theme.scaffoldBackgroundColor, 'divider': theme.dividerTheme.color!,
          'muted': tr.muted, 'border': tr.border, 'fieldBorder': tr.fieldBorder, 'input': tr.input, 'track': tr.track, 'accent': tr.accent, 'accentInk': tr.accentInk,
        };
        final coloured = roles.entries.where((e) => !isGrey(e.value)).map((e) => '${e.key}=${e.value}').toList();
        expect(coloured, isEmpty);
      });

      test('${entry.key}: text and controls are readable (WCAG)', () {
        expect(contrast(s.onSurface, s.surface), greaterThanOrEqualTo(7), reason: 'body text');
        expect(contrast(tr.muted, s.surface), greaterThanOrEqualTo(4.5), reason: 'secondary text');
        expect(contrast(tr.muted, theme.scaffoldBackgroundColor), greaterThanOrEqualTo(4.5), reason: 'secondary text on the page');
        expect(contrast(tr.accentInk, tr.accent), greaterThanOrEqualTo(7), reason: 'text on a filled button');
        expect(contrast(tr.fieldBorder, s.surface), greaterThanOrEqualTo(3), reason: 'input outline / check circle (non-text contrast)');
        expect(contrast(tr.fieldBorder, theme.scaffoldBackgroundColor), greaterThanOrEqualTo(3));
      });
    }

    test('the White theme is white and the Black theme is true black', () {
      expect(AppTheme.light().scaffoldBackgroundColor, Colors.white);
      expect(AppTheme.dark().scaffoldBackgroundColor, Colors.black);
      expect(AppTheme.light().colorScheme.brightness, Brightness.light);
      expect(AppTheme.dark().colorScheme.brightness, Brightness.dark);
    });
  });

  group('source files cannot introduce a hue', () {
    // Emoji are drawn by Android's colour-emoji font whatever the theme says.
    // Beyond Latin-1, anything with the Emoji property: that also catches the warning sign, which defaults to text presentation but is
    // drawn as a colour emoji by Android's font (it showed up yellow on a real phone). The text symbols the app uses on purpose
    // (✓ ✕ ◐ ↻ ★ ☆ • – · — …) are not emoji.
    // ignore: valid_regexps (the analyzer's regex checker predates Unicode property escapes; the Dart VM supports them)
    final emoji = RegExp(r'(?![\u0000-\u00FF])\p{Emoji}|\uFE0F', unicode: true);
    // Dart: Color(0xAARRGGBB). Android XML: "#RRGGBB" / "#AARRGGBB" / "#RGB" as an attribute value or element text. Kotlin: parseColor("#...") / 0xFFRRGGBB.
    final dartColor = RegExp(r'Color\(0x([0-9A-Fa-f]{8})\)');
    final dartNamed = RegExp(r'Colors\.(\w+)');
    final xmlColor = RegExp(r'(?:="|>)\s*#([0-9A-Fa-f]{3,8})\s*(?:"|<)');
    final xmlNamed = RegExp(r'@android:color/(\w+)');
    final ktColor = RegExp(r'(?:parseColor\("#([0-9A-Fa-f]{6,8})"\)|0x([0-9A-Fa-f]{8})\b)');
    const greyNames = {'transparent', 'grey', 'gray'};
    const greyAndroid = {'black', 'white', 'transparent', 'darker_gray', 'background_dark', 'background_light'};

    bool hexIsGrey(String hex) {
      var h = hex;
      if (h.length == 3 || h.length == 4) h = h.split('').map((c) => '$c$c').join(); // #RGB / #ARGB
      if (h.length == 8) h = h.substring(2); // drop alpha
      if (h.length != 6) return true; // not a colour
      return h.substring(0, 2) == h.substring(2, 4) && h.substring(2, 4) == h.substring(4, 6);
    }

    List<File> files(String dir, List<String> exts) {
      final d = Directory(dir);
      if (!d.existsSync()) return const [];
      return d.listSync(recursive: true).whereType<File>().where((f) => exts.any(f.path.endsWith)).toList();
    }

    Iterable<String> scan(List<File> list, RegExp re, bool Function(RegExpMatch m) bad) sync* {
      for (final f in list) {
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          for (final m in re.allMatches(lines[i])) {
            if (bad(m)) yield '${f.path.replaceAll('\\', '/')}:${i + 1}: ${m.group(0)}';
          }
        }
      }
    }

    test('no emoji in app text (use IconText / Material icons)', () {
      expect(scan(files('lib', ['.dart']), emoji, (_) => true), isEmpty);
    });

    test('Dart: colour literals and named colours are all grey', () {
      final dart = files('lib', ['.dart']);
      expect(scan(dart, dartColor, (m) => !hexIsGrey(m.group(1)!)), isEmpty);
      expect(scan(dart, dartNamed, (m) => !(RegExp(r'^(black|white)\d*$').hasMatch(m.group(1)!) || greyNames.contains(m.group(1)))), isEmpty);
    });

    test('Android resources and Kotlin: colours are grey, no emoji in user-visible strings', () {
      final res = files('android/app/src/main/res', ['.xml']);
      expect(scan(res, xmlColor, (m) => !hexIsGrey(m.group(1)!)), isEmpty);
      expect(scan(res, xmlNamed, (m) => !greyAndroid.contains(m.group(1))), isEmpty);
      expect(scan(res.where((f) => f.path.contains('values')).toList(), emoji, (_) => true), isEmpty, reason: 'strings.xml');
      final kt = files('android/app/src/main/kotlin', ['.kt']);
      expect(scan(kt, ktColor, (m) => !hexIsGrey(m.group(1) ?? m.group(2)!)), isEmpty);
    });
  });

  testWidgets('launcher icons (and the Play Store icon) are pure grey: no leftover coloured artwork', (tester) async {
    final res = Directory('android/app/src/main/res');
    final files = [
      ...res.listSync(recursive: true).whereType<File>().where((f) => f.path.contains('mipmap') && f.path.endsWith('.png')),
      File('../docs/store/icon-512.png'),
    ];
    expect(files.where((f) => f.path.contains('mipmap')).length, greaterThanOrEqualTo(5), reason: 'one launcher icon per density');
    for (final f in files) {
      expect(f.existsSync(), isTrue, reason: f.path);
      final bytes = await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(f.readAsBytesSync());
        final frame = await codec.getNextFrame();
        return (await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      });
      var coloured = 0, dark = 0, light = 0;
      for (var i = 0; i < bytes!.lengthInBytes; i += 4) {
        final int r = bytes.getUint8(i), g = bytes.getUint8(i + 1), b = bytes.getUint8(i + 2), a = bytes.getUint8(i + 3);
        if (a == 0) continue;
        if (math.max<int>(r, math.max<int>(g, b)) - math.min<int>(r, math.min<int>(g, b)) > 2) coloured++;
        if (r < 40) dark++;
        if (r > 215) light++;
      }
      expect(coloured, 0, reason: '${f.path}: $coloured coloured pixels');
      expect(dark, greaterThan(0), reason: '${f.path} should have a black background');
      expect(light, greaterThan(0), reason: '${f.path} should have a white mark');
    }
  });

  group('rendered screens contain no coloured pixel', () {
    final screens = <String, Widget Function()>{
      'Today': () => const TodayScreen(),
      'Calendar': () => const CalendarScreen(),
      'Review': () => const ReviewScreen(),
      'Sheet': () => const SheetScreen(),
      'Search': () => const SearchScreen(),
      'Profile': () => const ProfileScreen(),
      'Sign in': () => const AuthScreen(),
      'Onboarding': () => const OnboardingScreen(),
    };

    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      for (final s in screens.entries) {
        testWidgets('${s.key} in ${mode == ThemeMode.light ? 'White' : 'Black'}', (tester) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 3.0;
          addTearDown(tester.view.reset);

          final key = GlobalKey();
          await pumpWith(tester, RepaintBoundary(key: key, child: s.value()), server: FakeServer(), mode: mode);
          await tester.pumpAndSettle();
          if (s.key == 'Search') {
            await tester.enterText(find.byType(TextField).first, 'report'); // show results, not only the empty prompt
            await tester.pumpAndSettle(const Duration(seconds: 1));
          }

          final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
          final bytes = await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 0.5);
            return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
          });

          var worst = 0, coloured = 0;
          for (var i = 0; i < bytes!.lengthInBytes; i += 4) {
            final r = bytes.getUint8(i), g = bytes.getUint8(i + 1), b = bytes.getUint8(i + 2);
            final int chroma = math.max<int>(r, math.max<int>(g, b)) - math.min<int>(r, math.min<int>(g, b));
            if (chroma > 2) coloured++;
            if (chroma > worst) worst = chroma;
          }
          expect(coloured, 0, reason: '$coloured coloured pixels (max channel spread $worst)');
        });
      }
    }
  });

  // A monochrome theme makes "invisible" easy: foreground and fill can be the same grey. The colour scan above cannot see that
  // (grey on grey is still grey), and on a real phone the quick-add arrow was white on white. So check that a control's icon is
  // actually distinguishable from its fill: the button must contain both a light and a dark region.
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('the quick-add arrow is visible against its button in ${mode == ThemeMode.light ? 'White' : 'Black'}', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      await pumpWith(tester, RepaintBoundary(key: key, child: const TodayScreen()), server: FakeServer(), mode: mode);
      await tester.pumpAndSettle();

      final rect = tester.getRect(find.widgetWithIcon(IconButton, Icons.arrow_upward));
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
      final bytes = await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1.0);
        return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      });
      final width = (boundary.size.width).round();
      var light = 0, dark = 0;
      final inner = rect.deflate(rect.shortestSide * 0.2); // inside the circle, away from its anti-aliased edge
      for (var y = inner.top.floor(); y < inner.bottom.ceil(); y++) {
        for (var x = inner.left.floor(); x < inner.right.ceil(); x++) {
          final v = bytes!.getUint8((y * width + x) * 4); // R == G == B in a grey theme
          if (v > 200) light++;
          if (v < 60) dark++;
        }
      }
      expect(light, greaterThan(10), reason: 'no light pixels inside the button');
      expect(dark, greaterThan(10), reason: 'no dark pixels inside the button: the arrow is the same grey as its fill');
    });
  }

  // The general form of the arrow check above. Grey on the same grey (a selected chip whose label has the fill's colour) is not a
  // "colour", so the scans above cannot see it. Every control, in every state, in both themes, must show at least 3:1 contrast
  // (WCAG 1.4.11, UI components) between the tones that cover a meaningful part of its own rectangle. Disabled controls are exempt.
  group('controls are legible in every state', () {
    final controls = <String, Widget Function()>{
      'selected ChoiceChip': () => ChoiceChip(label: const Text('30'), selected: true, onSelected: (_) {}),
      'unselected ChoiceChip': () => ChoiceChip(label: const Text('45'), selected: false, onSelected: (_) {}),
      'selected FilterChip': () => FilterChip(label: const Text('Mon'), selected: true, onSelected: (_) {}),
      'unselected FilterChip': () => FilterChip(label: const Text('Tue'), selected: false, onSelected: (_) {}),
      'InputChip': () => InputChip(label: const Text('Low'), onPressed: () {}, onDeleted: () {}),
      'FilledButton': () => FilledButton(onPressed: () {}, child: const Text('Save')),
      'OutlinedButton': () => OutlinedButton(onPressed: () {}, child: const Text('Cancel')),
      'TextButton': () => TextButton(onPressed: () {}, child: const Text('Retry')),
      'FilledButton.icon': () => FilledButton.icon(onPressed: () {}, icon: const Icon(Icons.add), label: const Text('Add')),
      'FloatingActionButton': () => FloatingActionButton.extended(onPressed: () {}, icon: const Icon(Icons.add), label: const Text('Add task')),
      'Switch on': () => Switch(value: true, onChanged: (_) {}),
      'Switch off': () => Switch(value: false, onChanged: (_) {}),
      'Checkbox checked': () => Checkbox(value: true, onChanged: (_) {}),
      'SegmentedButton': () => SegmentedButton<int>(
            segments: const [ButtonSegment(value: 1, label: Text('White')), ButtonSegment(value: 2, label: Text('Black'))],
            selected: const {1},
            onSelectionChanged: (_) {},
          ),
      'icon button': () => IconButton(onPressed: () {}, icon: const Icon(Icons.search)),
      'ProgressIndicator': () => const SizedBox(width: 120, child: LinearProgressIndicator(value: 0.5)),
    };

    double lum(int v) {
      final c = v / 255;
      return c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
    }

    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      for (final c in controls.entries) {
        testWidgets('${c.key} in ${mode == ThemeMode.light ? 'White' : 'Black'}', (tester) async {
          final boundaryKey = GlobalKey(), controlKey = GlobalKey();
          final theme = mode == ThemeMode.light ? AppTheme.light() : AppTheme.dark();
          await tester.pumpWidget(MaterialApp(
            theme: theme,
            home: Scaffold(
              body: Center(
                child: RepaintBoundary(
                  key: boundaryKey,
                  // the page colour is painted OUTSIDE the boundary, so it is repeated inside to get what a user sees
                  child: ColoredBox(color: theme.scaffoldBackgroundColor, child: Padding(padding: const EdgeInsets.all(12), child: KeyedSubtree(key: controlKey, child: c.value()))),
                ),
              ),
            ),
          ));
          await tester.pumpAndSettle();

          final outer = tester.getRect(find.byKey(boundaryKey));
          // Only the middle of the control: a chip's 48dp tap target is taller than its 32dp pill, so its edges would let the page
          // colour in and hide a label that has the same colour as its fill.
          final full = tester.getRect(find.byKey(controlKey));
          final rect = Rect.fromCenter(center: full.center, width: full.width * 0.7, height: full.height * 0.45);
          const ratio = 2.0;
          final bytes = await tester.runAsync(() async {
            final image = await tester.renderObject<RenderRepaintBoundary>(find.byKey(boundaryKey)).toImage(pixelRatio: ratio);
            return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
          });
          final width = (outer.width * ratio).round();
          final bins = List<int>.filled(16, 0); // 16 grey levels
          var total = 0;
          for (var y = ((rect.top - outer.top) * ratio).floor(); y < ((rect.bottom - outer.top) * ratio).ceil(); y++) {
            for (var x = ((rect.left - outer.left) * ratio).floor(); x < ((rect.right - outer.left) * ratio).ceil(); x++) {
              bins[bytes!.getUint8((y * width + x) * 4) >> 4]++;
              total++;
            }
          }
          final tones = [for (var i = 0; i < 16; i++) if (bins[i] >= total * 0.015) i * 16 + 8]; // tones covering >= 1.5% of the control
          var best = 1.0;
          for (final a in tones) {
            for (final b in tones) {
              final hi = math.max(lum(a), lum(b)), lo = math.min(lum(a), lum(b));
              best = math.max(best, (hi + 0.05) / (lo + 0.05));
            }
          }
          expect(best, greaterThanOrEqualTo(3.0), reason: '${c.key}: the strongest contrast inside it is only ${best.toStringAsFixed(2)}:1 (tones: $tones)');
        });
      }
    }
  });

  group('the White / Black / Device choice', () {
    Future<ProviderContainer> pumpApp(WidgetTester tester, Map<String, Object> saved) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues(saved);
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(overrides: [
        prefsProvider.overrideWithValue(prefs),
        httpClientProvider.overrideWithValue(FakeServer().client),
        bridgeProvider.overrideWithValue(FakeBridge()),
        sessionProvider.overrideWith(SignedInSession.new),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const TaskRelayApp()));
      await tester.pumpAndSettle();
      return container;
    }

    Color page(WidgetTester tester) => Theme.of(tester.element(find.byType(Scaffold).first)).scaffoldBackgroundColor;

    Future<void> choose(WidgetTester tester, String label) async {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    Future<void> openProfile(WidgetTester tester) async {
      await tester.tap(find.text('Profile').last);
      await tester.pumpAndSettle();
    }

    testWidgets('picking Black or White changes the running app and is remembered', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final c = await pumpApp(tester, {});
      expect(page(tester), Colors.white, reason: 'a fresh install follows the (light) device');

      await openProfile(tester);
      await choose(tester, 'Black');
      expect(page(tester), Colors.black);
      expect(c.read(themeModeProvider), ThemeMode.dark);
      expect(c.read(prefsProvider).getString('theme_mode'), 'dark');

      await choose(tester, 'White');
      expect(page(tester), Colors.white);
      expect(c.read(prefsProvider).getString('theme_mode'), 'light');
    });

    testWidgets('Device follows the phone, live', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final c = await pumpApp(tester, {'theme_mode': 'light'});
      expect(page(tester), Colors.white, reason: 'an explicit White beats a dark phone');

      await openProfile(tester);
      await choose(tester, 'Device');
      expect(page(tester), Colors.black);
      expect(c.read(prefsProvider).containsKey('theme_mode'), isFalse);

      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await tester.pumpAndSettle();
      expect(page(tester), Colors.white);
    });

    testWidgets('a saved Black choice is applied on the next launch', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await pumpApp(tester, {'theme_mode': 'dark'});
      expect(page(tester), Colors.black);
    });
  });
}
