import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/livekit/livekit_room.dart';
import 'package:watchparty/ui/widgets/floating_camera_tile.dart';

void main() {
  group('FloatingTileGeometry', () {
    const stage = Size(800, 450);

    test('tile keeps 4:3 aspect (plus header) when expanded', () {
      final size = FloatingTileGeometry.tileSize(160, collapsed: false);
      expect(size.width, 160);
      // height = header + width / (4/3)
      expect(size.height, FloatingTileGeometry.headerHeight + 120);
    });

    test('collapsed tile is a round ball, whatever width it was', () {
      final size = FloatingTileGeometry.tileSize(160, collapsed: true);
      expect(size.width, FloatingTileGeometry.ballDiameter);
      expect(size.height, FloatingTileGeometry.ballDiameter);
      // The expanded width is remembered, not applied — a ball is the same size
      // whether it was collapsed from a small tile or a large one.
      expect(FloatingTileGeometry.tileSize(400, collapsed: true), size);
    });

    test('width clamps to the minimum, and to the stage rather than a cap', () {
      expect(
        FloatingTileGeometry.clampWidth(10, stage),
        FloatingTileGeometry.minWidth,
      );

      // There is no fixed maximum any more — a hard cap made the resize handle
      // stop responding partway through a drag. The tile grows until it runs
      // out of window, on whichever axis runs out first.
      final huge = FloatingTileGeometry.clampWidth(9999, stage);
      final tile = FloatingTileGeometry.tileSize(huge, collapsed: false);
      expect(tile.width, lessThanOrEqualTo(stage.width));
      expect(tile.height, lessThanOrEqualTo(stage.height));
      expect(huge, greaterThan(FloatingTileGeometry.defaultWidth));
    });

    test('offset is clamped within stage bounds', () {
      final tile = FloatingTileGeometry.tileSize(160, collapsed: false);
      // Dragged far off the bottom-right corner.
      final clamped = FloatingTileGeometry.clamp(
        const Offset(5000, 5000),
        tile,
        stage,
      );
      expect(clamped.dx, stage.width - tile.width);
      expect(clamped.dy, stage.height - tile.height);
      // Dragged off the top-left.
      final clamped2 = FloatingTileGeometry.clamp(
        const Offset(-500, -500),
        tile,
        stage,
      );
      expect(clamped2, Offset.zero);
    });

    test('shrinking the stage re-clamps a previously valid offset', () {
      final tile = FloatingTileGeometry.tileSize(160, collapsed: false);
      const offset = Offset(700, 380); // valid in 800x450
      final small = FloatingTileGeometry.clamp(
        offset,
        tile,
        const Size(300, 200),
      );
      expect(small.dx, 300 - tile.width);
      expect(small.dy, 200 - tile.height);
    });

    test('cascade anchors tiles at the bottom-right, stacked upward', () {
      final tile = FloatingTileGeometry.tileSize(
        FloatingTileGeometry.defaultWidth,
        collapsed: false,
      );
      final a0 = FloatingTileGeometry.cascadeAnchor(0, tile, stage);
      final a1 = FloatingTileGeometry.cascadeAnchor(1, tile, stage);
      expect(a0.dx, a1.dx); // same right-aligned column
      expect(a1.dy, lessThan(a0.dy)); // later tiles stack higher up
      // Both stay inside the stage.
      expect(a0.dx + tile.width, lessThanOrEqualTo(stage.width));
      expect(a0.dy + tile.height, lessThanOrEqualTo(stage.height));
    });

    test('movie tiles settle at the nearest corner', () {
      const tile = Size(200, 120);

      expect(
        FloatingTileGeometry.snapToNearestCorner(
          const Offset(500, 300),
          tile,
          stage,
        ),
        Offset(
          stage.width - tile.width - FloatingTileGeometry.margin,
          stage.height - tile.height - FloatingTileGeometry.margin,
        ),
      );
      expect(
        FloatingTileGeometry.snapToNearestCorner(
          const Offset(100, 50),
          tile,
          stage,
        ),
        const Offset(FloatingTileGeometry.margin, FloatingTileGeometry.margin),
      );
    });
  });

  group('FloatingCameraTile widget', () {
    const track = ParticipantTrack(
      identity: 'p1',
      name: 'Ada',
      isLocal: false,
      audioMuted: true,
    );

    testWidgets('dragging the header reports position deltas', (tester) async {
      var offset = const Offset(100, 100);
      const size = Size(160, 146);

      await tester.pumpWidget(
        _withProviders(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) => Stack(
                  children: [
                    Positioned(
                      left: offset.dx,
                      top: offset.dy,
                      width: size.width,
                      height: size.height,
                      child: FloatingCameraTile(
                        track: track,
                        collapsed: false,
                        onDrag: (d) => setState(() => offset += d),
                        onDragEnd: () {},
                        onResize: (_) {},
                        onToggleCollapse: () {},
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      final before = tester.getTopLeft(find.byType(FloatingCameraTile));
      // Drag on the header (top ~13px of the tile).
      await tester.drag(
        find.byIcon(Icons.drag_indicator),
        const Offset(40, 30),
      );
      await tester.pumpAndSettle();
      final after = tester.getTopLeft(find.byType(FloatingCameraTile));

      expect(after.dx, greaterThan(before.dx));
      expect(after.dy, greaterThan(before.dy));
    });

    testWidgets('dragging the resize handle reports resize deltas', (
      tester,
    ) async {
      var resized = Offset.zero;

      await tester.pumpWidget(
        _withProviders(
          MaterialApp(
            home: Scaffold(
              body: Stack(
                children: [
                  Positioned(
                    left: 0,
                    top: 0,
                    width: 160,
                    height: 146,
                    child: FloatingCameraTile(
                      track: track,
                      collapsed: false,
                      onDrag: (_) {},
                      onDragEnd: () {},
                      onResize: (d) => resized += d,
                      onToggleCollapse: () {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.drag(find.byIcon(Icons.south_east), const Offset(30, 30));
      await tester.pump();
      expect(resized.dx, greaterThan(0));
      expect(resized.dy, greaterThan(0));
    });

    testWidgets('a collapsed tile is the person, and clicking it expands', (
      tester,
    ) async {
      var expanded = 0;

      await tester.pumpWidget(
        _withProviders(
          MaterialApp(
            home: Scaffold(
              body: Stack(
                children: [
                  Positioned(
                    left: 0,
                    top: 0,
                    width: FloatingTileGeometry.ballDiameter,
                    height: FloatingTileGeometry.ballDiameter,
                    child: FloatingCameraTile(
                      track: track,
                      collapsed: true,
                      onDrag: (_) {},
                      onDragEnd: () {},
                      onResize: (_) {},
                      onToggleCollapse: () => expanded++,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // No avatar drawing to fetch in a test, so it falls back to initials —
      // which is still the person rather than the old strip of chrome.
      expect(find.text('A'), findsOneWidget);
      expect(find.byIcon(Icons.drag_indicator), findsNothing);
      expect(find.byIcon(Icons.south_east), findsNothing);
      // Muted, and you can see that without expanding them.
      expect(find.byIcon(Icons.mic_off), findsOneWidget);

      // Anywhere on the ball, not a toggle in a corner of it.
      await tester.tap(find.byType(FloatingCameraTile));
      await tester.pump();
      expect(expanded, 1);
    });
  });
}

Widget _withProviders(Widget child) => ProviderScope(child: child);
