import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sc;

import 'palette.dart';
import 'theme_mode.dart';
import 'tokens.dart';

/// The shadcn_flutter theme bridge, now per-[WpPalette] so all three modes get
/// a matching `sc.ThemeData`. Surfaces are flat (the redesign removed acrylic
/// blur everywhere except the balanced ambient wash and the dialog scrim), the
/// radius multiplier lands component radii on the 12px base, and typography is
/// the bundled Circular XX / JetBrains Mono stack.
///
/// The app root switches `sc.ShadcnLayer(theme:)` with the active mode; the
/// existing `AppShadcnTheme.dark` entry point is preserved.
abstract final class AppShadcnTheme {
  static sc.ColorScheme _scheme(WpPalette p) => sc.ColorScheme(
    brightness: p.brightness,
    background: p.bg,
    foreground: p.text,
    card: p.surface,
    cardForeground: p.text,
    popover: p.surface2,
    popoverForeground: p.text,
    primary: p.accent,
    primaryForeground: p.onAccent,
    secondary: p.surface,
    secondaryForeground: p.text,
    muted: p.surface2,
    mutedForeground: p.dim,
    accent: p.surface2,
    accentForeground: p.text,
    destructive: AppColors.red,
    destructiveForeground: const Color(0xFFFFFFFF),
    border: p.line2,
    input: p.line2,
    ring: p.dim,
    // Charts are unused; keep them on the neutral ramp so no stray hue renders.
    chart1: p.accent,
    chart2: p.dim,
    chart3: p.faint,
    chart4: p.surface3,
    chart5: p.surface2,
  );

  static const sc.Typography _typography = sc.Typography.geist(
    sans: TextStyle(fontFamily: AppFonts.sans),
    mono: TextStyle(fontFamily: AppFonts.mono),
    inlineCode: TextStyle(
      fontFamily: AppFonts.mono,
      fontSize: 14,
      fontWeight: FontWeight.w500,
    ),
  );

  static sc.ThemeData build(WpPalette p) => sc.ThemeData(
    colorScheme: _scheme(p),
    typography: _typography,
    // radius is a multiplier (radiusMd = radius * 12); 1.0 → 12px base.
    radius: AppSpacing.radius / 12,
    surfaceOpacity: 1.0,
    surfaceBlur: 0,
    platform: defaultTargetPlatform,
  );

  static sc.ThemeData get light => build(kLightPalette);
  static sc.ThemeData get balanced => build(kBalancedPalette);

  /// Preserved dark entry point.
  static sc.ThemeData get dark => build(kDarkPalette);

  static sc.ThemeData forMode(AppThemeMode mode) => build(WpPalette.of(mode));
}
