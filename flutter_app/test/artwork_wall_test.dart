import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/ui/widgets/artwork_wall.dart';

/// Explicit strengths throughout, not the shipped constants.
///
/// Those are all zero now: the app paints the paste with a fragment shader and
/// the soft-light path is no longer used on any real surface. Reading them here
/// would render flat grey and assert nothing, while still passing. The
/// mechanism is kept — the playground compares against it, and it is the
/// fallback if the shader is ever unavailable — so it is still worth a golden.
const _wallStrength = 0.9;
const _pasteStrength = 0.3;

void main() {
  setUp(WallImages.debugClear);

  /// Asset decoding runs on real async, and one turn is not enough for the
  /// first image in a file. Without this the wall never arrives, every surface
  /// renders plain, and any assertion about the relief is vacuous.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('the courses run straight through pasted artwork', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 520);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: WallLayer(
          index: 3,
          withTint: true,
          strength: _wallStrength,
          builder: (context, depth, tint) => Stack(
            fit: StackFit.expand,
            children: [
              // The wall itself.
              WallRelief(
                depth: depth,
                strength: _wallStrength,
                child: const ColoredBox(color: Color(0xFF2A211C)),
              ),
              if (tint != null)
                Opacity(
                  opacity: ArtworkWall.kTintOpacity,
                  child: RawImage(image: tint, fit: BoxFit.cover),
                ),
              // Two sheets pasted on it, at different places. If the relief
              // were sampled per widget, both would show the same brick
              // starting in their own top-left corner — two little walls
              // instead of one wall behind two posters. The golden is the only
              // thing that can tell those apart.
              for (final left in const [60.0, 520.0])
                Positioned(
                  left: left,
                  top: 90,
                  width: 220,
                  height: 330,
                  child: WallLayer(
                    index: 3,
                    strength: _pasteStrength,
                    builder: (context, paste, _) => WallRelief(
                      depth: paste,
                      strength: _pasteStrength,
                      child: const ColoredBox(color: Color(0xFF9C8F7A)),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    await settle(tester);

    await expectLater(
      // The outermost of the three, now that each pasted sheet loads its own
      // eased map.
      find.byType(WallLayer).first,
      matchesGoldenFile('goldens/artwork_wall.png'),
    );
  });

  testWidgets('artwork paints plainly while the wall is still decoding', (
    tester,
  ) async {
    // A hole where a poster should be, on every cold start, is worse than a
    // poster that gains its texture a frame late.
    await tester.pumpWidget(
      const MaterialApp(
        home: WallRelief(
          depth: null,
          strength: 1,
          child: ColoredBox(color: Color(0xFF1663EB)),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    // Scoped: MaterialApp paints a ColoredBox of its own.
    expect(
      find.descendant(
        of: find.byType(WallRelief),
        matching: find.byType(ColoredBox),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a zero-strength relief is a no-op, not a crash', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WallLayer(
          index: 0,
          strength: 1,
          builder: (context, depth, _) => WallRelief(
            depth: depth,
            strength: 0,
            child: const ColoredBox(color: Color(0xFF1663EB)),
          ),
        ),
      ),
    );
    await settle(tester);
    expect(tester.takeException(), isNull);
  });

  group('wall choice', () {
    test('is stable for a room', () {
      expect(ArtworkWall.indexFor('movies'), ArtworkWall.indexFor('movies'));
    });

    test('spreads rooms across every wall', () {
      final used = <int>{};
      for (var i = 0; i < 300; i++) {
        used.add(ArtworkWall.indexFor('room-$i'));
      }
      expect(used.length, ArtworkWall.count);
    });

    test('an absent seed still names a real wall', () {
      expect(ArtworkWall.indexFor(null), 0);
      expect(ArtworkWall.indexFor(''), 0);
      expect(ArtworkWall.depth(0), contains('depth-00'));
      // The index wraps rather than running off the end of the set.
      expect(ArtworkWall.depth(ArtworkWall.count), ArtworkWall.depth(0));
    });
  });

  group('every wall in the set is present and loadable', () {
    testWidgets('all ten decode', (tester) async {
      await tester.runAsync(() async {
        for (var i = 0; i < ArtworkWall.count; i++) {
          final depth = await WallImages.load(ArtworkWall.depth(i));
          final tint = await WallImages.load(ArtworkWall.tint(i));
          expect(depth, isA<ui.Image>());
          expect(tint, isA<ui.Image>());
        }
      });
    });
  });
}
