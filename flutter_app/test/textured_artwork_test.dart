import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/ui/widgets/textured_artwork.dart';

/// Blend modes only compose correctly against a real canvas, so this is a
/// golden rather than a tree assertion: there is no widget-level fact that
/// distinguishes "soft-light applied" from "soft-light silently skipped
/// because nothing shared a layer", which is the exact bug this guards.
void main() {
  // Sheets are cached process-wide as Futures, and a Future from a previous
  // test's zone never completes in this one. Without this every test after the
  // first would render plain artwork and assert nothing.
  setUp(TexturedArtwork.debugClearSheetCache);

  /// The sheet decodes off the test's fake async, so it needs real time to
  /// land — and more than one turn of it: the first decode in a file is not
  /// finished after a single round, which quietly leaves the plain artwork on
  /// screen and makes any assertion about the treatment vacuous.
  Future<void> settleSheet(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<void> pumpSheet(WidgetTester tester, Widget child, Size size) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ColoredBox(
          color: const Color(0xFF12100E),
          child: Center(
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: child,
            ),
          ),
        ),
      ),
    );
    await settleSheet(tester);
  }

  testWidgets('poster stock prints artwork with worn edges', (tester) async {
    await pumpSheet(
      tester,
      const TexturedArtwork(
        texture: 'assets/textures/poster.png',
        child: ColoredBox(color: Color(0xFF1663EB)),
      ),
      const Size(400, 600),
    );
    await expectLater(
      find.byType(TexturedArtwork),
      matchesGoldenFile('goldens/textured_poster.png'),
    );
  });

  testWidgets('the stock takes a hue push from the artwork', (tester) async {
    await pumpSheet(
      tester,
      TexturedArtwork(
        texture: 'assets/textures/poster.png',
        paper: TexturedArtwork.paperFor(const Color(0xFF1663EB)),
        child: const ColoredBox(color: Color(0xFF1663EB)),
      ),
      const Size(400, 600),
    );
    await expectLater(
      find.byType(TexturedArtwork),
      matchesGoldenFile('goldens/textured_poster_hued.png'),
    );
  });

  testWidgets('disabled returns the artwork untouched', (tester) async {
    await pumpSheet(
      tester,
      const TexturedArtwork(
        texture: 'assets/textures/poster.png',
        enabled: false,
        child: ColoredBox(color: Color(0xFF1663EB)),
      ),
      const Size(400, 600),
    );
    // Nothing wrapping, nothing blending — the caller's own child, as given.
    expect(
      find.descendant(
        of: find.byType(TexturedArtwork),
        matching: find.byType(ColoredBox),
      ),
      findsOneWidget,
    );
  });

  testWidgets('survives an unbounded parent', (tester) async {
    // A poster tile puts its artwork in a Column, which hands down unbounded
    // height. StackFit.expand turned that into "BoxConstraints forces an
    // infinite height" and took the whole rail down with it. The sheet has to
    // pass its constraints through and let the artwork decide the size.
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            SizedBox(
              width: 229.1,
              child: TexturedArtwork(
                texture: 'assets/textures/poster.png',
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
    await settleSheet(tester);

    expect(tester.takeException(), isNull);
    // Proves the stock actually rendered. Without this the test passes when
    // the sheet fails to decode and TexturedArtwork quietly returns its child,
    // which is exactly how it passed against the infinite-height bug.
    expect(find.byType(ShaderMask), findsWidgets);
    expect(tester.getSize(find.byType(TexturedArtwork)).height, 343);
  });

  testWidgets('fills a tight parent, as the backdrop needs', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        // Centred, because pumpWidget hands the root tight view constraints
        // and a bare SizedBox cannot shrink inside them.
        child: Center(
          child: SizedBox(
            width: 800,
            height: 450,
            child: TexturedArtwork(
              texture: 'assets/textures/backdrop.png',
              child: const ColoredBox(color: Color(0xFF1663EB)),
            ),
          ),
        ),
      ),
    );
    await settleSheet(tester);

    expect(tester.takeException(), isNull);
    expect(find.byType(ShaderMask), findsWidgets);
    expect(tester.getSize(find.byType(TexturedArtwork)), const Size(800, 450));
  });

  test('the hue push keeps paper as paper', () {
    final pushed = TexturedArtwork.paperFor(const Color(0xFF1663EB));
    final base = HSLColor.fromColor(TexturedArtwork.kWarmPaper);
    final got = HSLColor.fromColor(pushed);
    // Hue moves; saturation and lightness must not. Mixing in RGB bleached the
    // stock instead of tinting it, which is what this pins down.
    expect(got.hue, isNot(closeTo(base.hue, 0.5)));
    expect(got.saturation, closeTo(base.saturation, 0.01));
    expect(got.lightness, closeTo(base.lightness, 0.01));
    expect(pushed, isNot(TexturedArtwork.kWarmPaper));
  });

  test('a near-neutral poster leaves the stock alone', () {
    // Greyscale artwork carries no hue to borrow; asking for one would tint the
    // paper from decoder rounding noise.
    expect(
      TexturedArtwork.paperFor(const Color(0xFF6E6E70)),
      TexturedArtwork.kWarmPaper,
    );
  });

  test('artwork with no usable colour falls back to warm stock', () {
    expect(TexturedArtwork.paperFor(null), TexturedArtwork.kWarmPaper);
  });
}
