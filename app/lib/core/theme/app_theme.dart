import 'package:flutter/material.dart';

/// Productivity Mode Design System
class AppTheme {
  // ─── Palette — teal-green accent, deep navy dark ──────────────────
  static const Color primaryColor    = Color(0xFF00D4AA); // vivid teal
  static const Color primaryDark     = Color(0xFF00B891); // deeper teal
  static const Color primaryLight    = Color(0xFF33DDBB); // bright teal
  static const Color primaryLighter  = Color(0xFF66E8CC); // soft teal
  static const Color primaryLightest = Color(0xFFE0FAF5); // pale teal wash

  static const Color secondaryColor = Color(0xFF4DA6FF); // blue for info
  static const Color accentColor    = Color(0xFF00D4AA);

  // Backgrounds
  static const Color backgroundLight = Color(0xFFF0F2F7); // cool neutral
  static const Color backgroundDark  = Color(0xFF080D18); // deep near-black
  static const Color surfaceLight    = Color(0xFFFFFFFF);
  static const Color surfaceDark     = Color(0xFF111827); // dark blue-slate
  static const Color navIconColor    = Color(0xFF00D4AA);

  // Text
  static const Color textLight          = Color(0xFF0F1629);
  static const Color textDark           = Color(0xFFE8EDF8);
  static const Color textSecondaryLight = Color(0xFF5A6880);
  static const Color textSecondaryDark  = Color(0xFF7A8BA3);

  // Semantic
  static const Color success = Color(0xFF00D4AA); // teal = done = go
  static const Color warning = Color(0xFFF59E0B);
  static const Color error   = Color(0xFFF04438);
  static const Color info    = Color(0xFF4DA6FF);

  // Borders
  static const Color borderLight = Color(0xFFCDD5E0);
  static const Color borderDark  = Color(0xFF1E2D45);

  // ─── Geometry — sharper for productivity focus ────────────────────
  static const double radiusXS   = 6;
  static const double radiusSM   = 8;
  static const double radiusMD   = 12;
  static const double radiusLG   = 16;
  static const double radiusXL   = 20;
  static const double radiusFull = 100;

