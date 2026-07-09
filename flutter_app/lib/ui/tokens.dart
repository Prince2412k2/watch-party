import 'package:flutter/widgets.dart';

/// FROZEN CONTRACT (PLAN §3.6). Cinematic-minimal design tokens, ported from the
/// shipped web system (`app/client/src/lib/ui.jsx` `C`, SANS/MONO). Monochrome
/// near-black → near-white ramp, ONE semantic red for danger/live only. No
/// gradients, no glass. E1 fleshes out the component visuals; these token values
/// are the source of truth every widget reads.
abstract final class AppColors {
  static const bg = Color(0xFF0A0A0B);
  static const surface = Color(0xFF141416);
  static const surface2 = Color(0xFF1E1E21);
  static const surface3 = Color(0xFF2A2A2E);

  static const text = Color(0xFFF4F4F5);
  static const dim = Color(0x9EF4F4F5); // .62
  static const faint = Color(0x5CF4F4F5); // .36

  static const line = Color(0x14FFFFFF); // .08
  static const line2 = Color(0x24FFFFFF); // .14

  /// Near-white primary control (the Play pill) — NOT a color accent.
  static const accent = Color(0xFFF4F4F5);
  static const accentDim = Color(0xFFCBCBCE);
  static const onAccent = Color(0xFF0A0A0B);

  /// Semantic status ONLY — never decorative, never a brand hue.
  static const green = Color(0xFF5AB98A); // success tick, sparingly
  static const red = Color(0xFFE0655E); // danger
  static const live = Color(0xFFE0655E); // active-download / recording dot
}

abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  static const double radiusSm = 8;
  static const double radius = 10;
  static const double radiusLg = 16;
  static const double radiusPill = 999;
}

abstract final class AppFonts {
  /// Matches the web `SANS` stack (falls back to system UI when unbundled).
  static const sans = 'Hanken Grotesk';

  /// Matches the web `MONO` stack.
  static const mono = 'JetBrains Mono';
}
