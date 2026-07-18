import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sc;
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
  String urlFor(String itemId) => 'http://127.0.0.1/test/$itemId';
}

void main() {
  testWidgets(
    'Watch sends media into an existing party instead of going solo',
    (tester) async {
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
            builder: (context, child) => sc.ShadcnLayer(
              theme: AppShadcnTheme.dark,
              themeMode: sc.ThemeMode.dark,
              child: child!,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

    await tester.tap(find.text('Watch now'));
      await tester.pumpAndSettle();

      expect(find.text('Party party-1'), findsOneWidget);
      expect(socket.emitted.last.$1, ClientEvent.partySelectMedia);
      expect(
        socket.emitted.last.$2,
        containsPair('mediaItemId', 'mock-item-0'),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('solo player Back returns immediately to details', (tester) async {
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
          builder: (context, child) => sc.ShadcnLayer(
            theme: AppShadcnTheme.dark,
            themeMode: sc.ThemeMode.dark,
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Watch now'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byTooltip('Back'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Watch now'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
