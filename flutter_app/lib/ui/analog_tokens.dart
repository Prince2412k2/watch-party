// GENERATED FILE — DO NOT EDIT.
//
// Source:    app/shared/design/analog-tokens.json
// Generator: node app/shared/design/generate.mjs
//
// Edit the JSON and regenerate. A parity test in each client re-runs the
// generator and compares against these bytes, so hand-edits fail the suite.

import 'package:flutter/animation.dart';

/// Warm blacks and softly tinted neutrals — never pure black, never pure
/// white. R > G > B on every neutral.
abstract final class AnalogColor {
  static const Color stageVoid = Color(0xFF070605);
  static const Color stageGround = Color(0xFF0E0C0A);
  static const Color stageSurface = Color(0xFF16130F);
  static const Color stageSurface2 = Color(0xFF201C18);
  static const Color stageSurface3 = Color(0xFF2B2621);
  static const Color ink = Color(0xFFF4EFE6);
  static const Color inkDim = Color(0xA3F4EFE6);
  static const Color inkFaint = Color(0x61F4EFE6);
  static const Color line = Color(0x1AF4EFE6);
  static const Color lineStrong = Color(0x2EF4EFE6);
  static const Color edgeLight = Color(0x3DFFF6E8);
  static const Color edgeShade = Color(0x8C000000);
  static const Color shadowCast = Color(0x99120A04);
  static const Color shadowCastStrong = Color(0xC4120A04);
  static const Color backdropScrim = Color(0xD90E0C0A);
  static const Color backdropVignette = Color(0xB3070605);
  static const Color accent = Color(0xFFF4EFE6);
  static const Color onAccent = Color(0xFF0E0C0A);
  static const Color statusDanger = Color(0xFFE0655E);
  static const Color statusSuccess = Color(0xFF5AB98A);
  static const Color statusLive = Color(0xFFE0655E);
  static const Color statusPartyLive = Color(0xFF78C99F);
}

/// Fine, low-contrast film grain over the stage. Must never reduce text or
/// artwork clarity.
abstract final class AnalogGrain {
  static const double opacityPct = 3.5;
  static const double tilePx = 128.0;
  static const double focusedBoostPct = 1.5;
}

/// Square, unrounded artwork at EVERY size — including skeletons,
/// placeholders, season cards and selected states. radiusPx is 0 and is
/// asserted by tests in both clients.
abstract final class AnalogPoster {
  static const double radiusPx = 0.0;
  static const int aspectW = 2;
  static const int aspectH = 3;
  static const double framePx = 1.0;
  static const double gapPx = 14.0;
  static const double shelfPeekPx = 64.0;
}

/// Depth through scale, framing, light and position. No perspective tilt, no
/// bounce.
abstract final class AnalogSelection {
  static const double restScale = 1.0;
  static const double focusScale = 1.06;
  static const double focusLiftPx = 6.0;
  static const double focusBackdropDarkenPct = 22.0;
  static const double sceneLightAngleDeg = 315.0;
}

/// Directional cast shadows keyed to sceneLightAngleDeg (light above-left =>
/// shadow below-right).
abstract final class AnalogElevation {
  static const double restBlurPx = 18.0;
  static const double restOffsetXPx = 4.0;
  static const double restOffsetYPx = 8.0;
  static const double focusBlurPx = 34.0;
  static const double focusOffsetXPx = 8.0;
  static const double focusOffsetYPx = 18.0;
}

/// Mechanical and weighty: short travel, clear detents, restrained easing. No
/// elastic overshoot anywhere.
abstract final class AnalogMotion {
  static const Duration focusStepMs = Duration(milliseconds: 170);
  static const Cubic focusStepEase = Cubic(0.22, 0.61, 0.36, 1.0);
  static const Duration backdropCrossMs = Duration(milliseconds: 420);
  static const Cubic backdropCrossEase = Cubic(0.4, 0.0, 0.2, 1.0);
  static const Duration chromeFadeMs = Duration(milliseconds: 160);
  static const Cubic chromeFadeEase = Cubic(0.4, 0.0, 0.2, 1.0);
  static const Duration detentMs = Duration(milliseconds: 90);
  static const Cubic detentEase = Cubic(0.3, 0.0, 0.1, 1.0);
  static const Duration drawerMs = Duration(milliseconds: 260);
  static const Cubic drawerEase = Cubic(0.22, 0.61, 0.36, 1.0);
}

/// Timeline and volume are precision lines, not filled bars. The visible line
/// is thin; the hit target is not.
abstract final class AnalogHairline {
  static const double idlePx = 2.0;
  static const double activePx = 4.0;
  static const double hitPx = 24.0;
  static const double handlePx = 10.0;
  static const double handleFocusPx = 14.0;
  static const double rangeGapPx = 2.0;
}

/// Behavioural constants fixed by the design references; the interaction
/// cores in app/shared/design/interaction.json are driven by these same
/// numbers.
abstract final class AnalogTiming {
  static const Duration chromeAutoHideMs = Duration(milliseconds: 3000);
  static const Duration toastLifetimeMs = Duration(milliseconds: 4000);
  static const int toastMaxStack = 3;
}

abstract final class AnalogSpace {
  static const double xsPx = 4.0;
  static const double smPx = 8.0;
  static const double mdPx = 12.0;
  static const double lgPx = 16.0;
  static const double xlPx = 24.0;
  static const double xxlPx = 32.0;
  static const double stageGutterPx = 48.0;
  static const double stageGutterPhonePx = 20.0;
}

/// Artwork is always square. These radii are for chrome only (buttons,
/// sheets, toasts) and must never be applied to a poster, still, skeleton or
/// placeholder.
abstract final class AnalogRadius {
  static const double chromePx = 4.0;
  static const double sheetPx = 8.0;
  static const double pillPx = 999.0;
}

abstract final class AnalogType {
  static const String sans = "'Circular XX', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif";
  static const String mono = "'JetBrains Mono', ui-monospace, monospace";
  static const String sansFamily = "CircularXX";
  static const String monoFamily = "JetBrains Mono";
}

/// Stage layering. The player owns its own bands; these are the browse shell.
abstract final class AnalogZ {
  static const int backdrop = 0;
  static const int grain = 5;
  static const int shelf = 10;
  static const int nav = 20;
  static const int toolbox = 30;
  static const int scrim = 40;
  static const int sheet = 50;
  static const int toast = 60;
}

abstract final class AnalogBreakpoint {
  static const double phoneMaxPx = 719.0;
  static const double tabletMaxPx = 1023.0;
}
