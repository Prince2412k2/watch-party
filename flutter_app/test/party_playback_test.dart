// The rules that make a party a watch party rather than two people playing the
// same file. See lib/state/party_playback.dart.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/data/mock_api_client.dart';
import 'package:watchparty/models/models.dart';
import 'package:watchparty/net/events.dart';
import 'package:watchparty/net/socket_client.dart';
import 'package:watchparty/player/mock_player_controller.dart';
import 'package:watchparty/state/state.dart';
import 'package:watchparty/sync/sync_engine.dart';
import 'package:watchparty/sync/sync_engine_impl.dart';

class _FakeEngine implements SyncEngine {
  int attachCount = 0;
  int detachCount = 0;
  String? partyId;
  bool _canControl = false;
  final seeks = <Duration>[];
  int plays = 0;
  int pauses = 0;

  @override
  Future<void> attach({
    required player,
    required socket,
    required String partyId,
    required bool canControl,
  }) async {
    attachCount++;
    this.partyId = partyId;
    _canControl = canControl;
  }

  @override
  Future<void> detach() async => detachCount++;

  @override
  bool get canControl => _canControl;

  @override
  set canControl(bool value) => _canControl = value;

  @override
  Future<void> requestPlay() async => plays++;

  @override
  Future<void> requestPause() async => pauses++;

  @override
  Future<void> requestSeek(Duration position) async => seeks.add(position);

  @override
  SyncSchedule get currentSchedule => const SyncSchedule();

  @override
  Stream<SyncSchedule> get scheduleStream => const Stream.empty();

  @override
  Stream<Duration> get drift => const Stream.empty();

  @override
  Stream<CatchUp> get catchUp => const Stream.empty();
}

class _WatchedApi extends MockApiClient {
  @override
  Future<LibraryItem> item(String id) async => LibraryItem(
    id: id,
    name: 'Watched',
    type: 'Movie',
    userData: const UserItemData(playbackPositionTicks: 45000000),
  );
}

class _GatedItemApi extends MockApiClient {
  final requests = <String, Completer<LibraryItem>>{};

  @override
  Future<LibraryItem> item(String id) =>
      (requests[id] ??= Completer<LibraryItem>()).future;

  void complete(String id, {int ticks = 0}) {
    requests[id]!.complete(
      LibraryItem(
        id: id,
        name: id,
        type: 'Movie',
        userData: UserItemData(playbackPositionTicks: ticks),
      ),
    );
  }
}

({ProviderContainer container, _FakeEngine engine}) _boot({
  required String me,
  required String hostId,
  bool collaborative = false,
  String? watching,
  MockApiClient? api,
}) {
  final engine = _FakeEngine();
  final container = ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(api ?? MockApiClient()),
      socketClientProvider.overrideWithValue(MockSocketClient()),
      playerControllerProvider.overrideWithValue(MockPlayerController()),
      syncEngineProvider.overrideWithValue(engine),
      authProvider.overrideWith((ref) {
        final notifier = AuthNotifier(ref);
        notifier.state = AuthState(
          user: User(userId: me, name: me),
          initialized: true,
        );
        return notifier;
      }),
    ],
  );
  // Reading it is what starts it — PlayerHost does the same at the root.
  container.read(partyPlaybackProvider);
  container
      .read(partyProvider.notifier)
      .setState(
        PartyState(
          id: 'room-1',
          hostId: hostId,
          mediaItemId: watching,
          collaborativeControl: collaborative,
        ),
      );
  return (container: container, engine: engine);
}

void _watch(
  ProviderContainer container,
  String? itemId, {
  PlaybackInfo? playback,
}) {
  final party = container.read(partyProvider)!;
  container
      .read(partyProvider.notifier)
      .setState(
        PartyState(
          id: party.id,
          hostId: party.hostId,
          mediaItemId: itemId,
          collaborativeControl: party.collaborativeControl,
          playback: playback,
        ),
      );
}

