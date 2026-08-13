import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:watchparty/analog/chrome/chrome.dart';
import 'package:watchparty/app/router.dart';
import 'package:watchparty/app/screens/detail_screen.dart';
import 'package:watchparty/app/screens/downloads_screen.dart';
import 'package:watchparty/data/mock_api_client.dart';
import 'package:watchparty/models/models.dart';
import 'package:watchparty/state/state.dart';

/// Putting a title on the server's disk — or taking it off — belongs to the
/// administrator. These cover the client half of that: what a member is shown,
/// and what the one delete affordance actually deletes. The server half (403 on
/// every acquisition route) is `app/server/servarr/index.test.js`; the UI here
/// only keeps a member from being handed a control that would answer 403.

/// A library movie carrying the Tmdb id the Radarr record is joined on, plus a
/// Radarr library that holds a record for it.
class _RadarrApi extends MockApiClient {
  _RadarrApi({this.inRadarr = true});

  /// The Tmdb id both sides of the join carry.
  static const tmdbId = 550;

  final bool inRadarr;

  /// Every servarr delete this test saw, as `(path, query)`.
  final deletes = <(String, Map<String, dynamic>?)>[];

  static const _movie = LibraryItem(
    id: 'movie-1',
    name: 'Fight Club',
    type: 'Movie',
    overview: 'Two men start a club.',
    productionYear: 1999,
    runTimeTicks: 30000000000,
  );

  @override
  Future<LibraryItem> item(String id) async =>
      _movie.copyWith(providerIds: {'Tmdb': '$tmdbId'});

  @override
  Future<List<LibraryItem>> children(String itemId) async => const [];

  @override
  Future<dynamic> servarrGet(String path, {Map<String, dynamic>? query}) async {
    if (path == 'radarr/movies') {
      return [
        if (inRadarr)
          {'id': 77, 'tmdbId': tmdbId, 'title': 'Fight Club', 'hasFile': true},
        {'id': 78, 'tmdbId': 999999, 'title': 'Something Else'},
      ];
    }
    return super.servarrGet(path, query: query);
  }

  @override
  Future<dynamic> servarrDelete(
    String path, {
    Map<String, dynamic>? query,
    Object? body,
  }) async {
    deletes.add((path, query));
    return {'ok': true};
  }
}

