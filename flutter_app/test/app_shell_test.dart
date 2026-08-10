import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/analog/chrome/chrome.dart';
import 'package:go_router/go_router.dart';
import 'package:watchparty/app/screens/app_shell.dart';
import 'package:watchparty/data/catalog_repository.dart';
import 'package:watchparty/data/mock_api_client.dart';
import 'package:watchparty/models/models.dart';
import 'package:watchparty/state/state.dart';
import 'package:watchparty/ui/ui.dart';

/// Counts browse-catalog fetches, which is the only thing the launch warm does.
class _CountingApi extends MockApiClient {
  int itemCalls = 0;

  @override
  Future<List<LibraryItem>> items({String? parentId}) async {
    itemCalls++;
    return const [];
  }
}

/// AppShell chrome renders analog tooltips/badges and can raise notices, so it
/// needs the theme plus an [AnalogToastHost] above it — mirror app.dart's
/// builder wrap here.
Widget _analog(BuildContext context, Widget? child) => Theme(
  data: AppTheme.dark,
  child: AnalogToastHost(child: child!),
);

/// A bare `ProviderScope` defaults `authProvider` to its un-initialized,
/// logged-out `AuthState()`. Signed-in tests need an authenticated override to
/// exercise the full four-tab nav.
List<Override> _signedIn() => [
  authProvider.overrideWith((ref) {
    final notifier = AuthNotifier(ref);
    notifier.state = const AuthState(
      user: User(userId: 'u1', name: 'Test User'),
      initialized: true,
    );
    return notifier;
  }),
];

Widget _shell({
  required List<Override> overrides,
  String location = '/movies',
}) => MaterialApp(
  theme: AppTheme.dark,
  builder: _analog,
  home: ProviderScope(
    overrides: overrides,
    child: AppShell(location: location, child: const SizedBox()),
  ),
);

