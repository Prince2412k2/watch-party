// Type has weight.
//
// A 52px heading and a 10px label arriving on the same clock read as stickers
// stuck to one card. Giving the heading longer travel and a later settle makes
// the block arrive as a set of objects with different mass — which is the
// twelve principles' *timing* doing its actual job, rather than one duration
// applied to everything.
//
// Scaled by font size because on this stage size is the hierarchy: the title is
// the heaviest thing on screen and the mono breadcrumb the lightest, and that
// is already how they are set.
//
// Pure, so the rule can be asserted without pumping a frame, and so the web can
// read the same law out of the same tokens.

import 'dart:math' as math;

import 'package:flutter/animation.dart';

import '../ui/analog_tokens.dart';

/// How heavy text at [fontSizePx] is, 0..1.
///
/// [AnalogMotion.typeMassRefPx] is the pivot: body text sits at 0 and moves at
/// exactly the base timing. Anything larger gains mass up to
/// [AnalogMotion.typeMassMaxPx]; anything smaller loses it. Clamped at both
/// ends so a stray 200px display style cannot produce a settle that outlasts
/// the gesture that caused it.
double typeMass(double fontSizePx) {
  const ref = AnalogMotion.typeMassRefPx;
  const max = AnalogMotion.typeMassMaxPx;
  if (fontSizePx <= ref) {
    // Below the reference, mass falls away but never reaches zero: even a
    // caption has some.
    return -(1 - (fontSizePx / ref)).clamp(0.0, 1.0);
  }
  return ((fontSizePx - ref) / (max - ref)).clamp(0.0, 1.0);
}

/// The fraction of the shared entry animation this text should take.
///
/// Heavier text finishes later, so the block settles from the top down rather
/// than all at once. Returned as a [Curve] interval rather than a duration
/// because every line rides one controller — separate controllers would drift
/// apart and there would be nothing keeping the block a block.
Interval typeSettleInterval(double fontSizePx) {
  final mass = typeMass(fontSizePx);
  const minEnd = AnalogMotion.typeMassSettleMinPct / 100;
  // Light text lands early; the heaviest uses the whole clock.
  final end = mass >= 0
      ? minEnd + (1 - minEnd) * mass
      : minEnd * (1 + mass).clamp(0.0, 1.0);
  return Interval(0, end.clamp(0.15, 1.0));
}

/// Multiplier on the block's travel distance for text at [fontSizePx].
///
/// Momentum: the heading carries further than the label riding with it, so the
/// two do not arrive locked together.
double typeTravelFactor(double fontSizePx) {
  final mass = typeMass(fontSizePx);
  const lo = AnalogMotion.typeMassTravelMinPct / 100;
  const hi = AnalogMotion.typeMassTravelMaxPct / 100;
  return mass >= 0
      ? 1 + (hi - 1) * mass
      : math.max(lo, 1 + (1 - lo) * mass);
}
