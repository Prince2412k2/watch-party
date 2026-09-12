import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/data/mock_api_client.dart';
import 'package:watchparty/player/mock_player_controller.dart';
import 'package:watchparty/player/player_host.dart';
import 'package:watchparty/player/player_view.dart';
import 'package:watchparty/models/party_state.dart';
import 'package:watchparty/state/party_provider.dart';
import 'package:watchparty/state/chat_provider.dart';
import 'package:watchparty/state/now_playing_provider.dart';
import 'package:watchparty/state/player_provider.dart';
import 'package:watchparty/state/providers.dart';
import 'package:watchparty/ui/ui.dart';
import 'package:watchparty/ui/widgets/floating_camera_tile.dart';

class _TestPlayer extends MockPlayerController {
  int openCalls = 0;
  int seekCalls = 0;

  @override
  Future<void> open(
    String url, {
    Duration startAt = Duration.zero,
    bool autoplay = false,
  }) async {
    openCalls++;
    await super.open(url, startAt: startAt, autoplay: autoplay);
  }

  @override
  Future<void> play() async {}

  @override
  Future<void> seek(Duration position) async {
    seekCalls++;
    await super.seek(position);
  }
}

/// The host exists so there is exactly ONE PlayerView for the life of the
/// session, with expanded/floating being a rect it animates between rather than
/// two different mounts. The identity assertions below are the whole point: if
/// the element is rebuilt, the video texture is re-attached and the media
/// reloads — which is the bug this replaced.
void main() {
  late ProviderContainer container;
  late _TestPlayer player;

  setUp(() {
    player = _TestPlayer();
    container = ProviderContainer(
      overrides: [
        playerControllerProvider.overrideWithValue(player),
        apiClientProvider.overrideWithValue(MockApiClient()),
        currentUserIdProvider.overrideWithValue('host'),
      ],
    );
  });
  tearDown(() async {
    await player.dispose();
    container.dispose();
  });

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
    container.read(nowPlayingProvider.notifier).open(itemId: 'movie-1');
    await tester.pump();

    expect(find.byType(PlayerView), findsOneWidget);
    expect(find.text('library'), findsOneWidget);
  });

  testWidgets('track and title updates never reopen the native media', (
    tester,
  ) async {
    await pumpHost(tester);
    final notifier = container.read(nowPlayingProvider.notifier);
    notifier.open(itemId: 'movie-1', title: 'Loading');
    await tester.pump();
    await tester.pump();
    expect(player.openCalls, 1);
    final seekCalls = player.seekCalls;

    notifier.open(
      itemId: 'movie-1',
      title: 'Dune',
      audioStreamIndex: 2,
      subtitleStreamIndex: 3,
    );
    await tester.pump();
    notifier.open(
      itemId: 'movie-1',
      title: 'Dune',
      audioStreamIndex: 4,
      subtitleStreamIndex: -1,
    );
    await tester.pump();
    notifier.open(
      itemId: 'movie-1',
      title: 'Dune',
      audioStreamIndex: 2,
      subtitleStreamIndex: 3,
    );
    await tester.pump();

    expect(player.openCalls, 1);
    expect(player.seekCalls, seekCalls);
    expect(container.read(nowPlayingProvider).subtitleStreamIndex, 3);
  });

  testWidgets('minimise and expand reuse the same PlayerView safely', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpHost(tester);
    final notifier = container.read(nowPlayingProvider.notifier);

    notifier.open(itemId: 'movie-1');
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
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('the floating tile is smaller than the window and 16:9', (
    tester,
  ) async {
    await pumpHost(tester);
    final notifier = container.read(nowPlayingProvider.notifier);

    notifier.open(itemId: 'movie-1');
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

  testWidgets('platform Back minimises an expanded movie', (tester) async {
    await pumpHost(tester);
    container.read(nowPlayingProvider.notifier).open(itemId: 'movie-1');
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(container.read(nowPlayingProvider).isFloating, isTrue);
  });

  for (final path in ['back', 'escape', 'platform']) {
    testWidgets('$path awaits fullscreen exit before minimising', (
      tester,
    ) async {
      final exit = Completer<void>();
      const channel = MethodChannel('window_manager');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'isFullScreen') return false;
        if (call.method == 'setFullScreen' &&
            (call.arguments as Map)['isFullScreen'] == false) {
          await exit.future;
        }
        return null;
      });
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        );
      });
      await pumpHost(tester);
      container.read(nowPlayingProvider.notifier).open(itemId: 'movie-1');
      await tester.pump();
      tester.widget<PlayerView>(find.byType(PlayerView)).onToggleFullscreen!();
      await tester.pump();
      expect(
        tester.widget<PlayerView>(find.byType(PlayerView)).isFullscreen,
        true,
      );
      switch (path) {
        case 'back':
          tester.widget<PlayerView>(find.byType(PlayerView)).onBack!();
        case 'escape':
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        case 'platform':
          unawaited(tester.binding.handlePopRoute());
      }
      await tester.pump();
      expect(container.read(nowPlayingProvider).isExpanded, true);
      exit.complete();
      await tester.pump();
      expect(container.read(nowPlayingProvider).isFloating, true);
    });
  }

  testWidgets('host teardown tolerates outstanding child holds', (
    tester,
  ) async {
    await pumpHost(tester);
    container.read(nowPlayingProvider.notifier).open(itemId: 'movie-1');
    await tester.pump();
    final view = tester.widget<PlayerView>(find.byType(PlayerView));
    expect(view.onHold, isNotNull);
    expect(view.onRelease, isNotNull);
    view.onHold!('settingsStack');
    await tester.pumpWidget(const SizedBox.shrink());
    view.onRelease!('settingsStack');
    view.onWake!();
    await tester.pump(const Duration(seconds: 4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the whole floating movie drags and snaps to a corner', (
    tester,
  ) async {
    await pumpHost(tester);
    final notifier = container.read(nowPlayingProvider.notifier);
    notifier.open(itemId: 'movie-1');
    notifier.minimise();
    await tester.pumpAndSettle();

    await tester.dragFrom(
      tester.getCenter(find.byType(PlayerView)),
      const Offset(-900, 700),
    );
    await tester.pumpAndSettle();

    final rect = tester.getRect(find.byType(PlayerView));
    expect(rect.left, closeTo(FloatingTileGeometry.margin, 1));
    expect(rect.bottom, closeTo(800 - FloatingTileGeometry.margin, 1));
  });

  testWidgets('closing unmounts the player and leaves the app behind', (
    tester,
  ) async {
    await pumpHost(tester);
    final notifier = container.read(nowPlayingProvider.notifier);

    notifier.open(itemId: 'movie-1');
    await tester.pump();
    await notifier.close();
    await tester.pump();

    expect(find.byType(PlayerView), findsNothing);
    expect(find.text('library'), findsOneWidget);
  });

  testWidgets('party ending is not duplicated in the movie top bar', (
    tester,
  ) async {
    container
        .read(partyProvider.notifier)
        .setState(const PartyState(id: 'ROOM1234', hostId: 'host'));
    await pumpHost(tester);
    container.read(nowPlayingProvider.notifier).open(itemId: 'movie-1');
    await tester.pump();

    expect(find.byKey(const Key('closePartyFromPlayerButton')), findsNothing);
    expect(find.text('End watch party'), findsNothing);
  });

  testWidgets('Ctrl+C opens chat from the app-wide player host', (
    tester,
  ) async {
    container
        .read(partyProvider.notifier)
        .setState(const PartyState(id: 'ROOM1234', hostId: 'host'));
    await pumpHost(tester);
    container.read(nowPlayingProvider.notifier).open(itemId: 'movie-1');
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(container.read(chatDrawerOpenProvider), isTrue);
  });
}