  // ─── Gradients ────────────────────────────────────────────────────
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primaryColor, primaryDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient successGradient = LinearGradient(
    colors: [Color(0xFF00D4AA), Color(0xFF00B891)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient warningGradient = LinearGradient(
    colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient dangerGradient = LinearGradient(
    colors: [Color(0xFFF04438), Color(0xFFDC2626)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient streakGradient = LinearGradient(
    colors: [Color(0xFFFF6B35), Color(0xFFF59E0B)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ─── Shadows — borders do the heavy lifting in dark mode ──────────
  static List<BoxShadow> softShadow(BuildContext context) {
    if (Theme.of(context).brightness == Brightness.dark) return [];
    return [
      BoxShadow(
        color: const Color(0xFF8A97AB).withValues(alpha: 0.08),
        blurRadius: 12,
        offset: const Offset(0, 2),
      ),
    ];
  }

  static List<BoxShadow> subtleShadow(BuildContext context) =>
      softShadow(context);

  // ─── Helpers ──────────────────────────────────────────────────────
  static Color getSecondaryTextColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? textSecondaryDark
          : textSecondaryLight;

  static Color getCardBorderColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? borderDark : borderLight;

  static Color getShimmerColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF1E2D45)
          : const Color(0xFFE4E9F0);

  static Color getProgressBackgroundColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF1E2D45)
          : const Color(0xFFE4E9F0);

  // ═══════════════════════════════════════════════════════════════════
  // LIGHT THEME
  // ═══════════════════════════════════════════════════════════════════
  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    fontFamily: 'Roboto',
    colorScheme: ColorScheme.light(
      primary: primaryColor,
      secondary: secondaryColor,
      tertiary: accentColor,
      surface: surfaceLight,
      surfaceContainerHighest: const Color(0xFFEAEDF5),
      error: error,
    ),
    scaffoldBackgroundColor: backgroundLight,
    appBarTheme: const AppBarTheme(
      backgroundColor: surfaceLight,
      foregroundColor: textLight,
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: false,
      surfaceTintColor: Colors.transparent,
      shadowColor: borderLight,
      titleTextStyle: TextStyle(
        color: textLight,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
      iconTheme: IconThemeData(color: textLight),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusMD),
      ),
      color: surfaceLight,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryColor,
        foregroundColor: const Color(0xFF0F1629),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSM)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, letterSpacing: 0.2),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primaryColor,
        side: const BorderSide(color: primaryColor, width: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSM)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primaryColor,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusXS)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: primaryColor,
      foregroundColor: const Color(0xFF0F1629),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMD)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFEFF1F7),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSM),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSM),
        borderSide: const BorderSide(color: borderLight, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSM),
        borderSide: const BorderSide(color: primaryColor, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSM),
        borderSide: const BorderSide(color: error, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSM),
        borderSide: const BorderSide(color: error, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      hintStyle: const TextStyle(color: textSecondaryLight, fontWeight: FontWeight.w400, fontSize: 14),
      labelStyle: const TextStyle(color: textSecondaryLight, fontSize: 14),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: surfaceLight,
      selectedItemColor: primaryColor,
      unselectedItemColor: textSecondaryLight,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surfaceLight,
      indicatorColor: primaryColor.withValues(alpha: 0.12),
      elevation: 0,
      height: 60,
      surfaceTintColor: Colors.transparent,
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: primaryColor, size: 22);
        }
        return const IconThemeData(color: textSecondaryLight, size: 22);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: primaryColor, letterSpacing: 0.2);
        }
        return const TextStyle(fontSize: 11, color: textSecondaryLight, letterSpacing: 0.2);
      }),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: primaryColor.withValues(alpha: 0.08),
      labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: primaryColor),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusFull)),
      side: BorderSide.none,
    ),
    dividerTheme: const DividerThemeData(color: borderLight, thickness: 1, space: 1),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusLG)),
      surfaceTintColor: Colors.transparent,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surfaceLight,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(radiusLG)),
      ),
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF111827),
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSM)),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: primaryColor,
      unselectedLabelColor: textSecondaryLight,
      indicatorColor: primaryColor,
      indicatorSize: TabBarIndicatorSize.label,
      dividerHeight: 0,
      labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      unselectedLabelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? primaryColor : Colors.white),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? primaryColor.withValues(alpha: 0.4) : borderLight),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      fillColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? primaryColor : Colors.transparent),
      checkColor: WidgetStateProperty.all(const Color(0xFF0F1629)),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: primaryColor,
      linearTrackColor: borderLight,
    ),
    popupMenuTheme: PopupMenuThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSM)),
      surfaceTintColor: Colors.transparent,
      elevation: 4,
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSM),
          borderSide: BorderSide.none,
        ),
        filled: true,
        fillColor: const Color(0xFFEFF1F7),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(radiusXS),
      ),
      textStyle: const TextStyle(color: Colors.white, fontSize: 12),
    ),
  );

  // ═══════════════════════════════════════════════════════════════════
  // DARK THEME
  // ═══════════════════════════════════════════════════════════════════
  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: 'Roboto',
    colorScheme: ColorScheme.dark(
      primary: primaryColor,
      secondary: secondaryColor,
      tertiary: accentColor,
      surface: surfaceDark,
      surfaceContainerHighest: const Color(0xFF1E2D45),
      error: error,
    ),
    scaffoldBackgroundColor: backgroundDark,
    appBarTheme: const AppBarTheme(
      backgroundColor: surfaceDark,
      foregroundColor: textDark,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        color: textDark,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
      iconTheme: IconThemeData(color: textDark),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusMD),
      ),
      color: surfaceDark,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryColor,
        foregroundColor: const Color(0xFF080D18),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSM)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, letterSpacing: 0.2),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primaryColor,
        side: const BorderSide(color: primaryColor, width: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSM)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primaryColor,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusXS)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: primaryColor,
      foregroundColor: const Color(0xFF080D18),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMD)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF1A2236),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSM),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSM),
        borderSide: const BorderSide(color: borderDark, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSM),
        borderSide: const BorderSide(color: primaryColor, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSM),
        borderSide: const BorderSide(color: error, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSM),
        borderSide: const BorderSide(color: error, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      hintStyle: const TextStyle(color: textSecondaryDark, fontWeight: FontWeight.w400, fontSize: 14),
      labelStyle: const TextStyle(color: textSecondaryDark, fontSize: 14),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: surfaceDark,
      selectedItemColor: primaryColor,
      unselectedItemColor: textSecondaryDark,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surfaceDark,
      indicatorColor: primaryColor.withValues(alpha: 0.15),
      elevation: 0,
      height: 60,
      surfaceTintColor: Colors.transparent,
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: primaryColor, size: 22);
        }
        return const IconThemeData(color: textSecondaryDark, size: 22);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: primaryColor, letterSpacing: 0.2);
        }
        return const TextStyle(fontSize: 11, color: textSecondaryDark, letterSpacing: 0.2);
      }),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: primaryColor.withValues(alpha: 0.12),
      labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: primaryColor),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusFull)),
      side: BorderSide.none,
    ),
    dividerTheme: const DividerThemeData(color: borderDark, thickness: 1, space: 1),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusLG)),
      backgroundColor: surfaceDark,
      surfaceTintColor: Colors.transparent,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surfaceDark,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(radiusLG)),
      ),
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFFE8EDF8),
      contentTextStyle: const TextStyle(color: Color(0xFF0F1629), fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSM)),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: primaryColor,
      unselectedLabelColor: textSecondaryDark,
      indicatorColor: primaryColor,
      indicatorSize: TabBarIndicatorSize.label,
      dividerHeight: 0,
      labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      unselectedLabelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? primaryColor : textDark),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? primaryColor.withValues(alpha: 0.4) : borderDark),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      fillColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? primaryColor : Colors.transparent),
      checkColor: WidgetStateProperty.all(const Color(0xFF080D18)),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: primaryColor,
      linearTrackColor: borderDark,
    ),
    popupMenuTheme: PopupMenuThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSM)),
      surfaceTintColor: Colors.transparent,
      color: surfaceDark,
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSM),
          borderSide: BorderSide.none,
        ),
        filled: true,
        fillColor: const Color(0xFF1A2236),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: const Color(0xFFE8EDF8),
        borderRadius: BorderRadius.circular(radiusXS),
      ),
      textStyle: const TextStyle(color: Color(0xFF0F1629), fontSize: 12),
    ),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: textDark),
      bodyMedium: TextStyle(color: textDark),
      bodySmall: TextStyle(color: textSecondaryDark),
      titleLarge:   TextStyle(color: textDark, letterSpacing: -0.3),
      titleMedium:  TextStyle(color: textDark, letterSpacing: -0.2),
      titleSmall:   TextStyle(color: textDark),
      headlineLarge:  TextStyle(color: textDark, letterSpacing: -0.5),
      headlineMedium: TextStyle(color: textDark, letterSpacing: -0.4),
      headlineSmall:  TextStyle(color: textDark, letterSpacing: -0.3),
    ),
  );
}
