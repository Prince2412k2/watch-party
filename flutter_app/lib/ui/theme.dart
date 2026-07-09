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
    );
  }

  /// A few named text styles the widgets reference directly.
  static const TextStyle titleLarge = TextStyle(
    fontFamily: AppFonts.sans,
    fontSize: 20,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
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

  static const TextStyle mono = TextStyle(
    fontFamily: AppFonts.mono,
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: AppColors.text,
  );
}
