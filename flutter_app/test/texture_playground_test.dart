import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/playground/pasted_poster_shader.dart';
import 'package:watchparty/playground/texture_playground.dart';
import 'package:watchparty/ui/widgets/artwork_wall.dart';
import 'package:watchparty/ui/widgets/textured_artwork.dart';

void main() {
  setUp(WallImages.debugClear);

  group('the values it hands back', () {
    test('start at whatever the app currently ships', () {
      // The tool is useless as a comparison if it opens on something other
      // than the thing being compared against.
      const s = TextureSettings();
      expect(s.reliefStrength, ArtworkWall.kReliefStrength);
      expect(s.backdropStrength, ArtworkWall.kBackdropPasteStrength);
      expect(s.posterStrength, ArtworkWall.kPasteStrength);
      expect(s.tintOpacity, ArtworkWall.kTintOpacity);
    });

    test('name the constants they belong to', () {
      // Pasteable means the output has to say where each number goes; a bare
      // list of decimals is a screenshot with extra steps.
      final out = const TextureSettings(
        reliefStrength: 0.8,
        posterStrength: 0.25,
      ).asDart();
      expect(out, contains('kReliefStrength = 0.800'));
      expect(out, contains('kPasteStrength = 0.250'));
      expect(out, contains('artwork_wall.dart'));
      expect(out, contains('analog_stage.dart'));
    });

    test('the wash dial has a defined meaning at both ends', () {
      expect(
        const TextureSettings(washAmount: 1).wash,
        TexturedArtwork.defaultWash,
      );
      // At zero it must be the identity, or "no wash" would still tint.
      expect(
        const TextureSettings(washAmount: 0).wash,
        const ColorFilter.matrix(<double>[
          1, 0, 0, 0, 0, //
          0, 1, 0, 0, 0, //
          0, 0, 1, 0, 0, //
          0, 0, 0, 1, 0, //
        ]),
      );
    });

    test('the shader uniforms come out named', () {
      // The uniform block is positional — setFloat indexes a flat list — so a
      // bare column of decimals is unusable. The names have to travel with it.
      final out = const TextureSettings(
        shader: PasteShaderSettings(displacement: 0.02, bumpStrength: 12),
      ).asDart();
      expect(out, contains('displacement:    0.020'));
      expect(out, contains('bumpStrength:    12.000'));
      expect(out, contains('pasted_poster.frag'));
    });

    test('soft-light mode leaves the shader block out', () {
      final out = const TextureSettings(mode: PasteMode.softLight).asDart();
      expect(out, isNot(contains('pasted_poster.frag')));
      expect(out, contains('mode softLight'));
    });

    test('copyWith moves one knob and leaves the rest', () {
      const base = TextureSettings();
      final moved = base.copyWith(contrast: 2.5);
      expect(moved.contrast, 2.5);
      expect(moved.reliefStrength, base.reliefStrength);
      expect(moved.wall, base.wall);
    });
  });

  testWidgets('it builds, and each mode renders its own path', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    Future<void> settle() async {
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pump();
      }
    }

    await tester.pumpWidget(const MaterialApp(home: TexturePlayground()));
    await settle();
    expect(tester.takeException(), isNull);

    // Shader is the default. The wall itself still goes through WallRelief —
    // it is the surface, not something pasted to it, so there is nothing to
    // displace — but the pasted artwork goes through the shader instead, and
    // so TexturedArtwork is deliberately absent.
    expect(find.byType(WallRelief), findsWidgets);
    expect(find.byType(PastedPoster), findsWidgets);
    expect(find.byType(TexturedArtwork), findsNothing);

    await tester.drag(find.byType(Slider).first, const Offset(-60, 0));
    await tester.pump();
    expect(tester.takeException(), isNull);

    // Soft-light is the shipped path, kept for comparison.
    await tester.tap(find.text('Soft-light'));
    await settle();
    expect(tester.takeException(), isNull);
    expect(find.byType(TexturedArtwork), findsWidgets);
    expect(find.byType(PastedPoster), findsNothing);
  });
}
