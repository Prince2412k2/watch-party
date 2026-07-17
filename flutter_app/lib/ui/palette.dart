import 'package:flutter/material.dart';

import 'theme_mode.dart';

/// Brand red — a NON-decorative identity accent (the wordmark, the centered
/// bottom-nav active underline, poster rating stars, the profile notification
/// dot). Distinct from [kSemanticRed]: never used for danger/destructive state.
const Color kBrandRed = Color(0xFFD81F2A);

/// Semantic danger / live red (`--red`). Destructive actions, error toasts, and
/// the active-download / recording dot. Never used as a brand accent.
const Color kSemanticRed = Color(0xFFE0655E);

/// Success tick — used sparingly.
const Color kSuccessGreen = Color(0xFF5AB98A);

/// The party-live indicator dot (`.web-party-button.is-live`).
const Color kPartyLive = Color(0xFF78C99F);

/// A full semantic colour set for one theme — the Flutter port of the web
/// `--wp-*` custom properties (styles.css `.web-app` theme blocks). Registered
/// as a [ThemeExtension] on the active [ThemeData] so any widget can read the
/// live palette via `context.wp` without threading it through constructors.
@immutable
class WpPalette extends ThemeExtension<WpPalette> {
  const WpPalette({
    required this.mode,
    required this.brightness,
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.text,
    required this.dim,
    required this.faint,
    required this.line,
    required this.line2,
    required this.stage,
    required this.nav,
    required this.shadow,
    required this.accent,
    required this.onAccent,
    required this.ambientOpacity,
    required this.ambientBlur,
    required this.ambientBrightness,
  });

  final AppThemeMode mode;
  final Brightness brightness;

  /// Page background (`--wp-bg`).
  final Color bg;

  /// Surface ramp (`--wp-surface`, `-2`, `-3`).
  final Color surface;
  final Color surface2;
  final Color surface3;

  /// Primary text (`--wp-text`) and its dim/faint derivations.
  final Color text;
  final Color dim;
  final Color faint;

  /// Hairline strokes (`--wp-line`, `--wp-line-2`).
  final Color line;
  final Color line2;

  /// The translucent scrim painted over the ambient wash (`--wp-stage`).
  final Color stage;

  /// Bottom-nav surface (`--wp-nav`).
  final Color nav;

  /// Shadow colour for every elevation (`--wp-shadow`).
  final Color shadow;

  /// The near-solid control fill (the Play pill) = text; its foreground = bg.
  final Color accent;
  final Color onAccent;

  /// Ambient-wash intensity for this mode: opacity of the blurred artwork layer
  /// (1.0 balanced, .42 dark, .3 light), the blur sigma, and a brightness lift
  /// (light washes the artwork paler).
  final double ambientOpacity;
  final double ambientBlur;
  final double ambientBrightness;

  /// glass.tsx SURFACE elevation scale, keyed to the theme's [shadow].
  List<BoxShadow> get elevationLight =>
      [BoxShadow(color: shadow, blurRadius: 12, offset: const Offset(0, 2))];
  List<BoxShadow> get elevationMedium =>
      [BoxShadow(color: shadow, blurRadius: 30, offset: const Offset(0, 8))];
  List<BoxShadow> get elevationHeavy =>
      [BoxShadow(color: shadow, blurRadius: 46, offset: const Offset(0, 18))];

  /// Poster art shadow (`.library-poster-art`) and its hover strengthening.
  List<BoxShadow> get posterShadow =>
      [BoxShadow(color: shadow, blurRadius: 20, offset: const Offset(0, 8))];
  List<BoxShadow> get posterShadowHover =>
      [BoxShadow(color: shadow, blurRadius: 28, offset: const Offset(0, 16))];

  /// Party-card / dialog float (`0 24px 70px`).
  List<BoxShadow> get cardShadow =>
      [BoxShadow(color: shadow, blurRadius: 70, offset: const Offset(0, 24))];

  @override
  WpPalette copyWith({
    AppThemeMode? mode,
    Brightness? brightness,
    Color? bg,
    Color? surface,
    Color? surface2,
    Color? surface3,
    Color? text,
    Color? dim,
    Color? faint,
    Color? line,
    Color? line2,
    Color? stage,
    Color? nav,
    Color? shadow,
    Color? accent,
    Color? onAccent,
    double? ambientOpacity,
    double? ambientBlur,
    double? ambientBrightness,
  }) {
    return WpPalette(
      mode: mode ?? this.mode,
      brightness: brightness ?? this.brightness,
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surface2: surface2 ?? this.surface2,
      surface3: surface3 ?? this.surface3,
      text: text ?? this.text,
      dim: dim ?? this.dim,
      faint: faint ?? this.faint,
      line: line ?? this.line,
      line2: line2 ?? this.line2,
      stage: stage ?? this.stage,
      nav: nav ?? this.nav,
      shadow: shadow ?? this.shadow,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      ambientOpacity: ambientOpacity ?? this.ambientOpacity,
      ambientBlur: ambientBlur ?? this.ambientBlur,
      ambientBrightness: ambientBrightness ?? this.ambientBrightness,
    );
  }

