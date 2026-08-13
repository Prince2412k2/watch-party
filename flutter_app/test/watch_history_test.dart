import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:watchparty/data/api_client.dart';
import 'package:watchparty/data/mock_api_client.dart';
import 'package:watchparty/models/models.dart';
import 'package:watchparty/player/mock_player_controller.dart';
import 'package:watchparty/state/state.dart';

/// Watch history is the whole reason Continue Watching, Next Up, the Resume
/// button and every progress bar in the app have anything to show — Jellyfin
/// fills those in only for playback it was told about. These cover the telling:
/// that a session opens and closes, that the position reported is the player's
/// real one, and that a stop survives being offline, because a lost stop is a
/// lost resume point.

/// Fails every report, as a server that is down or unreachable does.
class _OfflineApi extends MockApiClient {
  int attempts = 0;

  @override
  Future<void> reportPlayback(
    PlaybackReport report, {
    required PlaybackReportKind kind,
  }) async {
    attempts++;
    throw ApiException('reportPlayback', 0, 'offline');
  }
}

ProviderContainer _container(MockApiClient api, MockPlayerController player) {
  final container = ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      playerControllerProvider.overrideWithValue(player),
      authProvider.overrideWith((ref) {
        final notifier = AuthNotifier(ref);
        notifier.state = const AuthState(
          user: User(userId: 'u1', name: 'Test User'),
          initialized: true,
        );
        return notifier;
      }),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// A title actually open in the player. `isOpen` needs a presentation as well
/// as an id — an id alone is a title the player has been TOLD about, not one it
/// is showing.
NowPlaying _open(String itemId) => NowPlaying(
  itemId: itemId,
  title: 'A Film',
  presentation: PlayerPresentation.expanded,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('opening a title starts a session, closing it stops one', () async {
    final api = MockApiClient();
    final player = MockPlayerController();
    final reporter = _container(api, player).read(watchHistoryProvider);

    await reporter.open(_open('item-1'));
    expect(api.playbackReports.single.$1, PlaybackReportKind.started);
    expect(api.playbackReports.single.$2.itemId, 'item-1');
    // Starting is position zero, and the session id ties the three calls into
    // one play rather than a stream of unrelated positions.
    expect(api.playbackReports.single.$2.positionTicks, 0);
    expect(api.playbackReports.single.$2.playSessionId, isNotNull);

    await player.seek(const Duration(minutes: 12));
    await reporter.close();

    final stop = api.playbackReports.last;
    expect(stop.$1, PlaybackReportKind.stopped);
    // The position Jellyfin derives the resume point from is the player's, read
    // at the moment of the stop — not whatever the last tick happened to say.
    expect(stop.$2.positionTicks, PlaybackReport.ticksOf(const Duration(minutes: 12)));
    expect(stop.$2.playSessionId, api.playbackReports.first.$2.playSessionId);
  });

  test('switching titles stops the outgoing one before starting the next', () async {
    final api = MockApiClient();
    final player = MockPlayerController();
    final reporter = _container(api, player).read(watchHistoryProvider);

    await reporter.open(_open('item-1'));
    await player.seek(const Duration(minutes: 30));
    await reporter.open(_open('item-2'));

    final kinds = api.playbackReports.map((r) => r.$1).toList();
    final items = api.playbackReports.map((r) => r.$2.itemId).toList();
    expect(kinds, [
      PlaybackReportKind.started,
      PlaybackReportKind.stopped,
      PlaybackReportKind.started,
    ]);
    // Without the stop, the first title keeps the position it had when we
    // looked away and never gets a resume point.
    expect(items, ['item-1', 'item-1', 'item-2']);
    expect(
      api.playbackReports[1].$2.positionTicks,
      PlaybackReport.ticksOf(const Duration(minutes: 30)),
    );
  });

  test('closing twice reports once', () async {
    final api = MockApiClient();
    final reporter = _container(api, MockPlayerController()).read(
      watchHistoryProvider,
    );

    await reporter.open(_open('item-1'));
    await reporter.close();
    await reporter.close();

    expect(
      api.playbackReports.where((r) => r.$1 == PlaybackReportKind.stopped),
      hasLength(1),
    );
  });

  test('a signed-out viewer reports nothing at all', () async {
    final api = MockApiClient();
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        playerControllerProvider.overrideWithValue(MockPlayerController()),
      ],
    );
    addTearDown(container.dispose);

    // A guest watching a downloaded title has no session to write against.
    await container.read(watchHistoryProvider).open(_open('item-1'));
    await container.read(watchHistoryProvider).close();
    expect(api.playbackReports, isEmpty);
  });

  group('offline', () {
    test('a lost stop is kept and sent later; a lost tick is not', () async {
      final offline = _OfflineApi();
      final player = MockPlayerController();
      final reporter = _container(offline, player).read(watchHistoryProvider);

      await reporter.open(_open('item-1'));
      await player.seek(const Duration(minutes: 20));
      await reporter.flush();       // a progress tick, lost
      await reporter.close();       // the stop, kept

      final queued = SharedPreferences.getInstance().then(
        (p) => p.getStringList(kWatchHistoryQueueKey) ?? const <String>[],
      );
      // Exactly one: the stop. A dropped progress tick is worth nothing — a
      // newer position follows in seconds — but a dropped stop IS the resume
      // point, so it is the only kind worth keeping.
      expect(await queued, hasLength(1));
      expect((await queued).single, contains('item-1'));

      // Back online: the queue drains and the position finally lands.
      final online = MockApiClient();
      final second = _container(online, player).read(watchHistoryProvider);
      await second.drainPending();

      expect(online.playbackReports, hasLength(1));
      expect(online.playbackReports.single.$1, PlaybackReportKind.stopped);
      expect(
        online.playbackReports.single.$2.positionTicks,
        PlaybackReport.ticksOf(const Duration(minutes: 20)),
      );
      final drained = await SharedPreferences.getInstance();
      expect(drained.getStringList(kWatchHistoryQueueKey), isEmpty);
    });

    test('a second stop for the same title supersedes the first', () async {
      final offline = _OfflineApi();
      final player = MockPlayerController();
      final reporter = _container(offline, player).read(watchHistoryProvider);

      await reporter.open(_open('item-1'));
      await player.seek(const Duration(minutes: 10));
      await reporter.close();

      await reporter.open(_open('item-1'));
      await player.seek(const Duration(minutes: 40));
      await reporter.close();

      final prefs = await SharedPreferences.getInstance();
      final queue = prefs.getStringList(kWatchHistoryQueueKey)!;
      // Replaying both would move the resume point BACKWARDS — whichever landed
      // last would win, and that is the older one half the time.
      expect(queue, hasLength(1));
      final report = PlaybackReport.fromJson(
        jsonDecode(queue.single) as Map<String, dynamic>,
      )!;
      expect(
        report.positionTicks,
        PlaybackReport.ticksOf(const Duration(minutes: 40)),
      );
    });

    test('the queue is bounded', () async {
      final offline = _OfflineApi();
      final player = MockPlayerController();
      final reporter = _container(offline, player).read(watchHistoryProvider);

      for (var i = 0; i < kWatchHistoryQueueLimit + 20; i++) {
        await reporter.open(_open('item-$i'));
        await reporter.close();
      }

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getStringList(kWatchHistoryQueueKey),
        hasLength(kWatchHistoryQueueLimit),
      );
    });
  });

  test('ticks and durations round-trip', () {
    const position = Duration(hours: 1, minutes: 23, seconds: 45);
    // Jellyfin counts in 100ns units; a factor-of-ten slip here lands the
    // resume point in the wrong scene rather than throwing anything.
    expect(PlaybackReport.ticksOf(position), position.inMicroseconds * 10);
    expect(PlaybackReport.durationOf(PlaybackReport.ticksOf(position)), position);
  });
}
