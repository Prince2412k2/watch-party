import 'package:flutter/widgets.dart';

import 'palette.dart';

/// Legacy const token surface, retained so the whole app keeps compiling while
/// the three-theme [WpPalette] system rolls out. The values now mirror the
/// redesigned web DARK palette (`--wp-*`, styles.css `.web-app`), so the app's
/// default appearance already matches the redesign's dark mode. Widgets that
/// have been theme-scoped read the LIVE palette via `context.wp`
/// ([WpPaletteContext]); these consts are the dark fallback for everything not
/// yet migrated.
abstract final class AppColors {
  static const bg = Color(0xFF101113);
  static const surface = Color(0xFF17181B);
  static const surface2 = Color(0xFF222327);
  static const surface3 = Color(0xFF2C2E33);

  static const text = Color(0xFFF2F1ED);
  static const dim = Color(0xA3F2F1ED); // .64
  static const faint = Color(0x61F2F1ED); // .38

  static const line = Color(0x1AFFFFFF); // .1
  static const line2 = Color(0x2BFFFFFF); // .17

  /// The near-solid primary control fill (the Play pill) = text in the dark
  /// palette. NOT a colour accent.
  static const accent = Color(0xFFF2F1ED);
  static const accentDim = Color(0xFFCBCBCE);
  static const onAccent = Color(0xFF101113);

  /// Brand red — identity accent (wordmark, nav underline, rating stars, notif
  /// dot). Distinct from the semantic [red]; never marks danger.
  static const brandRed = kBrandRed;

  /// Semantic status ONLY.
  static const green = kSuccessGreen; // success tick, sparingly
  static const red = kSemanticRed; // danger
  static const live = kSemanticRed; // active-download / recording dot
  static const partyLive = kPartyLive; // party-live indicator dot
}

abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// Web radii: `--r` 12 base, `--r-lg` 16, cards/dialogs 22, nav pills ~9,
  /// poster art 12, play pill fully rounded. [radiusSm] stays 8 for the small
  /// chrome affordances that predate the redesign.
  static const double radiusSm = 8;
  static const double radius = 12;
  static const double radiusLg = 16;
  static const double radiusCard = 22;
  static const double radiusPill = 999;
}

abstract final class AppFonts {
  /// The primary UI family (bundled `assets/fonts/CircularXX-*.ttf`).
  static const sans = 'CircularXX';

  /// Compact technical metadata (runtime, resolution, room codes, episodes).
  static const mono = 'JetBrains Mono';
}

/// Motion system (PLAN PKG-0 §Motion). Durations/curves the redesign reads for
/// route transitions, list stagger, hover, and micro-interactions. Kept short
/// and calm to match the cinematic, content-first identity.
abstract final class AppMotion {
  /// Fade-through page transition (route push).
  static const Duration page = Duration(milliseconds: 180);

  /// Reveal / staggered list-item entrance.
  static const Duration reveal = Duration(milliseconds: 220);

  /// Per-index delay between staggered items.
  static const Duration stagger = Duration(milliseconds: 40);

  /// Hover / active-state cross-fades (poster shadow, nav highlight).
  static const Duration hover = Duration(milliseconds: 180);

  /// Floating camera-tile drag-end snap + collapse.
  static const Duration snap = Duration(milliseconds: 260);

  static const Curve emphasized = Curves.easeOutCubic;
  static const Curve standard = Curves.easeOut;

  /// Spring-ish curve for the floating-tile snap/collapse.
  static const Curve spring = Curves.easeOutBack;
}

/// Blur radii for the two surfaces the redesign still blurs: the balanced
/// ambient wash and the dialog scrim. (glass.tsx removed all other blur.)
abstract final class AppBlur {
  static const double overlay = 16;
  static const double scrim = 8;
}

/// Elevation shadow presets. Prefer the theme-scoped [WpPalette] shadow helpers
/// (`context.wp.elevation*`); these dark-keyed consts remain for the surfaces
/// not yet migrated off the const token surface.
abstract final class AppElevation {
  static const List<BoxShadow> low = [
    BoxShadow(color: Color(0x5C000000), blurRadius: 12, offset: Offset(0, 2)),
  ];
  static const List<BoxShadow> high = [
    BoxShadow(color: Color(0x5C000000), blurRadius: 30, offset: Offset(0, 8)),
  ];
}
