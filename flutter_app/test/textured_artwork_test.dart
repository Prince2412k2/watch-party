import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/ui/widgets/textured_artwork.dart';

/// Blend modes only compose correctly against a real canvas, so this is a
/// golden rather than a tree assertion: there is no widget-level fact that
/// distinguishes "soft-light applied" from "soft-light silently skipped
/// because nothing shared a layer", which is the exact bug this guards.
void main() {
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
    // Image.asset decodes off the test's fake async, so let it actually run.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
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
