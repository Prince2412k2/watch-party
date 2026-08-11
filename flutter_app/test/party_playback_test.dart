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

class _FakeEngine implements SyncEngine {
  int attachCount = 0;
  int detachCount = 0;
  String? partyId;
  bool _canControl = false;
  final seeks = <Duration>[];

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
  Future<void> requestPlay() async {}

  @override
  Future<void> requestPause() async {}

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

({ProviderContainer container, _FakeEngine engine}) _boot({
  required String me,
  required String hostId,
  bool collaborative = false,
  String? watching,
}) {
  final engine = _FakeEngine();
  final container = ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(MockApiClient()),
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

void _watch(ProviderContainer container, String? itemId) {
  final party = container.read(partyProvider)!;
  container
      .read(partyProvider.notifier)
      .setState(
        PartyState(
          id: party.id,
          hostId: party.hostId,
          mediaItemId: itemId,
          collaborativeControl: party.collaborativeControl,
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

  test('the host taking the film away closes it for a guest', () {
    final (:container, :engine) = _boot(me: 'guest', hostId: 'host');
    addTearDown(container.dispose);

    _watch(container, 'film-1');
    expect(container.read(nowPlayingProvider).isOpen, isTrue);

    _watch(container, null);

    expect(container.read(nowPlayingProvider).isOpen, isFalse);
    expect(engine.detachCount, greaterThanOrEqualTo(1));
  });

  test('a passenger cannot close, a driver can, and it closes the room', () async {
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
  });

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

  test('a passenger\'s seek is never published', () {
    final (:container, :engine) = _boot(
      me: 'guest',
      hostId: 'host',
      watching: 'film-1',
    );
    addTearDown(container.dispose);

    container.read(partyPlaybackProvider).reportSeek(const Duration(minutes: 3));
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
    expect(
      await playback.requestOpen(itemId: 'film-9'),
      OpenOutcome.opened,
    );
    expect(container.read(nowPlayingProvider).itemId, 'film-9');
    expect(engine.attachCount, 0);
  });
}
