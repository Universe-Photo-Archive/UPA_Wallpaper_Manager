import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  // Space-inspired color palette
  static const Color _deepSpace = Color(0xFF0B0E1A);
  // ignore: unused_field
  static const Color _cosmicBlue = Color(0xFF1A237E);
  // ignore: unused_field
  static const Color _nebulaPurple = Color(0xFF4A148C);
  static const Color _starWhite = Color(0xFFF5F5F5);
  static const Color _accentCyan = Color(0xFF00BCD4);
  static const Color _accentOrange = Color(0xFFFF6D00);
  static const Color _surfaceDark = Color(0xFF121829);
  static const Color _surfaceDarkElevated = Color(0xFF1C2333);
  static const Color _cardDark = Color(0xFF1E2640);

  static ThemeData get darkTheme {
    final colorScheme = ColorScheme.dark(
      primary: _accentCyan,
      onPrimary: _deepSpace,
      secondary: _accentOrange,
      onSecondary: Colors.white,
      surface: _surfaceDark,
      onSurface: _starWhite,
      error: Colors.redAccent.shade200,
      onError: Colors.white,
      brightness: Brightness.dark,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: _deepSpace,
      fontFamily: 'Segoe UI',
      appBarTheme: AppBarTheme(
        backgroundColor: _surfaceDark,
        foregroundColor: _starWhite,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: _starWhite,
        ),
      ),
      cardTheme: CardThemeData(
        color: _cardDark,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: _surfaceDark,
        selectedIconTheme: const IconThemeData(color: _accentCyan),
        unselectedIconTheme: IconThemeData(color: _starWhite.withValues(alpha: 0.6)),
        indicatorColor: _accentCyan.withValues(alpha: 0.15),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: _surfaceDark,
        indicatorColor: _accentCyan.withValues(alpha: 0.15),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: _accentCyan);
          }
          return IconThemeData(color: _starWhite.withValues(alpha: 0.6));
        }),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return _accentCyan;
          return Colors.grey;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return _accentCyan.withValues(alpha: 0.3);
          }
          return Colors.grey.withValues(alpha: 0.2);
        }),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: _surfaceDarkElevated,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: _starWhite.withValues(alpha: 0.1)),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _accentCyan,
          foregroundColor: _deepSpace,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle:
              const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _accentCyan,
          side: const BorderSide(color: _accentCyan),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _surfaceDarkElevated,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      dividerTheme: DividerThemeData(
        color: _starWhite.withValues(alpha: 0.08),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: _surfaceDarkElevated,
        contentTextStyle: const TextStyle(color: _starWhite),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.light(
      primary: const Color(0xFF1565C0),
      onPrimary: Colors.white,
      secondary: _accentOrange,
      onSecondary: Colors.white,
      surface: const Color(0xFFF8F9FC),
      onSurface: const Color(0xFF1A1C2E),
      error: Colors.redAccent,
      onError: Colors.white,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFFF0F2F8),
      fontFamily: 'Segoe UI',
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFF8F9FC),
        foregroundColor: Color(0xFF1A1C2E),
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1A1C2E),
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: const Color(0xFFF8F9FC),
        selectedIconTheme: const IconThemeData(color: Color(0xFF1565C0)),
        unselectedIconTheme:
            IconThemeData(color: const Color(0xFF1A1C2E).withValues(alpha: 0.5)),
        indicatorColor: const Color(0xFF1565C0).withValues(alpha: 0.1),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFFF8F9FC),
        indicatorColor: const Color(0xFF1565C0).withValues(alpha: 0.1),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1565C0),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle:
              const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF1565C0),
          side: const BorderSide(color: Color(0xFF1565C0)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF1A1C2E),
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
