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
    // ignore: valid_regexps (the analyzer's regex checker predates Unicode property escapes; the Dart VM supports them)
    final emoji = RegExp(r'[\p{Emoji_Presentation}️]', unicode: true);
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

  group('rendered screens contain no coloured pixel', () {
    final screens = <String, Widget Function()>{
      'Today': () => const TodayScreen(),
      'Calendar': () => const CalendarScreen(),
      'Review': () => const ReviewScreen(),
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