Widget _detail(MockApiClient api, {required bool isAdmin}) => ProviderScope(
  overrides: [
    apiClientProvider.overrideWithValue(api),
    authProvider.overrideWith((ref) {
      final notifier = AuthNotifier(ref);
      notifier.state = AuthState(
        user: User(userId: 'u1', name: 'Test User', isAdmin: isAdmin),
        initialized: true,
      );
      return notifier;
    }),
  ],
  // A real router, because deleting the title leaves the page it was showing
  // and [DetailScreen]'s back action is go_router's.
  child: MaterialApp.router(
    builder: (context, child) => AnalogToastHost(child: child!),
    routerConfig: GoRouter(
      initialLocation: '/detail/movie-1',
      routes: [
        GoRoute(
          path: '/detail/:id',
          builder: (_, state) =>
              DetailScreen(itemId: state.pathParameters['id']!),
        ),
        GoRoute(path: '/movies', builder: (_, _) => const SizedBox()),
      ],
    ),
  ),
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// Set the window size the widgets actually see.
///
/// NOT `binding.setSurfaceSize`, which leaves `MediaQuery.size` at the default
/// 800x600 — every size assertion written against it silently tests the default
/// instead of the size asked for, which is how the narrow-window case below
/// passed while rendering the wide layout.
void _window(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
}

void main() {
  group('admin-only routes', () {
    test('the acquisition surfaces are named, and nothing else is', () {
      expect(isAdminOnlyRoute('/discover'), isTrue);
      expect(isAdminOnlyRoute('/servarr/queue'), isTrue);
      // A SERVER torrent, with pause/resume/delete on it.
      expect(isAdminOnlyRoute('/downloads/abc123'), isTrue);

      // ...but the downloads tab itself is this device's list, and everything
      // else is about watching what is already here.
      expect(isAdminOnlyRoute('/downloads'), isFalse);
      expect(isAdminOnlyRoute('/movies'), isFalse);
      expect(isAdminOnlyRoute('/series'), isFalse);
      expect(isAdminOnlyRoute('/offline'), isFalse);
      expect(isAdminOnlyRoute('/detail/abc'), isFalse);
      expect(isAdminOnlyRoute('/settings'), isFalse);
    });
  });

  downloadsAndPaletteTests();

  group('delete from the server', () {
    testWidgets('an admin gets it on a title Radarr holds', (tester) async {
      _window(tester, const Size(1280, 800));

      await tester.pumpWidget(_detail(_RadarrApi(), isAdmin: true));
      await _settle(tester);

      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('a member never sees it', (tester) async {
      _window(tester, const Size(1280, 800));

      await tester.pumpWidget(_detail(_RadarrApi(), isAdmin: false));
      await _settle(tester);

      expect(find.text('Delete'), findsNothing);
      // The device-local download button is untouched: that is theirs.
      expect(find.text('Watch now'), findsOneWidget);
    });

    testWidgets('nothing to delete → nothing offered, even to an admin', (
      tester,
    ) async {
      _window(tester, const Size(1280, 800));

      // Jellyfin has the film; Radarr never added it (hand-copied, imported by
      // something else). A delete here has no record to act on, so there is no
      // button — not a disabled one.
      await tester.pumpWidget(
        _detail(_RadarrApi(inRadarr: false), isAdmin: true),
      );
      await _settle(tester);

      expect(find.text('Delete'), findsNothing);
    });

    testWidgets('confirming deletes the matched record, with its files', (
      tester,
    ) async {
      _window(tester, const Size(1280, 800));

      final api = _RadarrApi();
      await tester.pumpWidget(_detail(api, isAdmin: true));
      await _settle(tester);

      await tester.tap(find.text('Delete'));
      await _settle(tester);
      // Nothing has gone yet — the dialog is a real gate, not a formality.
      expect(api.deletes, isEmpty);

      await tester.tap(find.text('Delete').last);
      await _settle(tester);

      // Id 77 is the Radarr record whose tmdbId matched the Jellyfin item —
      // NOT the other row in that library, and not the Jellyfin item id.
      expect(api.deletes, hasLength(1));
      expect(api.deletes.single.$1, 'radarr/movie/77');
      expect(api.deletes.single.$2, {'deleteFiles': 'true'});
    });
  });
}

Widget _downloads(MockApiClient api, {required bool isAdmin}) => ProviderScope(
  overrides: [
    apiClientProvider.overrideWithValue(api),
    authProvider.overrideWith((ref) {
      final notifier = AuthNotifier(ref);
      notifier.state = AuthState(
        user: User(userId: 'u1', name: 'Test User', isAdmin: isAdmin),
        initialized: true,
      );
      return notifier;
    }),
  ],
  child: MaterialApp(
    builder: (context, child) => AnalogToastHost(child: child!),
    home: const DownloadsScreen(),
  ),
);

void downloadsAndPaletteTests() {
  group('the Downloads tabs', () {
    testWidgets('an admin chooses between this device and the server', (
      tester,
    ) async {
      _window(tester, const Size(1280, 900));

      await tester.pumpWidget(_downloads(MockApiClient(), isAdmin: true));
      await _settle(tester);

      expect(find.text('This device'), findsOneWidget);
      expect(find.text('Server'), findsOneWidget);
      // Device is where it opens: your own downloads are the common case, and
      // the server queue is the administrative one.
      expect(find.text('Nothing downloaded yet'), findsOneWidget);

      await tester.tap(find.text('Server'));
      await _settle(tester);
      expect(find.text('Nothing downloaded yet'), findsNothing);
    });

    testWidgets('a member gets no tabs at all, just their own downloads', (
      tester,
    ) async {
      _window(tester, const Size(1280, 900));

      await tester.pumpWidget(_downloads(MockApiClient(), isAdmin: false));
      await _settle(tester);

      // One tab is a control that lies about being one.
      expect(find.text('This device'), findsNothing);
      expect(find.text('Server'), findsNothing);
      expect(find.text('Nothing downloaded yet'), findsOneWidget);
    });
  });

  group('the fuzzy finder', () {
    Future<void> open(
      WidgetTester tester, {
      required bool previewPane,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          // The palette opens on the root navigator, ABOVE any route's own
          // Scaffold, so its Material plumbing comes from the app builder —
          // exactly as `app.dart` supplies it.
          builder: (context, child) => Material(
            type: MaterialType.transparency,
            child: AnalogToastHost(child: child!),
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
              onPressed: () => showAnalogCommandPalette(
                context: context,
                previewPane: previewPane,
                debounce: Duration.zero,
                results: (_) => Stream.value([
                  AnalogCommandCategory(
                    title: 'Library',
                    items: [
                      AnalogCommandItem(
                        label: 'Fight Club',
                        onSelected: () {},
                        preview: (_) => const Text('POSTER: Fight Club'),
                      ),
                      AnalogCommandItem(
                        label: 'Shrek',
                        onSelected: () {},
                        preview: (_) => const Text('POSTER: Shrek'),
                      ),
                    ],
                  ),
                ]),
              ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await _settle(tester);
    }

    testWidgets('shows the highlighted row beside the list, and follows it', (
      tester,
    ) async {
      _window(tester, const Size(1280, 900));

      await open(tester, previewPane: true);

      // Both names on the left; only the highlighted one's poster on the right.
      expect(find.text('Fight Club'), findsOneWidget);
      expect(find.text('Shrek'), findsOneWidget);
      expect(find.text('POSTER: Fight Club'), findsOneWidget);
      expect(find.text('POSTER: Shrek'), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await _settle(tester);

      expect(find.text('POSTER: Shrek'), findsOneWidget);
      expect(find.text('POSTER: Fight Club'), findsNothing);
    });

    testWidgets('a narrow window keeps the list and drops the pane', (
      tester,
    ) async {
      _window(tester, const Size(600, 900));

      await open(tester, previewPane: true);

      expect(find.text('Fight Club'), findsOneWidget);
      expect(find.text('POSTER: Fight Club'), findsNothing);
    });
  });
}
