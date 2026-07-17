import 'package:flutter/material.dart';

import 'palette.dart';
import 'theme_mode.dart';
import 'tokens.dart';

/// Builds the Watchparty [ThemeData] for any of the three [WpPalette]s. The
/// chosen palette is attached as a [ThemeExtension] so widgets read it live via
/// `context.wp`. The app root swaps `theme:`/`darkTheme:` with the mode from
/// `state/theme_provider.dart`; switching only rebuilds the theme boundary and
/// never remounts the functional subtrees (PLAN §global invariants).
abstract final class AppTheme {
  static ThemeData build(WpPalette p) {
    final isLight = p.brightness == Brightness.light;
    final scheme =
        (isLight ? const ColorScheme.light() : const ColorScheme.dark())
            .copyWith(
              brightness: p.brightness,
              surface: p.bg,
              onSurface: p.text,
              primary: p.accent,
              onPrimary: p.onAccent,
              secondary: p.surface2,
              onSecondary: p.text,
              error: AppColors.red,
              onError: const Color(0xFFFFFFFF),
              outline: p.line2,
            );

    final base = ThemeData(
      useMaterial3: true,
      brightness: p.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.bg,
      canvasColor: p.bg,
      fontFamily: AppFonts.sans,
      splashFactory: NoSplash.splashFactory,
      dividerColor: p.line,
      extensions: [p],
    );

    return base.copyWith(
      textTheme: _buildTextTheme(p),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(p.line2),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: p.surface3,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          border: Border.all(color: p.line),
        ),
        textStyle: TextStyle(color: p.text, fontSize: 12),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.accent,
        linearTrackColor: p.line2,
      ),
      dialogTheme: DialogThemeData(backgroundColor: p.surface),
      popupMenuTheme: PopupMenuThemeData(
        color: p.surface2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          side: BorderSide(color: p.line),
        ),
      ),
    );
  }

  static TextTheme _buildTextTheme(WpPalette p) {
    return TextTheme(
      displayLarge: displayLarge.copyWith(color: p.text),
      displayMedium: headlineLarge.copyWith(color: p.text),
      displaySmall: displaySmall.copyWith(color: p.text),
      headlineLarge: headlineLarge.copyWith(color: p.text),
      headlineMedium: headlineMedium.copyWith(color: p.text),
      titleLarge: titleLarge.copyWith(color: p.text),
      titleMedium: titleMedium.copyWith(color: p.text),
      bodyLarge: body.copyWith(color: p.text),
      bodyMedium: body.copyWith(color: p.text),
      bodySmall: label.copyWith(color: p.dim),
      labelLarge: label.copyWith(color: p.text),
    );
  }

  static ThemeData get light => build(kLightPalette);
  static ThemeData get balanced => build(kBalancedPalette);

  /// The existing dark entry point — preserved so callers that still reference
  /// `AppTheme.dark` keep compiling.
  static ThemeData get dark => build(kDarkPalette);

  static ThemeData forMode(AppThemeMode mode) => build(WpPalette.of(mode));

  // ── Type scale (design guide §Typography) ────────────────────────────────
  // Circular Light (w300) for headings, Book (w400) for body/labels, Bold
  // (w700) sparingly. Heading tracking is -0.04em, computed as -0.04 * size.

  /// Major / detail-title heading (40–56px). Used by the detail screens.
  static const TextStyle displayLarge = TextStyle(
    fontFamily: AppFonts.sans,
    fontSize: 52,
    fontWeight: FontWeight.w300,
    height: 1.1,
    letterSpacing: -2.08, // -0.04em
    color: AppColors.text,
  );

  /// Section heading (34–44px). Used by library/discover shelf titles.
  static const TextStyle headlineLarge = TextStyle(
    fontFamily: AppFonts.sans,
    fontSize: 40,
    fontWeight: FontWeight.w300,
    height: 1.1,
    letterSpacing: -1.6, // -0.04em
    color: AppColors.text,
  );

  /// A smaller Circular-Light heading for tighter surfaces.
  static const TextStyle headlineMedium = TextStyle(
    fontFamily: AppFonts.sans,
    fontSize: 30,
    fontWeight: FontWeight.w300,
    height: 1.1,
    letterSpacing: -1.2, // -0.04em
    color: AppColors.text,
  );

  /// Preserved name — now a Circular-Light heading (was w800/28px, rejected by
  /// the guide).
  static const TextStyle displaySmall = TextStyle(
    fontFamily: AppFonts.sans,
    fontSize: 28,
    fontWeight: FontWeight.w300,
    height: 1.1,
    letterSpacing: -1.12, // -0.04em
    color: AppColors.text,
  );

  static const TextStyle titleLarge = TextStyle(
    fontFamily: AppFonts.sans,
    fontSize: 20,
    fontWeight: FontWeight.w500,
    height: 1.15,
    letterSpacing: -0.4,
    color: AppColors.text,
  );

  static const TextStyle titleMedium = TextStyle(
    fontFamily: AppFonts.sans,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.2,
    color: AppColors.text,
  );

  /// Body copy — Circular Book, generous line height.
  static const TextStyle body = TextStyle(
    fontFamily: AppFonts.sans,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.75,
    color: AppColors.text,
  );

  /// UI label — Circular Book, compact.
  static const TextStyle label = TextStyle(
    fontFamily: AppFonts.sans,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.text,
  );

  static const TextStyle dim = TextStyle(
    fontFamily: AppFonts.sans,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.dim,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: AppFonts.sans,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.faint,
  );

  /// Poster card title (14px, centered, Book).
  static const TextStyle posterTitle = TextStyle(
    fontFamily: AppFonts.sans,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.35,
    color: AppColors.text,
  );

  static const TextStyle mono = TextStyle(
    fontFamily: AppFonts.mono,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.text,
  );
}
