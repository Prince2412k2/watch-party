import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/data/mock_api_client.dart';
import 'package:watchparty/player/mock_player_controller.dart';
import 'package:watchparty/player/player_host.dart';
import 'package:watchparty/player/player_view.dart';
import 'package:watchparty/state/now_playing_provider.dart';
import 'package:watchparty/state/player_provider.dart';
import 'package:watchparty/state/providers.dart';
import 'package:watchparty/ui/ui.dart';

/// `fromParty: true` throughout: these tests are about PRESENTATION — where the
/// player is mounted and how it moves — not about opening media. A solo title
/// makes the host run the real open pipeline and show an indeterminate spinner
/// while it waits, which never settles and leaves a pending timer at teardown.
/// Party media is opened by PartyNotifier, so the host just renders it.
///
/// The host exists so there is exactly ONE PlayerView for the life of the
/// session, with expanded/floating being a rect it animates between rather than
/// two different mounts. The identity assertions below are the whole point: if
/// the element is rebuilt, the video texture is re-attached and the media
/// reloads — which is the bug this replaced.
void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(
      overrides: [
        playerControllerProvider.overrideWithValue(MockPlayerController()),
        apiClientProvider.overrideWithValue(MockApiClient()),
      ],
    );
  });
  tearDown(() => container.dispose());

  Future<void> pumpHost(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const Material(
            type: MaterialType.transparency,
            child: Stack(
              children: [
                Positioned.fill(child: Center(child: Text('library'))),
                Positioned.fill(child: PlayerHost()),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('nothing is mounted until a title is opened', (tester) async {
    await pumpHost(tester);
    expect(find.byType(PlayerView), findsNothing);
    expect(find.text('library'), findsOneWidget);
  });

  testWidgets('the app underneath stays mounted while a title plays', (
    tester,
  ) async {
    // The screen you were on is not replaced — that is the difference between a
    // player that floats over your app and a player that IS a route.
    await pumpHost(tester);
    container.read(nowPlayingProvider.notifier).open(itemId: 'movie-1', fromParty: true);
    await tester.pump();

    expect(find.byType(PlayerView), findsOneWidget);
    expect(find.text('library'), findsOneWidget);
  });

  testWidgets('minimise and expand reuse the SAME PlayerView element', (
    tester,
  ) async {
    await pumpHost(tester);
    final notifier = container.read(nowPlayingProvider.notifier);

    notifier.open(itemId: 'movie-1', fromParty: true);
    await tester.pump();
    final expanded = tester.element(find.byType(PlayerView));

    notifier.minimise();
    await tester.pump();
    final floating = tester.element(find.byType(PlayerView));

    notifier.expand();
    await tester.pump();
    final again = tester.element(find.byType(PlayerView));

    expect(
      identical(expanded, floating),
      isTrue,
      reason: 'minimising must not rebuild the player — that reloads the media',
    );
    expect(identical(floating, again), isTrue);
    expect(find.byType(PlayerView), findsOneWidget);
  });

  testWidgets('the floating tile is smaller than the window and 16:9', (
    tester,
  ) async {
    await pumpHost(tester);
    final notifier = container.read(nowPlayingProvider.notifier);

    notifier.open(itemId: 'movie-1', fromParty: true);
    await tester.pumpAndSettle();
    final expandedSize = tester.getSize(find.byType(PlayerView));

    notifier.minimise();
    await tester.pumpAndSettle();
    final floatingSize = tester.getSize(find.byType(PlayerView));

    expect(expandedSize.width, 1200);
    expect(floatingSize.width, lessThan(expandedSize.width));
    // 16:9 within a pixel — the tile carries the video's shape, not the 4:3 the
    // camera tiles are built around.
    expect(floatingSize.width / floatingSize.height, closeTo(16 / 9, 0.05));
  });

  testWidgets('closing unmounts the player and leaves the app behind', (
    tester,
  ) async {
    await pumpHost(tester);
    final notifier = container.read(nowPlayingProvider.notifier);

    notifier.open(itemId: 'movie-1', fromParty: true);
    await tester.pump();
    await notifier.close();
    await tester.pump();

    expect(find.byType(PlayerView), findsNothing);
    expect(find.text('library'), findsOneWidget);
  });
}
