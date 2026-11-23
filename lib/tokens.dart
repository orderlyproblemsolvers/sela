/// Design tokens. One scale for spacing, one for corner radii, one for timing.
/// Screens and the theme reference these instead of ad-hoc numbers.
///
/// Spacing follows a 4/8 rhythm. Radii are four steps. Durations stay in the
/// 150-300ms band for UI feedback (route changes are the only 300).
abstract final class Space {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

abstract final class Radii {
  static const double sm = 8; // chips
  static const double md = 12; // inputs, buttons, menus
  static const double lg = 16; // cards, folder tiles
  static const double xl = 24; // dialogs, sheets
}

abstract final class Dur {
  static const Duration fast = Duration(milliseconds: 150); // swaps, hover
  static const Duration base = Duration(milliseconds: 220); // enter/exit
  static const Duration route = Duration(milliseconds: 300); // container transform
}

/// Minimum interactive size (Material 48dp, above Apple's 44pt).
const double kMinHit = 48;