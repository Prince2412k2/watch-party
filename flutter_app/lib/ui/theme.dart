import 'package:flutter/material.dart';

import 'tokens.dart';

/// The Watchparty dark theme — the cinematic-minimal tokens mapped onto
/// [ThemeData]. E1 refines type scale + component themes; this is the frozen
/// baseline every screen inherits.
abstract final class AppTheme {
  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      surface: AppColors.bg,
      onSurface: AppColors.text,
      primary: AppColors.accent,
      onPrimary: AppColors.onAccent,
      secondary: AppColors.surface2,
      onSecondary: AppColors.text,
      error: AppColors.red,
      onError: AppColors.text,
      outline: AppColors.line2,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.bg,
      canvasColor: AppColors.bg,
      // System font fallback works even without the bundled font files.
      fontFamily: AppFonts.sans,
      splashFactory: NoSplash.splashFactory,
      dividerColor: AppColors.line,
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.text,
        displayColor: AppColors.text,
      ),
      scrollbarTheme: const ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(AppColors.line2),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.surface3,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          border: Border.all(color: AppColors.line),
        ),
        textStyle: const TextStyle(color: AppColors.text, fontSize: 12),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.accent,
        linearTrackColor: AppColors.line2,
      ),
      dialogTheme: const DialogThemeData(backgroundColor: AppColors.surface),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surface2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          side: const BorderSide(color: AppColors.line),
        ),
      ),
    );
  }

  /// The type scale (PLAN §0/§3.6). Named after intent, not size — screens
  /// reach for `AppTheme.titleLarge` etc. rather than raw `TextStyle`s.
  static const TextStyle displaySmall = TextStyle(
    fontFamily: AppFonts.sans,
    fontSize: 28,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.6,
    color: AppColors.text,
  );

  static const TextStyle titleLarge = TextStyle(
    fontFamily: AppFonts.sans,
    fontSize: 20,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
    color: AppColors.text,
  );

  static const TextStyle titleMedium = TextStyle(
    fontFamily: AppFonts.sans,
    fontSize: 16,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
    color: AppColors.text,
  );

  static const TextStyle body = TextStyle(
    fontFamily: AppFonts.sans,
    fontSize: 14.5,
    fontWeight: FontWeight.w500,
    color: AppColors.text,
  );

  static const TextStyle dim = TextStyle(
    fontFamily: AppFonts.sans,
    fontSize: 13.5,
    fontWeight: FontWeight.w500,
    color: AppColors.dim,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: AppFonts.sans,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: AppColors.faint,
  );

  static const TextStyle mono = TextStyle(
    fontFamily: AppFonts.mono,
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: AppColors.text,
  );
}
