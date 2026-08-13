import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/cache/media_cache_proxy.dart';
import 'package:watchparty/data/catalog_repository.dart';
import 'package:watchparty/data/mock_api_client.dart';
import 'package:watchparty/models/models.dart';
import 'package:watchparty/player/mock_player_controller.dart';
import 'package:watchparty/player/open_title.dart';
import 'package:watchparty/state/state.dart';

/// Opening a title has to start where the viewer left off, and the position it
/// starts from must be CURRENT.
///
/// The bug this pins: the resume point was read through `itemDetailProvider`,
/// whose repository yields its disk cache first and the fresh copy second — so
/// awaiting it returned the snapshot taken before the film was ever watched.
/// Browsing to a title is what caches it, so the stale copy was not an edge
/// case, it was every play.

/// Answers with a real watch position, as the server does once playback has
/// been reported.
class _WatchedApi extends MockApiClient {
  _WatchedApi(this.ticks);
  final int ticks;
  int itemCalls = 0;

  @override
  Future<LibraryItem> item(String id) async {
    itemCalls++;
    return LibraryItem(
      id: id,
      name: 'A Film',
      type: 'Movie',
      userData: UserItemData(playbackPositionTicks: ticks),
    );
  }
}

/// The on-device proxy, minus the socket. The real one throws from `urlFor`
/// until `start()` has bound a port, and `openTitleIntoPlayer` catches that —
/// which silently turns "could not open at all" into "opened at zero", the
/// exact reading this test exists to tell apart.
class _FakeProxy extends MediaCacheProxy {
  _FakeProxy({required super.apiClient});

  @override
  String urlFor(String itemId, {String? mediaSourceId}) =>
      'http://127.0.0.1:1/m/$itemId';
}

/// The catalog's copy: what was cached when the user browsed past this title,
/// before they had watched a second of it.
class _StaleCatalogApi extends MockApiClient {
  @override
  Future<LibraryItem> item(String id) async => const LibraryItem(
    id: 'item-1',
    name: 'A Film',
    type: 'Movie',
    userData: UserItemData(playbackPositionTicks: 0),
  );
}

Future<Duration> openAndReport({
  required WidgetTester tester,
  required MockApiClient api,
  required MockPlayerController player,
  PartyState? party,
}) async {
  late WidgetRef captured;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        playerControllerProvider.overrideWithValue(player),
        mediaCacheProxyProvider.overrideWithValue(_FakeProxy(apiClient: api)),
        // The stale half of the split: the repository the rest of the app
        // reads titles through still believes nothing has been watched.
        catalogRepositoryProvider.overrideWithValue(
          CatalogRepository(api: _StaleCatalogApi()),
        ),
        authProvider.overrideWith((ref) {
          final notifier = AuthNotifier(ref);
          notifier.state = const AuthState(
            user: User(userId: 'u1', name: 'Test User'),
            initialized: true,
          );
          return notifier;
        }),
        if (party != null)
          partyProvider.overrideWith((ref) => PartyNotifier(ref)..state = party),
      ],
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) {
            captured = ref;
            return const SizedBox();
          },
        ),
      ),
    ),
  );
  await tester.pump();

  final result = await openTitleIntoPlayer(
    captured,
    player,
    itemId: 'item-1',
    isStale: () => false,
  );
  // Asserted here so a failure to open can never masquerade as "resumed at the
  // beginning" — which is precisely how this test first went green-adjacent.
  expect(result.ok, isTrue, reason: 'open failed: ${result.error}');
  final position = player.positionNow;
  // The mock advances position on a periodic timer while playing, and a live
  // timer at the end of a widget test fails it.
  await player.pause();
  return position;
}

void main() {
  testWidgets('a title opens at the position the server holds, not the cached one', (
    tester,
  ) async {
    final position = await openAndReport(
      tester: tester,
      api: _WatchedApi(PlaybackReport.ticksOf(const Duration(minutes: 45))),
      player: MockPlayerController(),
    );

    // 45 minutes, not zero. Zero here is the cached copy winning.
    expect(position, const Duration(minutes: 45));
  });

  testWidgets('an unwatched title opens at the beginning', (tester) async {
    final position = await openAndReport(
      tester: tester,
      api: _WatchedApi(0),
      player: MockPlayerController(),
    );
    expect(position, Duration.zero);
  });

  testWidgets('a title whose detail cannot be fetched still opens', (
    tester,
  ) async {
    // Losing the resume point costs the viewer a seek; failing here would cost
    // them the film.
    final position = await openAndReport(
      tester: tester,
      api: MockApiClient(),
      player: MockPlayerController(),
    );
    expect(position, Duration.zero);
  });

  testWidgets('in a party the room decides the position, not your history', (
    tester,
  ) async {
    final position = await openAndReport(
      tester: tester,
      api: _WatchedApi(PlaybackReport.ticksOf(const Duration(minutes: 45))),
      player: MockPlayerController(),
      party: const PartyState(id: 'room-1', hostId: 'someone-else'),
    );

    // Seeking to your own resume point would jump the film to a scene nobody
    // else is on, until sync drags it back.
    expect(position, Duration.zero);
  });
}
