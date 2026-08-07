// The fixed-cursor rail.
//
// "Currently movie cursor moves around. Now we will have our cursor at the first
// position and the whole row will move. Like old video game consoles."
//
// The window geometry itself is `railWindow`/`clampRailOffset` in
// browse_core.dart — shared with the web and driven by
// app/shared/design/interaction.json. Nothing here re-derives it. This file is
// the surface-shaped layer around it: where the cursor actually sits once the
// row has run out of travel, how far the track has to translate to put the
// window's first index under it, how big the posters are now that they are a
// rail along the bottom rather than the main event, and which artwork to warm
// before it arrives.
//
// Pure on purpose. The rail's arithmetic is exactly the part worth pinning, and
// pinning it in a widget test would mean pumping a stage to assert a number.
//
// The Dart half of app/client/src/analog/movieRail.ts.

import 'dart:math' as math;

import '../ui/analog_tokens.dart';
import 'browse_core.dart';
import 'stage_layout.dart';

// ── cursor + window ─────────────────────────────────────────────────────────

class RailCursor {
  const RailCursor({
    required this.start,
    required this.cursorSlot,
    required this.visible,
    required this.prefetch,
  });

  /// Index sitting in the leftmost slot. What the track translates to.
  final int start;

  /// Which slot the cursor occupies. **Always zero.**
  ///
  /// Kept as a field rather than dropped so the widget reads its position from
  /// the model instead of hard-coding a 0, and so a regression that moves the
  /// cursor shows up here rather than as a layout mystery.
  final int cursorSlot;

  final List<int> visible;

  /// Indices to warm but not render. Never overlaps [visible].
  final List<int> prefetch;

  @override
  String toString() =>
      'RailCursor(start $start, slot $cursorSlot, visible $visible, '
      'prefetch $prefetch)';
}

/// "Selected movie/show should always be first, so when I scroll, the whole
/// thing scrolls to put the movie on the first spot."
///
/// So [RailCursor.start] IS the selection, unconditionally, and
/// [RailCursor.cursorSlot] is always 0 — including at the tail of the rail,
/// where the row keeps travelling and simply runs out of items to the right.
/// Trailing space is the price of a selection that never moves.
///
/// "Which item is selected" and "how far the row has scrolled" are therefore
/// literally the same number, which is what makes the visible set — and so the
/// prefetch set — trivially derivable.
RailCursor railCursor({
  required int total,
  required int selection,
  required int slots,
  int? lookahead,
  int? behind,
}) {
  if (total <= 0 || slots <= 0) {
    return const RailCursor(start: 0, cursorSlot: 0, visible: [], prefetch: []);
  }

  final start = clampPinnedOffset(selection, total);
  final window = railWindow(
    RailWindowInput(
      total: total,
      offset: start,
      slots: slots,
      lookahead: lookahead ?? kRailLookahead,
      behind: behind ?? kRailBehind,
      pinned: true,
    ),
  );

  return RailCursor(
    start: start,
    cursorSlot: 0,
    visible: window.visible,
    prefetch: window.prefetch,
  );
}

/// One step of the cursor. Clamped rather than wrapping: there is one rail on
/// this surface, so an overflow has nowhere to go and a wrap would make the ends
/// of a long library indistinguishable from each other.
int stepRailSelection(int selection, int total, int direction) {
  if (total <= 0) return 0;
  return (selection + direction.sign).clamp(0, total - 1);
}

/// Centre-to-centre distance between two slots.
double railStepPx(double posterWidthPx, double gapPx) => posterWidthPx + gapPx;

/// How far the track is translated to put [start] under the cursor. Never
/// positive.
double railTranslatePx(int start, double posterWidthPx, double gapPx) {
  final travelled = start * railStepPx(posterWidthPx, gapPx);
  return travelled == 0 ? 0 : -travelled;
}

/// The contiguous index range that has to exist in the tree.
///
/// [RailCursor.visible] alone would mount an arriving poster at the instant the
/// track starts moving, which is a decode in the middle of the transition.
/// Mounting the warmed neighbours as well means the item under the cursor after
/// a step was already laid out and decoded a step ago.
List<int> railRendered(RailCursor cursor) {
  final indices = [...cursor.visible, ...cursor.prefetch];
  if (indices.isEmpty) return const [];
  final first = indices.reduce(math.min);
  final last = indices.reduce(math.max);
  return [for (var i = first; i <= last; i++) i];
}

// ── rail sizing ─────────────────────────────────────────────────────────────
//
// "We put the posters in movie selection bottom and make them smaller." The
// stage's main event is now the focused title's details, so the rail is a strip
// underneath them rather than the half-height shelf `stageLayout` sizes.

class RailMetrics {
  const RailMetrics({
    required this.posterWidthPx,
    required this.gapPx,
    required this.slots,
  });

  final double posterWidthPx;
  final double gapPx;

  /// Whole posters that fit across the rail at this width.
  final int slots;

  @override
  String toString() =>
      'RailMetrics(poster $posterWidthPx, gap $gapPx, slots $slots)';
}

/// Target poster width per device size — roughly two thirds of the shelf's, so
/// ten titles are on screen at once on a desktop where seven used to be.
const Map<StageSize, double> _railPosterPx = {
  StageSize.phone: 68,
  StageSize.tablet: 88,
  StageSize.desktop: 104,
};

/// Below this a poster is an icon rather than artwork you can recognise.
const double _minRailPosterPx = 64;

RailMetrics railMetrics(double usableWidthPx, StageSize size) {
  const gapPx = AnalogPoster.gapPx;
  final target = _railPosterPx[size]!;
  final usable = math.max(_minRailPosterPx, usableWidthPx);

  // Fit whole posters across the usable width, then spend the remainder
  // widening them back out — so the rail always ends on a poster edge instead
  // of a sliver of the next one, at any viewport width.
  final slots = math.max(1, ((usable + gapPx) / (target + gapPx)).floor());
  final posterWidthPx = math.max(
    _minRailPosterPx,
    ((usable - gapPx * (slots - 1)) / slots).floorToDouble(),
  );

  return RailMetrics(posterWidthPx: posterWidthPx, gapPx: gapPx, slots: slots);
}