void main() {
  testWidgets('AppShell shows the four web nav tabs when signed in', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    await tester.pumpWidget(_shell(overrides: _signedIn()));
    await tester.pump();

    expect(find.text('Movies'), findsOneWidget);
    expect(find.text('Shows'), findsOneWidget);
    expect(find.text('Discover'), findsOneWidget);
    expect(find.text('Downloads'), findsOneWidget);
  });

  testWidgets('AppShell shows the guest tabs + login when logged out', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    await tester.pumpWidget(_shell(overrides: const []));
    await tester.pump();

    // Guest nav is just browse + downloaded; no Shows/Discover tabs.
    expect(find.text('Movies'), findsOneWidget);
    expect(find.text('Downloaded'), findsOneWidget);
    expect(find.text('Shows'), findsNothing);
    expect(find.text('Discover'), findsNothing);
    // Top-right chrome is the login control, not the profile avatar.
    expect(find.byIcon(Icons.login), findsOneWidget);
  });

  group('catalog warm on launch', () {
    Future<_CountingApi> launch(WidgetTester tester, String location) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      final api = _CountingApi();
      final container = ProviderContainer(
        overrides: [
          ..._signedIn(),
          catalogNamespaceProvider.overrideWithValue('server|user'),
          catalogRepositoryProvider.overrideWithValue(
            CatalogRepository(api: api),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark,
            builder: _analog,
            home: AppShell(location: location, child: const SizedBox()),
          ),
        ),
      );
      await tester.pump();
      await container.read(catalogPrefetcherProvider).settle();
      return api;
    }

    testWidgets('coming up away from browse warms the catalog', (tester) async {
      expect((await launch(tester, '/downloads')).itemCalls, 1);
    });

    testWidgets('coming up on browse leaves the fetch to the screen', (
      tester,
    ) async {
      // The browse screen subscribes to the same key as it builds; warming it
      // underneath would be a second request for a payload already in flight.
      expect((await launch(tester, '/movies')).itemCalls, 0);
      expect((await launch(tester, '/series')).itemCalls, 0);
    });
  });

  group('shellSectionTitle', () {
    test('maps shelled locations (incl. nested paths) to their section', () {
      expect(shellSectionTitle('/movies'), 'Movies');
      expect(shellSectionTitle('/series'), 'Shows');
      expect(shellSectionTitle('/discover'), 'Discover');
      expect(shellSectionTitle('/discover/abc123'), 'Discover');
      expect(shellSectionTitle('/downloads'), 'Downloads');
    });

    test('falls back to the app name off the shell', () {
      expect(shellSectionTitle('/login'), 'Watchparty');
      expect(shellSectionTitle('/detail/xyz'), 'Watchparty');
      expect(shellSectionTitle('/'), 'Watchparty');
    });
  });

  const watching = PartyState(
    id: 'ROOM1234',
    hostId: 'u1',
    stage: 'watching',
    mediaItemId: 'movie-1',
  );

  Widget shellRouter(ProviderContainer container) => UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      theme: AppTheme.dark,
      builder: _analog,
      routerConfig: GoRouter(
        initialLocation: '/movies',
        routes: [
          ShellRoute(
            builder: (_, state, child) =>
                AppShell(location: state.uri.path, child: child),
            routes: [
              GoRoute(path: '/movies', builder: (_, _) => const SizedBox()),
            ],
          ),
        ],
      ),
    ),
  );

  ProviderContainer partyContainer() {
    final container = ProviderContainer(overrides: _signedIn());
    addTearDown(container.dispose);
    container.read(partyProvider.notifier).setState(watching);
    return container;
  }

  testWidgets("a watching room does not open or replace the user's movie", (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    final container = partyContainer();

    await tester.pumpWidget(shellRouter(container));
    await tester.pumpAndSettle();

    final now = container.read(nowPlayingProvider);
    expect(now.itemId, isNull);
    expect(now.isOpen, isFalse);
    expect(find.text('Movies'), findsOneWidget);
  });

  testWidgets('party updates do not affect local playback presentation', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    final container = partyContainer();
    await tester.pumpWidget(shellRouter(container));
    await tester.pumpAndSettle();

    container.read(nowPlayingProvider.notifier).open(itemId: 'my-movie');
    container.read(nowPlayingProvider.notifier).minimise();
    container.read(partyProvider.notifier).setState(watching);
    await tester.pumpAndSettle();

    expect(container.read(nowPlayingProvider).isFloating, isTrue);
    expect(container.read(nowPlayingProvider).itemId, 'my-movie');
    expect(container.read(partyProvider), isNotNull);
  });

  testWidgets('a guest in a room keeps a fully interactive app', (
    tester,
  ) async {
    // Regression: the shell used to wrap its whole child in IgnorePointer for
    // any member who was not the host, so being a guest in a room made your own
    // library, tabs and settings dead to the pointer. Rooms share playback,
    // chat and A/V — never your app.
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1200, 800));

    final container = ProviderContainer(
      overrides: [
        ..._signedIn(),
        apiClientProvider.overrideWithValue(MockApiClient()),
        currentUserIdProvider.overrideWithValue('guest-1'),
      ],
    );
    addTearDown(container.dispose);
    // A room I am in but do not host — the exact state that used to freeze the
    // shell. Set before the first build, never during one.
    container
        .read(partyProvider.notifier)
        .setState(const PartyState(id: 'ROOM1234', hostId: 'someone-else'));

    var tapped = false;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark,
          builder: _analog,
          home: AppShell(
            location: '/movies',
            child: Center(
              child: GestureDetector(
                onTap: () => tapped = true,
                child: const Text('content'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Scoped to ANCESTORS of the content: other chrome legitimately parks an
    // IgnorePointer over a hidden tray, and a tree-wide finder would catch those
    // and fail for the wrong reason.
    expect(
      find.ancestor(
        of: find.text('content'),
        matching: find.byWidgetPredicate(
          (widget) => widget is IgnorePointer && widget.ignoring,
        ),
      ),
      findsNothing,
      reason: 'a guest must never have the shell blocked',
    );

    await tester.tap(find.text('content'));
    await tester.pump();
    expect(tapped, isTrue);
  });
}
