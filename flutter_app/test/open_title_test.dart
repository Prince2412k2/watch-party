import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/data/mock_api_client.dart';
import 'package:watchparty/models/models.dart';
import 'package:watchparty/player/mock_player_controller.dart';
import 'package:watchparty/player/open_title.dart';
import 'package:watchparty/state/state.dart';

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

  @override
  Future<void> open(
    String url, {
    Duration startAt = Duration.zero,
    bool autoplay = false,
  }) async {
    opened.add(url);
    await super.open(url, startAt: startAt, autoplay: autoplay);
  }
}

void main() {
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
