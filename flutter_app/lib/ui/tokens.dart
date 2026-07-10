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

/// Motion system (PLAN PKG-0 §Motion). Durations/curves the redesign reads for
/// route transitions, list stagger, hover, and micro-interactions. ADDITIVE —
/// no existing token values change. Kept short and calm to match the cinematic,
/// content-first identity (no bouncy overshoot except the floating-tile snap).
abstract final class AppMotion {
  /// Fade-through page transition (route push).
  static const Duration page = Duration(milliseconds: 180);

  /// Reveal / staggered list-item entrance.
  static const Duration reveal = Duration(milliseconds: 220);

  /// Per-index delay between staggered items.
  static const Duration stagger = Duration(milliseconds: 40);

  /// Hover / active-state cross-fades (poster scale, nav highlight).
  static const Duration hover = Duration(milliseconds: 140);

  /// Floating camera-tile drag-end snap + collapse.
  static const Duration snap = Duration(milliseconds: 260);

  static const Curve emphasized = Curves.easeOutCubic;
  static const Curve standard = Curves.easeOut;

  /// Spring-ish curve for the floating-tile snap/collapse.
  static const Curve spring = Curves.easeOutBack;
}

/// Blur radii for acrylic overlay surfaces (menus/dialogs/toasts/scrim). The
/// RGBA-transparent, Skia-rendered window makes blur viable; keep radii modest.
abstract final class AppBlur {
  static const double overlay = 16;
  static const double scrim = 8;
}

/// Elevation shadow presets for floating surfaces (poster hover, PiP tiles).
abstract final class AppElevation {
  static const List<BoxShadow> low = [
    BoxShadow(color: Color(0x40000000), blurRadius: 8, offset: Offset(0, 2)),
  ];
  static const List<BoxShadow> high = [
    BoxShadow(color: Color(0x66000000), blurRadius: 20, offset: Offset(0, 8)),
  ];
}
