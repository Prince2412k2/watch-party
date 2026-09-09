import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/data/mock_api_client.dart';
import 'package:watchparty/models/models.dart';
import 'package:watchparty/player/mock_player_controller.dart';
import 'package:watchparty/player/open_title.dart';
import 'package:watchparty/state/state.dart';
import 'package:watchparty/net/events.dart';
import 'package:watchparty/net/socket_client.dart';
import 'package:watchparty/sync/server_clock.dart';
import 'package:watchparty/sync/sync_engine_impl.dart';

class _GatedPlaybackApi extends MockApiClient {
  final arrived = Completer<void>();
  final release = Completer<void>();

  @override
  Future<PlaybackInfo> playbackInfo(
    String itemId, {
    String? mediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) async {
    arrived.complete();
    await release.future;
    return const PlaybackInfo();
  }
}

class _RecordingPlayer extends MockPlayerController {
  final opened = <String>[];
  Completer<void>? openGate;
  final arrived = Completer<void>();

  @override
  Future<void> open(
    String url, {
    Duration startAt = Duration.zero,
    bool autoplay = false,
  }) async {
    opened.add(url);
    if (!arrived.isCompleted) arrived.complete();
    if (openGate != null) await openGate!.future;
    await super.open(url, startAt: startAt, autoplay: autoplay);
  }
}

void main() {
  for (final phase in ['playing', 'paused', 'stalled']) {
    testWidgets('delayed hopping host open honors latest $phase schedule', (
      tester,
    ) async {
      late _RecordingPlayer player;
      late MockSocketClient socket;
      late SyncEngineImpl engine;
      // Native streams and their close futures must share the real async zone.
      await tester.runAsync(() async {
        player = _RecordingPlayer()..openGate = Completer<void>();
        socket = MockSocketClient();
        engine =
            SyncEngineImpl(
                clock: ManualServerClock(nowMs: () => 2000, ready: true),
              )
              ..isHost = true
              ..syncMode = 'hopping';
      });
      final container = ProviderContainer(
        overrides: [
          playerControllerProvider.overrideWithValue(player),
          socketClientProvider.overrideWithValue(socket),
          syncEngineProvider.overrideWithValue(engine),
        ],
      );
      WidgetRef? widgetRef;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, child) {
                widgetRef = ref;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      container
          .read(partyProvider.notifier)
          .setState(
            const PartyState(id: 'room', hostId: 'host', mediaItemId: 'movie'),
          );
      await tester.runAsync(() async {
        await engine.attach(
          player: player,
          socket: socket,
          partyId: 'room',
          canControl: true,
        );
        final opening = openTitleIntoPlayer(
          widgetRef!,
          player,
          itemId: 'movie',
          isStale: () => false,
        );
        await player.arrived.future.timeout(const Duration(seconds: 5));
        socket.inject(ServerEvent.syncSchedule, {
          'version': 5,
          'mediaGeneration': 0,
          'positionTicks': 420000000,
          't0': 1000,
          'phase': phase,
          'paused': phase != 'playing',
        });
        await Future<void>.delayed(const Duration(seconds: 1));
        expect(player.isPlayingNow, isFalse);
        player.openGate!.complete();
        final result = await opening.timeout(const Duration(seconds: 5));
        expect(result.error, isNull);
        expect(
          player.positionNow,
          Duration(seconds: phase == 'playing' ? 43 : 42),
        );
        expect(player.isPlayingNow, phase == 'playing');
        expect(
          socket.emitted.where(
            (e) =>
                e.$1 == ClientEvent.syncPlay || e.$1 == ClientEvent.syncPause,
          ),
          isEmpty,
        );
        await engine.dispose().timeout(const Duration(seconds: 5));
        await player.dispose().timeout(const Duration(seconds: 5));
      });
      container.dispose();
    });
  }

  testWidgets('a superseded track preselection never opens the old title', (
    tester,
  ) async {
    final api = _GatedPlaybackApi();
    final player = _RecordingPlayer();
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(api),
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
    addTearDown(() async {
      await player.dispose();
      container.dispose();
    });
    WidgetRef? widgetRef;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, child) {
              widgetRef = ref;
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    var stale = false;
    final opening = openTitleIntoPlayer(
      widgetRef!,
      player,
      itemId: 'old-title',
      audioStreamIndex: 1,
      isStale: () => stale,
    );
    await api.arrived.future;
    stale = true;
    api.release.complete();

    expect((await opening).ok, isTrue);
    expect(player.opened, isEmpty);
  });
}