  @override
  WpPalette lerp(covariant WpPalette? other, double t) {
    if (other == null) return this;
    return WpPalette(
      mode: t < 0.5 ? mode : other.mode,
      brightness: t < 0.5 ? brightness : other.brightness,
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      surface3: Color.lerp(surface3, other.surface3, t)!,
      text: Color.lerp(text, other.text, t)!,
      dim: Color.lerp(dim, other.dim, t)!,
      faint: Color.lerp(faint, other.faint, t)!,
      line: Color.lerp(line, other.line, t)!,
      line2: Color.lerp(line2, other.line2, t)!,
      stage: Color.lerp(stage, other.stage, t)!,
      nav: Color.lerp(nav, other.nav, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      ambientOpacity: _lerpD(ambientOpacity, other.ambientOpacity, t),
      ambientBlur: _lerpD(ambientBlur, other.ambientBlur, t),
      ambientBrightness: _lerpD(ambientBrightness, other.ambientBrightness, t),
    );
  }

  static double _lerpD(double a, double b, double t) => a + (b - a) * t;

  /// Resolve the palette for a given [mode].
  static WpPalette of(AppThemeMode mode) => switch (mode) {
    AppThemeMode.light => kLightPalette,
    AppThemeMode.balanced => kBalancedPalette,
    AppThemeMode.dark => kDarkPalette,
  };
}

/// DARK (`.web-app` default block, styles.css:198-226).
const WpPalette kDarkPalette = WpPalette(
  mode: AppThemeMode.dark,
  brightness: Brightness.dark,
  bg: Color(0xFF101113),
  surface: Color(0xFF17181B),
  surface2: Color(0xFF222327),
  surface3: Color(0xFF2C2E33),
  text: Color(0xFFF2F1ED),
  dim: Color(0xA3F2F1ED), // rgba(242,241,237,.64)
  faint: Color(0x61F2F1ED), // rgba(242,241,237,.38)
  line: Color(0x1AFFFFFF), // rgba(255,255,255,.1)
  line2: Color(0x2BFFFFFF), // rgba(255,255,255,.17)
  stage: Color(0xD10F1012), // rgba(15,16,18,.82)
  nav: Color(0xE618191C), // rgba(24,25,28,.9)
  shadow: Color(0x5C000000), // rgba(0,0,0,.36)
  accent: Color(0xFFF2F1ED),
  onAccent: Color(0xFF101113),
  ambientOpacity: 0.42,
  ambientBlur: 72,
  ambientBrightness: 1.0,
);

/// LIGHT (styles.css:227-241). Code wins over the guide's ~#f7f7f7 stage note:
/// a pure-white bg with off-white surfaces.
const WpPalette kLightPalette = WpPalette(
  mode: AppThemeMode.light,
  brightness: Brightness.light,
  bg: Color(0xFFFFFFFF),
  surface: Color(0xFFEBEAE5),
  surface2: Color(0xFFDFDED8),
  surface3: Color(0xFFD3D2CB),
  text: Color(0xFF171719),
  dim: Color(0xA3171719), // rgba(23,23,25,.64)
  faint: Color(0x66171719), // rgba(23,23,25,.4)
  line: Color(0x1A141416), // rgba(20,20,22,.1)
  line2: Color(0x2E141416), // rgba(20,20,22,.18)
  stage: Color(0xD6FFFFFF), // rgba(255,255,255,.84)
  nav: Color(0xE6FFFFFF), // rgba(255,255,255,.9)
  shadow: Color(0x2E1B1914), // rgba(27,25,20,.18)
  accent: Color(0xFF171719),
  onAccent: Color(0xFFFFFFFF),
  ambientOpacity: 0.3,
  ambientBlur: 88,
  ambientBrightness: 1.24,
);

/// BALANCED (styles.css:242-245): the dark tokens with a lighter page bg and a
/// thinner stage scrim so the selected artwork reads through at full strength.
const WpPalette kBalancedPalette = WpPalette(
  mode: AppThemeMode.balanced,
  brightness: Brightness.dark,
  bg: Color(0xFF15161A),
  surface: Color(0xFF17181B),
  surface2: Color(0xFF222327),
  surface3: Color(0xFF2C2E33),
  text: Color(0xFFF2F1ED),
  dim: Color(0xA3F2F1ED),
  faint: Color(0x61F2F1ED),
  line: Color(0x1AFFFFFF),
  line2: Color(0x2BFFFFFF),
  stage: Color(0xC20F1012), // rgba(15,16,18,.76)
  nav: Color(0xE618191C),
  shadow: Color(0x5C000000),
  accent: Color(0xFFF2F1ED),
  onAccent: Color(0xFF15161A),
  ambientOpacity: 1.0,
  ambientBlur: 72,
  ambientBrightness: 1.0,
);

/// The active palette for the current [BuildContext] — reads the [WpPalette]
/// [ThemeExtension] the app's [ThemeData] carries, falling back to dark before
/// a theme is mounted (e.g. in isolated widget tests).
extension WpPaletteContext on BuildContext {
  WpPalette get wp =>
      Theme.of(this).extension<WpPalette>() ?? kDarkPalette;
}
