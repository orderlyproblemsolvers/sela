import 'package:flutter/material.dart';

import 'motion.dart';

const _serifFallback = [
  'Georgia',
  'Cambria',
  'Times New Roman',
  'Noto Serif',
  'serif',
];

/// Serif headings, system sans for body text (works fully offline).
TextStyle serif(TextStyle? base) => (base ?? const TextStyle())
    .copyWith(fontFamily: 'Georgia', fontFamilyFallback: _serifFallback);

const _light = ColorScheme(
  brightness: Brightness.light,
  primary: Color(0xFFC6613F),
  onPrimary: Colors.white,
  primaryContainer: Color(0xFFF3DDD2),
  onPrimaryContainer: Color(0xFF4A2314),
  secondary: Color(0xFF5E5D59),
  onSecondary: Colors.white,
  secondaryContainer: Color(0xFFF0E8DD),
  onSecondaryContainer: Color(0xFF3D3929),
  error: Color(0xFFB3261E),
  onError: Colors.white,
  errorContainer: Color(0xFFF9E3DE),
  onErrorContainer: Color(0xFF5A1510),
  surface: Color(0xFFFAF9F5),
  onSurface: Color(0xFF141413),
  onSurfaceVariant: Color(0xFF5E5D59),
  outline: Color(0xFFB0AEA5),
  outlineVariant: Color(0xFFE8E6DC),
  surfaceContainerLowest: Colors.white,
  surfaceContainerLow: Color(0xFFF5F4EE),
  surfaceContainer: Color(0xFFF0EEE6),
  surfaceContainerHigh: Color(0xFFEBE9DF),
  surfaceContainerHighest: Color(0xFFE8E6DC),
);

const _dark = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFFD97757),
  onPrimary: Color(0xFF2B140A),
  primaryContainer: Color(0xFF5A2D1D),
  onPrimaryContainer: Color(0xFFF3DDD2),
  secondary: Color(0xFFB0AEA5),
  onSecondary: Color(0xFF262624),
  secondaryContainer: Color(0xFF3A3A37),
  onSecondaryContainer: Color(0xFFE8E6DC),
  error: Color(0xFFF2B8B5),
  onError: Color(0xFF601410),
  errorContainer: Color(0xFF5A1510),
  onErrorContainer: Color(0xFFF9DEDC),
  surface: Color(0xFF262624),
  onSurface: Color(0xFFFAF9F5),
  onSurfaceVariant: Color(0xFFB0AEA5),
  outline: Color(0xFF6B6A66),
  outlineVariant: Color(0xFF3E3E3B),
  surfaceContainerLowest: Color(0xFF30302E),
  surfaceContainerLow: Color(0xFF2B2B29),
  surfaceContainer: Color(0xFF30302E),
  surfaceContainerHigh: Color(0xFF3A3A37),
  surfaceContainerHighest: Color(0xFF444441),
);

class AppTheme {
  static ThemeData light() => _build(_light);
  static ThemeData dark() => _build(_dark);

  static ThemeData _build(ColorScheme s) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: s,
      brightness: s.brightness,
    );
    final tt = base.textTheme
        .apply(bodyColor: s.onSurface, displayColor: s.onSurface);
    final textTheme = tt.copyWith(
      displayLarge: serif(tt.displayLarge),
      displayMedium: serif(tt.displayMedium),
      displaySmall: serif(tt.displaySmall),
      headlineLarge: serif(tt.headlineLarge),
      headlineMedium: serif(tt.headlineMedium),
      headlineSmall: serif(tt.headlineSmall),
      titleLarge: serif(tt.titleLarge),
    );

    RoundedRectangleBorder rounded(double r, {bool border = false}) =>
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(r),
          side: border
              ? BorderSide(color: s.outlineVariant)
              : BorderSide.none,
        );

    OutlineInputBorder field(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c, width: w),
        );

    return base.copyWith(
      scaffoldBackgroundColor: s.surface,
      textTheme: textTheme,
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          for (final p in TargetPlatform.values)
            p: const MotionPageTransitionsBuilder(),
        },
      ),
      dividerTheme: DividerThemeData(
        color: s.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: s.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: s.onSurface),
        titleTextStyle: serif(textTheme.titleLarge)
            .copyWith(fontSize: 22, fontWeight: FontWeight.w500),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: s.surface,
        surfaceTintColor: Colors.transparent,
      ),
      navigationDrawerTheme: NavigationDrawerThemeData(
        backgroundColor: s.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: s.primaryContainer,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: s.primary,
        foregroundColor: s.onPrimary,
        elevation: 2,
        highlightElevation: 3,
        shape: const StadiumBorder(),
        extendedTextStyle:
            const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: s.primary,
          foregroundColor: s.onPrimary,
          shape: rounded(12),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: s.primary,
          shape: rounded(12),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: s.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        shape: rounded(14, border: true),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: s.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shape: rounded(20),
        titleTextStyle:
            serif(textTheme.titleLarge).copyWith(fontSize: 22, color: s.onSurface),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: s.surfaceContainerLowest,
        modalBackgroundColor: s.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: s.onSurface,
        contentTextStyle: TextStyle(color: s.surface),
        actionTextColor: const Color(0xFFE8A58C),
        shape: rounded(12),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: s.surfaceContainerLowest,
        border: field(s.outlineVariant),
        enabledBorder: field(s.outlineVariant),
        focusedBorder: field(s.primary, 1.5),
      ),
    );
  }
}
