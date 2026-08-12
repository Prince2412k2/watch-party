import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:watchparty/state/appearance_provider.dart';
import 'package:watchparty/ui/widgets/textured_artwork.dart';

/// The setting has to actually reach the artwork. It travels by inherited
/// scope rather than by parameter, because the widgets that draw artwork live
/// in `analog/`, which holds no providers — so nothing about the wiring is
/// visible at the call site, and only a test that renders both ends proves the
/// switch is connected to anything.
void main() {
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Widget harness({required bool enabled}) => Directionality(
    textDirection: TextDirection.ltr,
    child: ArtworkTextureScope(
      enabled: enabled,
      child: const Center(
        child: SizedBox(
          width: 200,
          height: 300,
          child: TexturedArtwork(
            seed: 'a-title',
            child: ColoredBox(color: Color(0xFF1663EB)),
          ),
        ),
      ),
    ),
  );

  testWidgets('the scope switches the sheet off', (tester) async {
    await tester.pumpWidget(harness(enabled: true));
    await settle(tester);
    expect(find.byType(Image), findsOneWidget);

    await tester.pumpWidget(harness(enabled: false));
    await settle(tester);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('artwork keeps its texture with no scope installed', (
    tester,
  ) async {
    // The default belongs with the treatment, not with whoever remembered to
    // wrap the tree.
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 200,
            height: 300,
            child: TexturedArtwork(
              seed: 'a-title',
              child: ColoredBox(color: Color(0xFF1663EB)),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('an explicit flag still overrides the scope', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: ArtworkTextureScope(
          enabled: false,
          child: Center(
            child: SizedBox(
              width: 200,
              height: 300,
              child: TexturedArtwork(
                seed: 'a-title',
                enabled: true,
                child: ColoredBox(color: Color(0xFF1663EB)),
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    expect(find.byType(Image), findsOneWidget);
  });

  group('the preference', () {
    test('defaults on, and survives a restart once turned off', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(artworkTextureProvider), isTrue);
      await container.read(artworkTextureProvider.notifier).set(false);
      expect(container.read(artworkTextureProvider), isFalse);

      // A taste decision, not a session one: turning the paper off must not
      // have to be done again on every launch.
      final restarted = ProviderContainer();
      addTearDown(restarted.dispose);
      expect(restarted.read(artworkTextureProvider), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(restarted.read(artworkTextureProvider), isFalse);
    });

    test('reads a stored true without complaint', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        kArtworkTexturePrefKey: true,
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(artworkTextureProvider), isTrue);
    });
  });
}
