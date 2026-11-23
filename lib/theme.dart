import 'package:flutter/material.dart';

import 'motion.dart';
import 'tokens.dart';

const _serifFallback = [
  'Georgia',
  'Cambria',
  'Times New Roman',
  'Noto Serif',
  'serif',
];

/// Serif is reserved for display/headline/title text (the wordmark, screen
/// intros, note titles). App chrome such as dialogs and the app bar uses the
/// system sans. Works fully offline.
TextStyle serif(TextStyle? base) => (base ?? const TextStyle())
    .copyWith(fontFamily: 'Georgia', fontFamilyFallback: _serifFallback);

// Palette: warm clay on warm paper, a few degrees off the usual terracotta
// (primary is darker and redder; neutrals lean slightly more yellow).
// Contrast was checked by hand: light primary/onPrimary ~4.9:1,
// onSurfaceVariant ~6.4:1 on surface; dark primary ~5.3:1 on surface.
// Re-verify with a contrast tool if you tweak any value.
const _light = ColorScheme(
  brightness: Brightness.light,
  primary: Color(0xFFB5532F),
  onPrimary: Colors.white,
  primaryContainer: Color(0xFFF2DACD),
  onPrimaryContainer: Color(0xFF44200F),
  secondary: Color(0xFF5B5953),
  onSecondary: Colors.white,
  secondaryContainer: Color(0xFFEDE6D9),
  onSecondaryContainer: Color(0xFF3A3626),
  error: Color(0xFFB3261E),
  onError: Colors.white,
  errorContainer: Color(0xFFF9DEDC),
  onErrorContainer: Color(0xFF410E0B),
  surface: Color(0xFFF7F5EF),
  onSurface: Color(0xFF1A1917),
  onSurfaceVariant: Color(0xFF5B5953),
  outline: Color(0xFF8F8D84),
  outlineVariant: Color(0xFFE5E2D7),
  inversePrimary: Color(0xFFE8977A),
  surfaceContainerLowest: Colors.white,
  surfaceContainerLow: Color(0xFFF3F1EA),
  surfaceContainer: Color(0xFFEEEBE2),
  surfaceContainerHigh: Color(0xFFE8E5DB),
  surfaceContainerHighest: Color(0xFFE3E0D5),
);

const _dark = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFFE4825F),
  onPrimary: Color(0xFF2E1508),
  primaryContainer: Color(0xFF5C301F),
  onPrimaryContainer: Color(0xFFF2DACD),
  secondary: Color(0xFFB3B0A6),
  onSecondary: Color(0xFF262521),
  secondaryContainer: Color(0xFF3B3A36),
  onSecondaryContainer: Color(0xFFE5E2D7),
  error: Color(0xFFF2B8B5),
  onError: Color(0xFF601410),
  errorContainer: Color(0xFF5A1510),
  onErrorContainer: Color(0xFFF9DEDC),
  surface: Color(0xFF2A2926),
  onSurface: Color(0xFFF7F5EF),
  onSurfaceVariant: Color(0xFFB3B0A6),
  outline: Color(0xFF77756D),
  outlineVariant: Color(0xFF42413D),
  inversePrimary: Color(0xFFB5532F),
  surfaceContainerLowest: Color(0xFF33322F),
  surfaceContainerLow: Color(0xFF2E2D2A),
  surfaceContainer: Color(0xFF33322F),
  surfaceContainerHigh: Color(0xFF3D3C38),
  surfaceContainerHighest: Color(0xFF474642),
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
          borderRadius: BorderRadius.circular(Radii.md),
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
        titleTextStyle: tt.titleLarge
            ?.copyWith(fontSize: 22, fontWeight: FontWeight.w600),
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
          shape: rounded(Radii.md),
          minimumSize: const Size(64, kMinHit),
          padding: const EdgeInsets.symmetric(horizontal: Space.xl),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: s.primary,
          shape: rounded(Radii.md),
          minimumSize: const Size(64, kMinHit),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: s.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        shape: rounded(Radii.md, border: true),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: s.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shape: rounded(Radii.xl),
        titleTextStyle: tt.titleLarge?.copyWith(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: s.onSurface,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: s.surfaceContainerLowest,
        modalBackgroundColor: s.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xl)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: s.onSurface,
        contentTextStyle: TextStyle(color: s.surface),
        actionTextColor: s.inversePrimary,
        shape: rounded(Radii.md),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: s.surfaceContainerLowest,
        border: field(s.outlineVariant),
        enabledBorder: field(s.outlineVariant),
        focusedBorder: field(s.primary, 2),
      ),
    );
  }
}