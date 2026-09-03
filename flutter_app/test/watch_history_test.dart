import 'dart:async';
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

class _ReportGate {
  final arrived = Completer<void>();
  final release = Completer<void>();
}

class _GatedApi extends MockApiClient {
  final arrivals = <(PlaybackReportKind, PlaybackReport)>[];
  final _gates = <_ReportGate>[];

  _ReportGate gateNext() {
    final gate = _ReportGate();
    _gates.add(gate);
    return gate;
  }

  @override
  Future<void> reportPlayback(
    PlaybackReport report, {
    required PlaybackReportKind kind,
  }) async {
    arrivals.add((kind, report));
    if (_gates.isNotEmpty) {
      final gate = _gates.removeAt(0);
      gate.arrived.complete();
      await gate.release.future;
    }
    playbackReports.add((kind, report));
  }
}

class _GatedOfflineApi extends _OfflineApi {
  final arrivals = <(PlaybackReportKind, PlaybackReport)>[];
  _ReportGate? _gate;

  _ReportGate gateNext() => _gate = _ReportGate();

  @override
  Future<void> reportPlayback(
    PlaybackReport report, {
    required PlaybackReportKind kind,
  }) async {
    arrivals.add((kind, report));
    final gate = _gate;
    _gate = null;
    if (gate != null) {
      gate.arrived.complete();
      await gate.release.future;
    }
    return super.reportPlayback(report, kind: kind);
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

Future<void> _start(
  WatchHistoryReporter reporter,
  MockPlayerController player,
  String itemId,
) async {
  await reporter.open(_open(itemId));
  await player.play();
  await Future<void>.delayed(Duration.zero);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'disposing during a delayed start cannot resume queued reporting',
    () async {
      final api = _GatedApi();
      final player = MockPlayerController();
      final container = _container(api, player);
      final reporter = container.read(watchHistoryProvider);
      final gate = api.gateNext();

      await reporter.open(_open('movie'));
      await player.play();
      await gate.arrived.future;
      container.dispose();
      gate.release.complete();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(api.arrivals.map((entry) => entry.$1), [
        PlaybackReportKind.started,
      ]);
    },
  );
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('opening a title starts a session, closing it stops one', () async {
    final api = MockApiClient();
    final player = MockPlayerController();
    final reporter = _container(api, player).read(watchHistoryProvider);

    await reporter.open(_open('item-1'));
    await player.seek(const Duration(minutes: 12));
    await player.play();
    await Future<void>.delayed(Duration.zero);
    expect(api.playbackReports.single.$1, PlaybackReportKind.started);
    expect(api.playbackReports.single.$2.itemId, 'item-1');
    expect(
      api.playbackReports.single.$2.positionTicks,
      PlaybackReport.ticksOf(const Duration(minutes: 12)),
    );
    expect(api.playbackReports.single.$2.playSessionId, isNotNull);

    await reporter.close();
    await player.pause();

    final stop = api.playbackReports.last;
    expect(stop.$1, PlaybackReportKind.stopped);
    // The position Jellyfin derives the resume point from is the player's, read
    // at the moment of the stop — not whatever the last tick happened to say.
    expect(
      stop.$2.positionTicks,
      PlaybackReport.ticksOf(const Duration(minutes: 12)),
    );
    expect(stop.$2.playSessionId, api.playbackReports.first.$2.playSessionId);
  });

  test(
    'switching titles stops the outgoing one before starting the next',
    () async {
      final api = MockApiClient();
      final player = MockPlayerController();
      final reporter = _container(api, player).read(watchHistoryProvider);

      await _start(reporter, player, 'item-1');
      await player.seek(const Duration(minutes: 30));
      await reporter.open(_open('item-2'));
      await player.play();
      await Future<void>.delayed(Duration.zero);

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
      await reporter.close();
      await player.pause();
    },
  );

  test('a delayed start completes before progress and stop', () async {
    final api = _GatedApi();
    final player = MockPlayerController();
    final reporter = _container(api, player).read(watchHistoryProvider);

    await reporter.open(_open('item-1'));
    final startGate = api.gateNext();
    await player.play();
    await startGate.arrived.future;

    await player.seek(const Duration(minutes: 5));
    final progress = reporter.flush();
    final stop = reporter.close();
    await Future<void>.delayed(Duration.zero);
    expect(api.playbackReports, isEmpty);

    startGate.release.complete();
    await Future.wait([progress, stop]);
    expect(api.playbackReports.map((r) => r.$1), [
      PlaybackReportKind.started,
      PlaybackReportKind.progress,
      PlaybackReportKind.stopped,
    ]);
  });

  test(
    'a title switch observes playback that began while stop was delayed',
    () async {
      final api = _GatedApi();
      final player = MockPlayerController();
      final reporter = _container(api, player).read(watchHistoryProvider);

      await _start(reporter, player, 'item-1');
      await player.pause();
      await reporter.flush();

      final stopGate = api.gateNext();
      final switched = reporter.open(_open('item-2'));
      await stopGate.arrived.future;
      await player.play();
      stopGate.release.complete();
      await switched;

      expect(api.playbackReports.last.$1, PlaybackReportKind.started);
      expect(api.playbackReports.last.$2.itemId, 'item-2');
      await reporter.close();
      await player.pause();
    },
  );

  test('rapid title opens retain call order', () async {
    final api = _GatedApi();
    final player = MockPlayerController();
    final reporter = _container(api, player).read(watchHistoryProvider);

    await _start(reporter, player, 'item-1');
    final stopGate = api.gateNext();
    final second = reporter.open(_open('item-2'));
    await stopGate.arrived.future;
    final third = reporter.open(_open('item-3'));
    stopGate.release.complete();
    await Future.wait([second, third]);

    expect(api.playbackReports.map((r) => (r.$1, r.$2.itemId)), [
      (PlaybackReportKind.started, 'item-1'),
      (PlaybackReportKind.stopped, 'item-1'),
      (PlaybackReportKind.started, 'item-2'),
      (PlaybackReportKind.stopped, 'item-2'),
      (PlaybackReportKind.started, 'item-3'),
    ]);
    await reporter.close();
    await player.pause();
  });

  test('closing twice reports once', () async {
    final api = MockApiClient();
    final player = MockPlayerController();
    final reporter = _container(api, player).read(watchHistoryProvider);

    await _start(reporter, player, 'item-1');
    await reporter.close();
    await reporter.close();
    await player.pause();

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

      await _start(reporter, player, 'item-1');
      await player.seek(const Duration(minutes: 20));
      await reporter.flush(); // a progress tick, lost
      await reporter.close(); // the stop, kept
      await player.pause();

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

      await _start(reporter, player, 'item-1');
      await player.seek(const Duration(minutes: 10));
      await reporter.close();

      await _start(reporter, player, 'item-1');
      await player.seek(const Duration(minutes: 40));
      await reporter.close();
      await player.pause();

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

    test(
      'pending drain and a new offline stop cannot overwrite each other',
      () async {
        final pending = PlaybackReport(
          itemId: 'item-old',
          positionTicks: PlaybackReport.ticksOf(const Duration(minutes: 10)),
        );
        SharedPreferences.setMockInitialValues({
          kWatchHistoryQueueKey: [jsonEncode(pending.toJson())],
        });
        final offline = _GatedOfflineApi();
        final player = MockPlayerController();
        final reporter = _container(offline, player).read(watchHistoryProvider);
        await _start(reporter, player, 'item-new');

        final drainGate = offline.gateNext();
        final drain = reporter.drainPending();
        await drainGate.arrived.future;
        final close = reporter.close();
        await Future<void>.delayed(Duration.zero);
        final arrivalsBeforeRelease = offline.arrivals.length;
        drainGate.release.complete();
        await Future.wait([drain, close]);

        expect(arrivalsBeforeRelease, 2);
        final prefs = await SharedPreferences.getInstance();
        final queue = prefs.getStringList(kWatchHistoryQueueKey)!;
        expect(queue, hasLength(2));
        expect(queue.join(), contains('item-old'));
        expect(queue.join(), contains('item-new'));
        await player.pause();
      },
    );

    test('the queue is bounded', () async {
      final offline = _OfflineApi();
      final player = MockPlayerController();
      final reporter = _container(offline, player).read(watchHistoryProvider);

      for (var i = 0; i < kWatchHistoryQueueLimit + 20; i++) {
        await _start(reporter, player, 'item-$i');
        await reporter.close();
      }
      await player.pause();

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
    expect(
      PlaybackReport.durationOf(PlaybackReport.ticksOf(position)),
      position,
    );
  });
}
