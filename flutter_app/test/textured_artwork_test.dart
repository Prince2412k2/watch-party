import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/ui/widgets/textured_artwork.dart';

void main() {
  /// Asset images decode off the test's fake async, so they need real time to
  /// land — and more than one turn of it. Without this the sheet never arrives
  /// and every assertion about the treatment is vacuous.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<void> pumpArt(WidgetTester tester, Widget child, Size size) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ColoredBox(
          color: const Color(0xFF12100E),
          child: Center(
            child: SizedBox(width: size.width, height: size.height, child: child),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets('the print takes a crumpled sheet', (tester) async {
    await pumpArt(
      tester,
      const TexturedArtwork(
        seed: 'castle-in-the-sky',
        child: ColoredBox(color: Color(0xFF1663EB)),
      ),
      const Size(400, 600),
    );
    await expectLater(
      find.byType(TexturedArtwork),
      matchesGoldenFile('goldens/textured_poster.png'),
    );
  });

  testWidgets('disabled returns the artwork untouched', (tester) async {
    await pumpArt(
      tester,
      const TexturedArtwork(
        enabled: false,
        child: ColoredBox(color: Color(0xFF1663EB)),
      ),
      const Size(400, 600),
    );
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('survives an unbounded parent', (tester) async {
    // A poster tile puts its artwork in a Column, which hands down unbounded
    // height. StackFit.expand turns that into "BoxConstraints forces an
    // infinite height" and takes the whole rail with it.
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            SizedBox(
              width: 229.1,
              child: TexturedArtwork(
                seed: 'x',
                child: SizedBox(
                  width: 229.1,
                  height: 343,
                  child: ColoredBox(color: Color(0xFF1663EB)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    await settle(tester);

    expect(tester.takeException(), isNull);
    // Proves the sheet actually rendered; without it this passes even when the
    // treatment silently does nothing.
    expect(find.byType(Image), findsOneWidget);
    expect(tester.getSize(find.byType(TexturedArtwork)).height, 343);
  });

  testWidgets('fills a tight parent, as the backdrop needs', (tester) async {
    await pumpArt(
      tester,
      const TexturedArtwork(
        seed: 'y',
        child: ColoredBox(color: Color(0xFF1663EB)),
      ),
      const Size(800, 450),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(Image), findsOneWidget);
    expect(tester.getSize(find.byType(TexturedArtwork)), const Size(800, 450));
  });

  group('sheet choice', () {
    test('is stable for a title', () {
      // A poster that re-creases whenever it scrolls back into view is worse
      // than no texture at all.
      expect(
        ArtworkTexture.sheetFor('the-darjeeling-limited', portrait: true),
        ArtworkTexture.sheetFor('the-darjeeling-limited', portrait: true),
      );
    });

    test('spreads titles across every sheet', () {
      // One sheet on twenty tiles reads as a filter, not as paper. This is the
      // property that buys the variety, so it is worth pinning.
      final used = <String>{};
      for (var i = 0; i < 300; i++) {
        used.add(ArtworkTexture.sheetFor('title-$i', portrait: true));
      }
      expect(used.length, ArtworkTexture.count);
    });

    test('paper is cut to the shape it prints on', () {
      // A tall sheet stretched across a backdrop drags its grain and edge wear
      // along one axis, which reads as a filter rather than as paper.
      expect(
        ArtworkTexture.sheetFor('x', portrait: true),
        contains('portrait-'),
      );
      expect(
        ArtworkTexture.sheetFor('x', portrait: false),
        contains('landscape-'),
      );
    });

    test('an absent id falls on one sheet rather than flickering', () {
      expect(
        ArtworkTexture.sheetFor(null, portrait: true),
        ArtworkTexture.sheetFor('', portrait: true),
      );
      expect(
        ArtworkTexture.sheetFor(null, portrait: true),
        contains('portrait-00'),
      );
    });
  });
}
