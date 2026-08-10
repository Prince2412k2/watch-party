import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/analog/chrome/chrome.dart';
import 'package:go_router/go_router.dart';
import 'package:watchparty/app/screens/detail_screen.dart';
import 'package:watchparty/cache/media_cache_proxy.dart';
import 'package:watchparty/data/mock_api_client.dart';
import 'package:watchparty/models/models.dart';
import 'package:watchparty/net/events.dart';
import 'package:watchparty/net/socket_client.dart';
import 'package:watchparty/player/mock_player_controller.dart';
import 'package:watchparty/state/state.dart';
import 'package:watchparty/ui/ui.dart';

class _TestMediaCacheProxy extends MediaCacheProxy {
  _TestMediaCacheProxy() : super(apiClient: MockApiClient());

  @override
  String urlFor(String itemId, {String? mediaSourceId}) =>
      'http://127.0.0.1/test/$itemId';
}

void main() {
  testWidgets('Watch stays local while a party is active', (tester) async {
    final socket = MockSocketClient();
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(MockApiClient()),
        socketClientProvider.overrideWithValue(socket),
        authProvider.overrideWith((ref) {
          final notifier = AuthNotifier(ref);
          notifier.state = const AuthState(
            user: User(userId: 'host', name: 'Host'),
            initialized: true,
          );
          return notifier;
        }),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(partyProvider.notifier)
        .setState(const PartyState(id: 'party-1', hostId: 'host'));

    final router = GoRouter(
      initialLocation: '/detail/mock-item-0',
      routes: [
        GoRoute(
          path: '/detail/:id',
          builder: (_, state) =>
              DetailScreen(itemId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: '/party/:id',
          builder: (_, state) => Text('Party ${state.pathParameters['id']}'),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: AppTheme.dark,
          routerConfig: router,
          builder: (context, child) => AnalogToastHost(child: child!),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Watch now'));
    await tester.pumpAndSettle();

    // Playing NEVER navigates now. The room is told what to play, the local
    // player state opens, and you stay on the page you were reading.
    expect(find.text('Party party-1'), findsNothing);
    expect(find.text('Watch now'), findsOneWidget);
    final now = container.read(nowPlayingProvider);
    expect(now.itemId, 'mock-item-0');
    expect(now.isExpanded, isTrue);
    expect(
      socket.emitted.where((event) => event.$1 == ClientEvent.partySelectMedia),
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('watching solo opens the app player without navigating', (
    tester,
  ) async {
    final player = MockPlayerController();
    final proxy = _TestMediaCacheProxy();
    addTearDown(player.dispose);
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(MockApiClient()),
        mediaCacheProxyProvider.overrideWithValue(proxy),
        playerControllerProvider.overrideWithValue(player),
        authProvider.overrideWith((ref) {
          final notifier = AuthNotifier(ref);
          notifier.state = const AuthState(
            user: User(userId: 'host', name: 'Host'),
            initialized: true,
          );
          return notifier;
        }),
      ],
    );
    addTearDown(container.dispose);

    final router = GoRouter(
      initialLocation: '/detail/mock-item-0',
      routes: [
        GoRoute(
          path: '/detail/:id',
          builder: (_, state) =>
              DetailScreen(itemId: state.pathParameters['id']!),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: AppTheme.dark,
          routerConfig: router,
          builder: (context, child) => AnalogToastHost(child: child!),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Watch now'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // The player used to be a pushed route, so Back popped it and stopped
    // playback. It is state now: the detail page is still underneath, and
    // minimising is what Back does.
    final notifier = container.read(nowPlayingProvider.notifier);
    expect(container.read(nowPlayingProvider).isExpanded, isTrue);
    expect(find.text('Watch now'), findsOneWidget);

    notifier.minimise();
    expect(container.read(nowPlayingProvider).isFloating, isTrue);
    expect(
      container.read(nowPlayingProvider).itemId,
      'mock-item-0',
      reason: 'minimising keeps the title open',
    );
    expect(tester.takeException(), isNull);
  });
}
