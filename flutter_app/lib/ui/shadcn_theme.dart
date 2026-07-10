import 'package:flutter/widgets.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sc;

import 'tokens.dart';

/// The shadcn_flutter theme bridge (PLAN PKG-0 §"Theme bridge").
///
/// Maps the FROZEN cinematic-minimal tokens in [AppColors]/[AppSpacing]/
/// [AppFonts] onto a shadcn [sc.ThemeData] so the rebuilt `lib/ui/widgets/*`
/// primitives render on shadcn components while keeping the exact monochrome
/// near-black→white identity and the single reserved red. No token VALUES are
/// changed here — this is a projection, not a repaint.
///
/// Wired once in `app.dart` via `sc.ShadcnLayer(theme: AppShadcnTheme.dark)`.
abstract final class AppShadcnTheme {
  /// Monochrome dark scheme. Mapping (per plan):
  /// background→bg, foreground→text, card→surface, popover→surface2,
  /// primary→accent (near-white) / primaryForeground→onAccent,
  /// secondary→surface, muted→surface2 / mutedForeground→dim,
  /// accent→surface2 (hover), destructive→red, border/input→line2, ring→dim.
  static const sc.ColorScheme _scheme = sc.ColorScheme(
    brightness: Brightness.dark,
    background: AppColors.bg,
    foreground: AppColors.text,
    card: AppColors.surface,
    cardForeground: AppColors.text,
    popover: AppColors.surface2,
    popoverForeground: AppColors.text,
    primary: AppColors.accent,
    primaryForeground: AppColors.onAccent,
    secondary: AppColors.surface,
    secondaryForeground: AppColors.text,
    muted: AppColors.surface2,
    mutedForeground: AppColors.dim,
    accent: AppColors.surface2,
    accentForeground: AppColors.text,
    destructive: AppColors.red,
    destructiveForeground: AppColors.text,
    border: AppColors.line2,
    input: AppColors.line2,
    ring: AppColors.dim,
    // Charts are unused by this app; keep them on the monochrome ramp so nothing
    // ever renders a stray brand hue.
    chart1: AppColors.accent,
    chart2: AppColors.accentDim,
    chart3: AppColors.dim,
    chart4: AppColors.faint,
    chart5: AppColors.surface3,
  );

  /// Custom typography on the app's Hanken Grotesk / JetBrains Mono stacks
  /// (falls back to system fonts when unbundled — identity is preserved).
  static const sc.Typography _typography = sc.Typography.geist(
    sans: TextStyle(fontFamily: AppFonts.sans),
    mono: TextStyle(fontFamily: AppFonts.mono),
    inlineCode: TextStyle(
      fontFamily: AppFonts.mono,
      fontSize: 14,
      fontWeight: FontWeight.w600,
    ),
  );

  /// The one shadcn theme the whole app runs on. [sc.ThemeData.radius] is a
  /// multiplier (radiusMd = radius * 12); ~0.85 lands component radii near the
  /// token's 10px. surfaceOpacity/surfaceBlur give overlays the acrylic feel
  /// the RGBA-transparent window affords.
  static sc.ThemeData get dark => sc.ThemeData(
    colorScheme: _scheme,
    typography: _typography,
    radius: AppSpacing.radius / 12,
    surfaceOpacity: 0.9,
    surfaceBlur: 16,
    platform: TargetPlatform.linux,
  );
}