void main() {
  test('a guest is pulled into the host\'s film, full-window', () {
    final (:container, :engine) = _boot(me: 'guest', hostId: 'host');
    addTearDown(container.dispose);
    expect(container.read(nowPlayingProvider).isOpen, isFalse);

    _watch(container, 'film-1');

    final now = container.read(nowPlayingProvider);
    expect(now.itemId, 'film-1');
    expect(now.isExpanded, isTrue);
    // ...and the room now drives their player, which is the whole point.
    expect(engine.attachCount, 1);
    expect(engine.partyId, 'room-1');
    expect(engine.canControl, isFalse, reason: 'a guest is a passenger');
  });

  test('switching titles lands where the guest is already watching', () {
    final (:container, :engine) = _boot(me: 'guest', hostId: 'host');
    addTearDown(container.dispose);

    _watch(container, 'film-1');
    // They put it in the corner and went back to browsing.
    container.read(nowPlayingProvider.notifier).minimise();
    expect(container.read(nowPlayingProvider).isFloating, isTrue);

    _watch(container, 'film-2');

    final now = container.read(nowPlayingProvider);
    expect(now.itemId, 'film-2');
    expect(
      now.isFloating,
      isTrue,
      reason: 'a title change must not yank the screen back off them',
    );
    // Announced, so the swap is not a black rectangle they did not ask for.
    expect(container.read(nowPlayingIntroProvider), 'film-2');
  });

  test('party audio changes preserve local subtitles without reopening', () {
    final (:container, :engine) = _boot(me: 'guest', hostId: 'host');
    addTearDown(container.dispose);

    _watch(container, 'film-1');
    container.read(nowPlayingProvider.notifier).setSubtitleStreamIndex(9);
    final before = container.read(nowPlayingProvider);
    expect(before.revision, 1);
    expect(engine.attachCount, 1);

    _watch(
      container,
      'film-1',
      playback: const PlaybackInfo(
        selectedAudioIndex: 2,
        selectedSubtitleIndex: 7,
      ),
    );

    final after = container.read(nowPlayingProvider);
    expect(after.itemId, 'film-1');
    expect(after.audioStreamIndex, 2);
    expect(after.subtitleStreamIndex, 9);
    expect(after.revision, before.revision);
    expect(engine.attachCount, 1);
  });

  test('the host taking the film away closes it for a guest', () {
    final (:container, :engine) = _boot(me: 'guest', hostId: 'host');
    addTearDown(container.dispose);

    _watch(container, 'film-1');
    expect(container.read(nowPlayingProvider).isOpen, isTrue);

    _watch(container, null);

    expect(container.read(nowPlayingProvider).isOpen, isFalse);
    expect(engine.detachCount, greaterThanOrEqualTo(1));
  });

  test(
    'a passenger cannot close, a driver can, and it closes the room',
    () async {
      final guest = _boot(me: 'guest', hostId: 'host', watching: 'film-1');
      addTearDown(guest.container.dispose);
      final playback = guest.container.read(partyPlaybackProvider);

      expect(playback.canClose, isFalse);
      expect(playback.canDrive, isFalse);
      await playback.close();
      expect(
        guest.container.read(nowPlayingProvider).isOpen,
        isTrue,
        reason: 'a guest closing the room\'s film must be a no-op',
      );

      final host = _boot(me: 'host', hostId: 'host', watching: 'film-1');
      addTearDown(host.container.dispose);
      final hostPlayback = host.container.read(partyPlaybackProvider);
      final socket =
          host.container.read(socketClientProvider) as MockSocketClient;

      expect(hostPlayback.canClose, isTrue);
      await hostPlayback.close();
      // Not a local close: the room is told, and everyone's follow path does it.
      expect(
        socket.emitted.map((e) => e.$1),
        contains(ClientEvent.partyBackToLobby),
      );
    },
  );

  test('collaborative control promotes a guest to driver', () {
    final (:container, :engine) = _boot(
      me: 'guest',
      hostId: 'host',
      collaborative: true,
      watching: 'film-1',
    );
    addTearDown(container.dispose);

    final playback = container.read(partyPlaybackProvider);
    expect(playback.canDrive, isTrue);
    expect(engine.canControl, isTrue);

    playback.reportSeek(const Duration(minutes: 3));
    expect(engine.seeks, [const Duration(minutes: 3)]);
  });

  test('a driver sends the fresh resume position to the room', () async {
    final (:container, :engine) = _boot(
      me: 'host',
      hostId: 'host',
      api: _WatchedApi(),
    );
    addTearDown(container.dispose);

    final outcome = await container
        .read(partyPlaybackProvider)
        .requestOpen(itemId: 'film-1');
    final socket = container.read(socketClientProvider) as MockSocketClient;
    final payload =
        socket.emitted
                .firstWhere((event) => event.$1 == ClientEvent.partySelectMedia)
                .$2
            as Map;

    expect(outcome, OpenOutcome.sentToRoom);
    expect(payload['resumePositionTicks'], 45000000);
    expect(engine.attachCount, 0);
  });

  test('party playback forwards canonical track selections', () {
    final (:container, :engine) = _boot(me: 'guest', hostId: 'host');
    addTearDown(container.dispose);
    _watch(
      container,
      'film-1',
      playback: const PlaybackInfo(
        selectedAudioIndex: 2,
        selectedSubtitleIndex: 4,
      ),
    );

    final now = container.read(nowPlayingProvider);
    expect(now.audioStreamIndex, 2);
    expect(now.subtitleStreamIndex, 4);
    expect(engine.attachCount, 1);
  });

  test('same-title party updates keep the viewer subtitle selection', () {
    final (:container, :engine) = _boot(me: 'guest', hostId: 'host');
    addTearDown(container.dispose);
    _watch(
      container,
      'film-1',
      playback: const PlaybackInfo(
        selectedAudioIndex: 2,
        selectedSubtitleIndex: 4,
      ),
    );
    container.read(nowPlayingProvider.notifier).minimise();
    container.read(nowPlayingProvider.notifier).setSubtitleStreamIndex(9);
    container.read(nowPlayingIntroProvider.notifier).state = null;
    final revision = container.read(nowPlayingProvider).revision;

    _watch(
      container,
      'film-1',
      playback: const PlaybackInfo(
        selectedAudioIndex: 5,
        selectedSubtitleIndex: -1,
      ),
    );

    final now = container.read(nowPlayingProvider);
    expect(now.audioStreamIndex, 5);
    expect(now.subtitleStreamIndex, 9);
    expect(
      now.revision,
      revision,
      reason: 'track-only changes must not trigger a native reopen',
    );
    expect(now.isFloating, isTrue);
    expect(container.read(nowPlayingIntroProvider), isNull);
    expect(engine.attachCount, 1);
  });

  test('only the host can author canonical audio tracks', () async {
    final host = _boot(me: 'host', hostId: 'host', watching: 'film-1');
    final guest = _boot(
      me: 'guest',
      hostId: 'host',
      collaborative: true,
      watching: 'film-1',
    );
    addTearDown(host.container.dispose);
    addTearDown(guest.container.dispose);

    expect(host.container.read(partyPlaybackProvider).canManageAudio, isTrue);
    expect(guest.container.read(partyPlaybackProvider).canManageAudio, isFalse);
    await host.container.read(partyPlaybackProvider).selectAudioStream(8);

    final hostSocket =
        host.container.read(socketClientProvider) as MockSocketClient;
    final guestSocket =
        guest.container.read(socketClientProvider) as MockSocketClient;
    expect(
      hostSocket.emitted.map((event) => event.$1),
      contains(ClientEvent.partySetPlaybackTracks),
    );
    final trackPayloads = hostSocket.emitted
        .where((event) => event.$1 == ClientEvent.partySetPlaybackTracks)
        .map((event) => event.$2)
        .toList();
    expect(trackPayloads, [
      {'audioStreamIndex': 8},
    ]);
    expect(
      guestSocket.emitted.map((event) => event.$1),
      isNot(contains(ClientEvent.partySetPlaybackTracks)),
    );
  });

  test('a pending open cannot select media in a replacement party', () async {
    final api = _GatedItemApi();
    final (:container, :engine) = _boot(me: 'host', hostId: 'host', api: api);
    addTearDown(container.dispose);
    final request = container
        .read(partyPlaybackProvider)
        .requestOpen(itemId: 'film-1');
    await Future<void>.delayed(Duration.zero);
    container
        .read(partyProvider.notifier)
        .setState(const PartyState(id: 'room-2', hostId: 'host'));
    api.complete('film-1', ticks: 45000000);

    expect(await request, OpenOutcome.superseded);
    final socket = container.read(socketClientProvider) as MockSocketClient;
    expect(
      socket.emitted.map((event) => event.$1),
      isNot(contains(ClientEvent.partySelectMedia)),
    );
    expect(engine.attachCount, 0);
  });

  test('only the latest pending open reaches the room', () async {
    final api = _GatedItemApi();
    final (:container, :engine) = _boot(me: 'host', hostId: 'host', api: api);
    addTearDown(container.dispose);
    final playback = container.read(partyPlaybackProvider);
    final first = playback.requestOpen(itemId: 'film-1');
    final second = playback.requestOpen(itemId: 'film-2');
    await Future<void>.delayed(Duration.zero);

    api.complete('film-2');
    expect(await second, OpenOutcome.sentToRoom);
    api.complete('film-1');
    expect(await first, OpenOutcome.superseded);

    final socket = container.read(socketClientProvider) as MockSocketClient;
    final selections = socket.emitted
        .where((event) => event.$1 == ClientEvent.partySelectMedia)
        .map((event) => event.$2 as Map)
        .toList();
    expect(selections, [containsPair('mediaItemId', 'film-2')]);
    expect(engine.attachCount, 0);
  });

  test('party transport uses the sync engine for play and pause', () async {
    final (:container, :engine) = _boot(
      me: 'host',
      hostId: 'host',
      watching: 'film-1',
    );
    addTearDown(container.dispose);
    final player = container.read(playerControllerProvider);
    final playback = container.read(partyPlaybackProvider);

    await playback.togglePlay();
    expect(engine.plays, 1);
    await player.play();
    await playback.togglePlay();
    expect(engine.pauses, 1);
  });

  test('a passenger\'s seek is never published', () {
    final (:container, :engine) = _boot(
      me: 'guest',
      hostId: 'host',
      watching: 'film-1',
    );
    addTearDown(container.dispose);

    container
        .read(partyPlaybackProvider)
        .reportSeek(const Duration(minutes: 3));
    expect(engine.seeks, isEmpty);
  });

  test('solo playback opens locally and never engages the engine', () async {
    final engine = _FakeEngine();
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(MockApiClient()),
        socketClientProvider.overrideWithValue(MockSocketClient()),
        playerControllerProvider.overrideWithValue(MockPlayerController()),
        syncEngineProvider.overrideWithValue(engine),
      ],
    );
    addTearDown(container.dispose);
    final playback = container.read(partyPlaybackProvider);

    expect(playback.role, PartyRole.solo);
    expect(await playback.requestOpen(itemId: 'film-9'), OpenOutcome.opened);
    expect(container.read(nowPlayingProvider).itemId, 'film-9');
    expect(engine.attachCount, 0);
  });

  test('the sync engine provider disposes its engine', () async {
    final container = ProviderContainer();
    final engine = container.read(syncEngineProvider) as SyncEngineImpl;

    container.dispose();
    await Future<void>.delayed(Duration.zero);

    expect(engine.isDisposed, isTrue);
  });
}
