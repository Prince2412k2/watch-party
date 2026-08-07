// Responsive and reduced-motion branches for the analog stage, derived from the
// generated tokens rather than hand-picked numbers.
//
// Phones keep the same stage and focus model as desktop — full-screen backdrop,
// one tactile shelf owning focus, bottom modes — so this returns *sizes*, never
// a different layout. The only thing that changes across the breakpoints is how
// much of the shelf is visible at once.
//
// The Dart half of app/client/src/analog/stageLayout.ts, held to it by
// stage_layout_parity_test.dart.

import 'dart:math' as math;

import '../ui/analog_tokens.dart';

enum StageSize { phone, tablet, desktop }

class StageLayout {
  const StageLayout({
    required this.size,
    required this.gutterPx,
    required this.posterWidthPx,
    required this.gapPx,
    required this.visibleCount,
  });

  final StageSize size;

  /// Inset from the viewport edge to the stage content.
  final double gutterPx;
  final double posterWidthPx;
  final double gapPx;

  /// Whole posters that fit across the shelf at this width.
  final int visibleCount;

  @override
  String toString() =>
      'StageLayout(${size.name}, gutter $gutterPx, poster $posterWidthPx, '
      'gap $gapPx, visible $visibleCount)';
}

/// Posters we aim to show across the shelf, per size.
const Map<StageSize, int> _targetAcross = {
  StageSize.phone: 3,
  StageSize.tablet: 5,
  StageSize.desktop: 7,
};

/// Below this a poster stops being readable artwork and becomes an icon; above
/// it the shelf reads as a wall of few enormous tiles rather than a collection.
const double _minPosterPx = 104;
const double _maxPosterPx = 232;

/// Share of the stage height the shelf may take, artwork plus caption.
const double _shelfHeightShare = 0.46;

/// [coarsePointer] is "phone-class device in ANY orientation" — a coarse
/// pointer AND (narrow OR short). That is the right signal and a plain width
/// breakpoint is not: a narrow *desktop* window is still a desktop (mouse,
/// hover, keyboard) and giving it the phone's three-across shelf would make it
/// worse, not smaller.
///
/// Height matters as much as width because the stage is the whole viewport. A
/// phone held sideways is 844px wide and 390px tall — wide enough for big
/// posters that would not come close to fitting.
StageLayout stageLayout(
  double viewportWidthPx,
  double viewportHeightPx,
  bool coarsePointer,
) {
  final size = coarsePointer
      ? StageSize.phone
      : viewportWidthPx <= AnalogBreakpoint.tabletMaxPx
      ? StageSize.tablet
      : StageSize.desktop;

  final gutterPx = size == StageSize.phone
      ? AnalogSpace.stageGutterPhonePx
      : AnalogSpace.stageGutterPx;
  const gapPx = AnalogPoster.gapPx;
  final across = _targetAcross[size]!;
  final usable = math.max(_minPosterPx, viewportWidthPx - gutterPx * 2);

  final byWidth = ((usable - gapPx * (across - 1)) / across).floorToDouble();
  final byHeight =
      (viewportHeightPx *
              _shelfHeightShare *
              AnalogPoster.aspectW /
              AnalogPoster.aspectH)
          .floorToDouble();

  final posterWidthPx = math
      .min(byWidth, byHeight)
      .clamp(_minPosterPx, _maxPosterPx)
      .toDouble();
  final visibleCount = math.max(
    1,
    ((usable + gapPx) / (posterWidthPx + gapPx)).floor(),
  );

  return StageLayout(
    size: size,
    gutterPx: gutterPx,
    posterWidthPx: posterWidthPx,
    gapPx: gapPx,
    visibleCount: visibleCount,
  );
}

// ── reduced motion ──────────────────────────────────────────────────────────

class MotionProfile {
  const MotionProfile({
    required this.focusStep,
    required this.backdropCross,
    required this.chromeFade,
    required this.drawer,
    required this.focusScale,
    required this.focusLiftPx,
    required this.framePx,
    required this.animate,
  });

  final Duration focusStep;
  final Duration backdropCross;
  final Duration chromeFade;
  final Duration drawer;
  final double focusScale;
  final double focusLiftPx;

  /// Frame around the artwork. **Thicker when motion is off** — see below.
  final double framePx;

  /// Whether travel is animated at all. The web's `scrollBehavior`.
  final bool animate;
}

/// "Reduced-motion mode must preserve all state changes without spatial
/// effects." So every duration collapses, the forward lift and the focus scale
/// go away, and the backdrop still changes — it just cuts instead of crossing.
///
/// That removes two of the four things focus is built from, and "selection must
/// not rely on colour alone" rules out replacing them with a tint. The frame
/// around the focused poster therefore **thickens** instead: a size change, not
/// a spatial one, and it survives on a monochrome display.
MotionProfile motionProfile(bool reducedMotion) {
  if (reducedMotion) {
    return const MotionProfile(
      focusStep: Duration.zero,
      backdropCross: Duration.zero,
      chromeFade: Duration.zero,
      drawer: Duration.zero,
      focusScale: AnalogSelection.restScale,
      focusLiftPx: 0,
      framePx: AnalogPoster.framePx * 3,
      animate: false,
    );
  }
  return const MotionProfile(
    focusStep: AnalogMotion.focusStepMs,
    backdropCross: AnalogMotion.backdropCrossMs,
    chromeFade: AnalogMotion.chromeFadeMs,
    drawer: AnalogMotion.drawerMs,
    focusScale: AnalogSelection.focusScale,
    focusLiftPx: AnalogSelection.focusLiftPx,
    framePx: AnalogPoster.framePx,
    animate: true,
  );
}

// ── scene light ─────────────────────────────────────────────────────────────

class EdgeLightOffsets {
  const EdgeLightOffsets({
    required this.litX,
    required this.litY,
    required this.shadeX,
    required this.shadeY,
  });

  /// Inset offsets for the lit edge, in px.
  final double litX;
  final double litY;

  /// Inset offsets for the shaded edge, in px.
  final double shadeX;
  final double shadeY;
}

/// [AnalogSelection.sceneLightAngleDeg] (315 = above-left) → the inset offsets
/// that put the highlight on the edges facing the light and the shade on the
/// ones facing away.
///
/// The angle convention is the web's, kept deliberately so both clients read
/// one number out of one token: 0deg points up, increasing clockwise. The unit
/// vector *towards* the light is therefore (sin a, -cos a); an inset shadow
/// offset by the negative of that lands on the lit edge.
EdgeLightOffsets edgeLightOffsets(double angleDeg, double weightPx) {
  final radians = angleDeg * math.pi / 180;
  final towardsX = math.sin(radians);
  final towardsY = -math.cos(radians);
  double round(double value) => (value * weightPx * 100).roundToDouble() / 100;
  return EdgeLightOffsets(
    litX: round(-towardsX),
    litY: round(-towardsY),
    shadeX: round(towardsX),
    shadeY: round(towardsY),
  );
}
