import 'package:flutter/material.dart';

/// App Theme Configuration - Blue Theme
class AppTheme {
  // Blue color palette
  static const Color primaryColor = Color(0xFF1976D2);      // Material Blue 700
  static const Color primaryDark = Color(0xFF0D47A1);       // Material Blue 900
  static const Color primaryLight = Color(0xFF42A5F5);      // Material Blue 400
  static const Color primaryLighter = Color(0xFF64B5F6);    // Material Blue 300
  static const Color primaryLightest = Color(0xFF90CAF9);   // Material Blue 200

  static const Color secondaryColor = Color(0xFF42A5F5);    // Material Blue 400
  static const Color accentColor = Color(0xFF64B5F6);       // Material Blue 300

  static const Color backgroundLight = Color(0xFFFFFFFF);   // Pure white
  static const Color backgroundDark = Color(0xFF121212);    // Modern dark gray
  static const Color surfaceLight = Color(0xFFFFFFFF);      // Pure white
  static const Color surfaceDark = Color(0xFF1E1E1E);       // Elevated dark surface
  static const Color navIconColor = Color(0xFF64B5F6);      // Light blue

  // Text colors for dark mode
  static const Color textLight = Color(0xFF1F2937);         // Dark text for light mode
  static const Color textDark = Color(0xFFE5E5E5);          // Light text for dark mode
  static const Color textSecondaryLight = Color(0xFF6B7280);// Secondary text light
  static const Color textSecondaryDark = Color(0xFF9CA3AF); // Secondary text dark

  // Status colors - muted versions
  static const Color success = Color.fromARGB(255, 61, 190, 106);
  static const Color warning = Color.fromARGB(255, 255, 210, 97);
  static const Color error = Color.fromARGB(255, 249, 62, 84);
  static const Color info = Color(0xFF42A5F5);              // Material Blue 400
  
  // Simple solid gradients (same color for simplicity)
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primaryColor, primaryDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient successGradient = LinearGradient(
    colors: [success, success],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient warningGradient = LinearGradient(
    colors: [warning, warning],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient dangerGradient = LinearGradient(
    colors: [error, error],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient streakGradient = LinearGradient(
    colors: [primaryLight, primaryColor],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  // Light Theme
  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.light(
      primary: primaryColor,
      secondary: secondaryColor,
      tertiary: accentColor,
      surface: surfaceLight,
      error: error,
    ),
    scaffoldBackgroundColor: backgroundLight,
    appBarTheme: const AppBarTheme(
      backgroundColor: primaryColor,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w500,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      color: surfaceLight,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: accentColor,
        foregroundColor: Colors.white,
        elevation: 1,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: accentColor,
        side: const BorderSide(color: accentColor, width: 1),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: accentColor,
      foregroundColor: Colors.white,
      elevation: 2,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: backgroundLight,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: accentColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: accentColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: accentColor, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: error, width: 1),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: backgroundLight,
      selectedItemColor: navIconColor,
      unselectedItemColor: navIconColor,
      type: BottomNavigationBarType.fixed,
      elevation: 4,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: backgroundLight,
      indicatorColor: primaryColor,
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: Colors.white);
        }
        return IconThemeData(color: primaryColor.withOpacity(0.6));
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: primaryColor);
        }
        return TextStyle(fontSize: 12, color: primaryColor.withOpacity(0.6));
      }),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: accentColor.withOpacity(0.2),
      labelStyle: TextStyle(fontSize: 12, color: accentColor),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: accentColor.withOpacity(0.3),
      thickness: 1,
    ),
  );
  
  // Dark Theme
  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.dark(
      primary: primaryColor,
      secondary: secondaryColor,
      tertiary: accentColor,
      surface: surfaceDark,
      error: error,
    ),
    scaffoldBackgroundColor: backgroundDark,
    appBarTheme: const AppBarTheme(
      backgroundColor: primaryColor,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w500,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      color: surfaceDark,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: accentColor,
        foregroundColor: Colors.white,
        elevation: 1,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: accentColor,
        side: BorderSide(color: accentColor, width: 1),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: accentColor,
      foregroundColor: Colors.white,
      elevation: 2,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: backgroundDark,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: accentColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: accentColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: accentColor, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: error, width: 1),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: surfaceDark,
      selectedItemColor: navIconColor,
      unselectedItemColor: navIconColor,
      type: BottomNavigationBarType.fixed,
      elevation: 4,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surfaceDark,
      indicatorColor: primaryColor,
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: Colors.white);
        }
        return IconThemeData(color: primaryColor.withOpacity(0.6));
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: primaryColor);
        }
        return TextStyle(fontSize: 12, color: primaryColor.withOpacity(0.6));
      }),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: accentColor.withOpacity(0.2),
      labelStyle: TextStyle(fontSize: 12, color: accentColor),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: accentColor.withOpacity(0.3),
      thickness: 1,
    ),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: textDark),
      bodyMedium: TextStyle(color: textDark),
      bodySmall: TextStyle(color: textSecondaryDark),
      titleLarge: TextStyle(color: textDark),
      titleMedium: TextStyle(color: textDark),
      titleSmall: TextStyle(color: textDark),
      headlineLarge: TextStyle(color: textDark),
      headlineMedium: TextStyle(color: textDark),
      headlineSmall: TextStyle(color: textDark),
    ),
  );
  
  // Helper methods for theme-aware colors
  static Color getSecondaryTextColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? textSecondaryDark
        : textSecondaryLight;
  }
  
  static Color getCardBorderColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? Colors.grey.shade700
        : Colors.grey.shade200;
  }
  
  static Color getShimmerColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? Colors.grey.shade800
        : Colors.grey.shade200;
  }
  
  static Color getProgressBackgroundColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? Colors.grey.shade700
        : Colors.grey.shade200;
  }
}
