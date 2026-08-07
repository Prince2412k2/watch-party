// The Dart half of app/client/src/analog/movieRail.test.ts.
//
// The geometry cases mirror the web's exactly. If these two suites stop
// agreeing, the two clients are showing different items for the same selection
// — which is the specific failure the fixed-cursor model exists to make
// impossible to reason about wrongly.
//
// The prefetch cases are deliberately NOT ported here: artwork URL building is
// a different subsystem in Dart (the artwork cache and its proxy), and faking
// the web's `artworkSrc` to assert a URL string would test the fake. That gap
// is real and named rather than papered over.

import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/analog/browse_core.dart';
import 'package:watchparty/analog/movie_rail.dart';
import 'package:watchparty/analog/stage_layout.dart';

void main() {
  test('the cursor stays in the first slot and the row moves underneath it', () {
    for (var selection = 0; selection <= 14; selection++) {
      final cursor = railCursor(total: 20, selection: selection, slots: 6);
      expect(
        cursor.cursorSlot,
        0,
        reason: 'selection $selection moved the cursor instead of the row',
      );
      expect(cursor.start, selection);
      expect(
        cursor.visible.first,
        selection,
        reason: 'the selected item must be the one under the cursor',
      );
      expect(cursor.visible.length, 6);
    }
  });

  test('the cursor stays first even at the tail, and the row runs out instead', () {
    // "Selected movie/show should always be first." So at the end of a library
    // the row keeps travelling and simply has nothing left to its right,
    // rather than stopping at the last full page and letting the cursor walk
    // forward into it.
    final tail = [
      for (final selection in [15, 16, 17, 18, 19])
        railCursor(total: 20, selection: selection, slots: 6),
    ];

    expect([for (final c in tail) c.start], [15, 16, 17, 18, 19]);
    expect([for (final c in tail) c.cursorSlot], [0, 0, 0, 0, 0]);
    for (final (offset, cursor) in tail.indexed) {
      expect(
        cursor.visible.first,
        15 + offset,
        reason: 'the selection must be the first slot',
      );
    }
    // The last selection shows only itself; the remaining slots are empty.
    expect(tail.last.visible, [19]);
  });

  test('a rail shorter than the row still puts the selection first', () {
    final cursor = railCursor(total: 3, selection: 2, slots: 6);
    expect(cursor.start, 2);
    expect(cursor.cursorSlot, 0);
    expect(cursor.visible, [2]);
    expect(cursor.prefetch, [0, 1]);
  });

  test('an out-of-range selection is clamped rather than emptying the window', () {
    final over = railCursor(total: 5, selection: 99, slots: 3);
    expect(over.start, 4);
    expect(over.cursorSlot, 0);
    expect(over.visible, [4]);
    expect(over.prefetch, [2, 3]);

    expect(railCursor(total: 5, selection: -4, slots: 3).visible, [0, 1, 2]);

    final empty = railCursor(total: 0, selection: 0, slots: 6);
    expect(empty.start, 0);
    expect(empty.cursorSlot, 0);
    expect(empty.visible, isEmpty);
    expect(empty.prefetch, isEmpty);
  });

  test('the cursor derives its window from the shared core, not a second copy', () {
    // If this stops agreeing, the rail has grown its own geometry and the two
    // clients are no longer showing the same items.
    for (final selection in [0, 1, 7, 13, 14, 19]) {
      final cursor = railCursor(total: 20, selection: selection, slots: 6);
      final shared = railWindow(
        RailWindowInput(total: 20, offset: selection, slots: 6, pinned: true),
      );
      expect(cursor.visible, shared.visible);
      expect(cursor.prefetch, shared.prefetch);
    }
  });

  test('stepping is clamped at both ends', () {
    expect(stepRailSelection(0, 20, -1), 0);
    expect(stepRailSelection(0, 20, 1), 1);
    expect(stepRailSelection(19, 20, 1), 19);
    expect(stepRailSelection(19, 20, -1), 18);
    // One item per step whatever the caller passes, so a burst of wheel deltas
    // cannot be laundered into a jump.
    expect(stepRailSelection(5, 20, 6), 6);
    expect(stepRailSelection(5, 20, -6), 4);
    expect(stepRailSelection(3, 0, 1), 0);
  });

  test('the track translates by whole slots', () {
    expect(railStepPx(118, 14), 132);
    expect(railTranslatePx(0, 118, 14), 0);
    expect(railTranslatePx(5, 118, 14), -660);
    // Never positive: a positive translate would drag the row away from the
    // cursor and leave the first slot empty.
    expect(railTranslatePx(14, 118, 14), lessThan(0));
  });

  test('the rendered range is contiguous and covers the warmed neighbours', () {
    final cursor = railCursor(total: 40, selection: 10, slots: 6);
    final rendered = railRendered(cursor);

    expect(rendered, [8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21]);
    for (final index in [...cursor.visible, ...cursor.prefetch]) {
      expect(
        rendered,
        contains(index),
        reason: '$index was warmed but never mounted',
      );
    }
    // Bounded: a 40-title library must not put 40 posters in the tree.
    expect(rendered.length, lessThan(20));
    expect(
      railRendered(
        const RailCursor(
          start: 0,
          cursorSlot: 0,
          visible: [],
          prefetch: [],
        ),
      ),
      isEmpty,
    );
  });

  test('the rail is sized smaller than the shelf it replaces, and ends on a poster edge', () {
    const usable = 1200.0;
    final rail = railMetrics(usable, StageSize.desktop);
    final shelf = stageLayout(1280, 800, false);

    expect(
      rail.posterWidthPx,
      lessThan(shelf.posterWidthPx),
      reason: 'the rail is a strip under the details, not the main event',
    );
    expect(
      rail.slots,
      greaterThan(shelf.visibleCount),
      reason: 'smaller posters must put more titles on screen',
    );

    // Ends on a poster edge: the slots plus the gaps between them fill the
    // usable width, with no sliver of a next poster left over.
    final used = rail.posterWidthPx * rail.slots + rail.gapPx * (rail.slots - 1);
    expect(used, lessThanOrEqualTo(usable));
    expect(usable - used, lessThan(rail.posterWidthPx));

    // A viewport narrower than one poster still yields one usable slot.
    final tiny = railMetrics(10, StageSize.phone);
    expect(tiny.slots, 1);
    expect(tiny.posterWidthPx, greaterThanOrEqualTo(64));
  });

  test('reduced motion trades the spatial signals for a thicker frame', () {
    final normal = motionProfile(false);
    final reduced = motionProfile(true);

    expect(reduced.focusStep, Duration.zero);
    expect(reduced.focusLiftPx, 0);
    expect(reduced.animate, isFalse);
    // Two of the four focus signals are gone, and colour cannot replace them.
    expect(
      reduced.framePx,
      greaterThan(normal.framePx),
      reason: 'the frame must thicken to carry focus without motion or colour',
    );
  });

  test('the scene light lands above-left, and both clients read one angle', () {
    final offsets = edgeLightOffsets(315, 1);
    // 315deg = up and to the left, so the lit edge is offset right and down
    // from the top-left corner.
    expect(offsets.litX, greaterThan(0));
    expect(offsets.litY, greaterThan(0));
    expect(offsets.shadeX, -offsets.litX);
    expect(offsets.shadeY, -offsets.litY);
  });
}
