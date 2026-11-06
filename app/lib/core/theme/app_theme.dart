import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Strictly black & white. Two palettes (White and Black) built by ONE function; the user picks White, Black, or
/// "match device" in Profile. Nothing relies on colour alone: status uses symbols, weight, borders and patterns.
class TrColors extends ThemeExtension<TrColors> {
  const TrColors({
    required this.muted,
    required this.border,
    required this.fieldBorder,
    required this.input,
    required this.track,
    required this.accent,
    required this.accentInk,
  });

  final Color muted;
  final Color border;
  final Color fieldBorder;
  final Color input;
  final Color track;

  /// Fill colour for primary actions, progress and selection (black on White, white on Black).
  final Color accent;
  final Color accentInk;

  @override
  TrColors copyWith({Color? muted, Color? border, Color? fieldBorder, Color? input, Color? track, Color? accent, Color? accentInk}) => TrColors(
        muted: muted ?? this.muted,
        border: border ?? this.border,
        fieldBorder: fieldBorder ?? this.fieldBorder,
        input: input ?? this.input,
        track: track ?? this.track,
        accent: accent ?? this.accent,
        accentInk: accentInk ?? this.accentInk,
      );

  @override
  TrColors lerp(ThemeExtension<TrColors>? other, double t) {
    if (other is! TrColors) return this;
    return TrColors(
      muted: Color.lerp(muted, other.muted, t)!,
      border: Color.lerp(border, other.border, t)!,
      fieldBorder: Color.lerp(fieldBorder, other.fieldBorder, t)!,
      input: Color.lerp(input, other.input, t)!,
      track: Color.lerp(track, other.track, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentInk: Color.lerp(accentInk, other.accentInk, t)!,
    );
  }
}

extension TrTheme on BuildContext {
  TrColors get tr => Theme.of(this).extension<TrColors>()!;
}

class AppTheme {
  static const radius = 16.0;
  static const radiusSm = 8.0;

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness b) {
    final dark = b == Brightness.dark;
    final bg = dark ? Colors.black : Colors.white;
    final surface = dark ? const Color(0xFF0D0D0D) : Colors.white;
    final text = dark ? const Color(0xFFF5F5F5) : const Color(0xFF0A0A0A);
    final c = TrColors(
      muted: dark ? const Color(0xFFA6A6A6) : const Color(0xFF5C5C5C),
      border: dark ? const Color(0xFF2B2B2B) : const Color(0xFFD9D9D9),
      fieldBorder: dark ? const Color(0xFF707070) : const Color(0xFF7A7A7A),
      input: dark ? const Color(0xFF1A1A1A) : const Color(0xFFF3F3F3),
      track: dark ? const Color(0xFF2B2B2B) : const Color(0xFFE6E6E6),
      accent: text,
      accentInk: bg,
    );

    // Every role is set explicitly so nothing falls back to a default blue/purple.
    final scheme = ColorScheme(
      brightness: b,
      primary: c.accent,
      onPrimary: c.accentInk,
      primaryContainer: c.track,
      onPrimaryContainer: text,
      secondary: c.accent,
      onSecondary: c.accentInk,
      secondaryContainer: c.track,
      onSecondaryContainer: text,
      tertiary: c.accent,
      onTertiary: c.accentInk,
      error: text,
      onError: bg,
      surface: surface,
      onSurface: text,
      onSurfaceVariant: c.muted,
      surfaceContainerHighest: c.input,
      surfaceContainerHigh: c.input,
      surfaceContainer: c.input,
      surfaceContainerLow: surface,
      outline: c.fieldBorder,
      outlineVariant: c.border,
      inverseSurface: text,
      onInverseSurface: bg,
      inversePrimary: bg,
      surfaceTint: Colors.transparent,
      shadow: Colors.black,
      scrim: Colors.black,
    );

    final base = ThemeData(brightness: b, useMaterial3: true, colorScheme: scheme, scaffoldBackgroundColor: bg);
    final shapeSm = RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSm));
    OutlineInputBorder field(Color color, [double w = 1]) =>
        OutlineInputBorder(borderRadius: BorderRadius.circular(radiusSm), borderSide: BorderSide(color: color, width: w));

    return base.copyWith(
      extensions: [c],
      textTheme: base.textTheme.apply(bodyColor: text, displayColor: text),
      dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        titleTextStyle: TextStyle(color: text, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.3),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius), side: BorderSide(color: c.border)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius), side: BorderSide(color: c.fieldBorder)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          side: BorderSide(color: c.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.input,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: field(c.fieldBorder),
        enabledBorder: field(c.fieldBorder),
        focusedBorder: field(text, 2),
        errorBorder: field(text, 2),
        focusedErrorBorder: field(text, 2),
        labelStyle: TextStyle(color: c.muted),
        helperStyle: TextStyle(color: c.muted),
        errorStyle: TextStyle(color: text, fontWeight: FontWeight.w700),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.accent,
          foregroundColor: c.accentInk,
          disabledBackgroundColor: c.track,
          disabledForegroundColor: c.muted,
          minimumSize: const Size(64, 48),
          shape: shapeSm,
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          side: BorderSide(color: c.fieldBorder),
          minimumSize: const Size(64, 48),
          shape: shapeSm,
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: text, minimumSize: const Size(48, 48), shape: shapeSm, textStyle: const TextStyle(fontWeight: FontWeight.w600)),
      ),
      iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: text, minimumSize: const Size(48, 48))),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.transparent,
        selectedColor: c.accent,
        disabledColor: c.track,
        side: BorderSide(color: c.fieldBorder),
        shape: const StadiumBorder(),
        showCheckmark: false,
        // The state-dependent colour must be a WidgetStateColor INSIDE the TextStyle: chips ignore a WidgetStateTextStyle here, which left a
        // selected chip's label the same colour as its fill (invisible) and the unselected label the wrong tone (test/monochrome_test.dart).
        labelStyle: TextStyle(
          color: WidgetStateColor.resolveWith((s) => s.contains(WidgetState.selected) ? c.accentInk : text),
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 64,
        indicatorColor: Colors.transparent,
        indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSm), side: BorderSide(color: text, width: 2)),
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(color: s.contains(WidgetState.selected) ? text : c.muted, size: 24)),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => TextStyle(fontSize: 12, fontWeight: s.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600, color: s.contains(WidgetState.selected) ? text : c.muted),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: text,
        contentTextStyle: TextStyle(color: bg, fontSize: 14),
        actionTextColor: bg,
        behavior: SnackBarBehavior.floating,
        shape: shapeSm,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.accentInk : c.muted),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.accent : c.input),
        trackOutlineColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.accent : c.fieldBorder),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.accent : Colors.transparent),
        checkColor: WidgetStatePropertyAll(c.accentInk),
        side: BorderSide(color: c.fieldBorder, width: 2),
        shape: const CircleBorder(),
      ),
      radioTheme: RadioThemeData(fillColor: WidgetStatePropertyAll(c.accent)),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: c.accent, linearTrackColor: c.track, circularTrackColor: c.track),
      listTileTheme: ListTileThemeData(iconColor: text, textColor: text, contentPadding: EdgeInsets.zero),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.accent : Colors.transparent),
          foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.accentInk : text),
          side: WidgetStatePropertyAll(BorderSide(color: c.fieldBorder)),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(backgroundColor: c.accent, foregroundColor: c.accentInk, elevation: 0, focusElevation: 0, hoverElevation: 0, highlightElevation: 0, shape: shapeSm),
      popupMenuTheme: PopupMenuThemeData(color: surface, surfaceTintColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSm), side: BorderSide(color: c.fieldBorder))),
    );
  }
}

/// The user's appearance choice for this device: follow the system, White, or Black.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  static const _key = 'theme_mode';

  @override
  ThemeMode build() {
    final saved = ref.watch(prefsProvider).getString(_key);
    return switch (saved) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    final prefs = ref.read(prefsProvider);
    if (mode == ThemeMode.system) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, mode == ThemeMode.dark ? 'dark' : 'light');
    }
  }
}

/// Overridden in main() with the loaded instance, so reading it is synchronous everywhere.
final prefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError('prefsProvider must be overridden'));

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);
