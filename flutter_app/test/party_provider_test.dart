import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/data/api_client.dart';
import 'package:watchparty/data/mock_api_client.dart';
import 'package:watchparty/livekit/livekit_room.dart';
import 'package:watchparty/net/events.dart';
import 'package:watchparty/net/socket_client.dart';
import 'package:watchparty/player/player_controller.dart';
import 'package:watchparty/state/state.dart';
import 'package:watchparty/sync/sync_engine_impl.dart';

/// No-op A/V room — real `LiveKitRoomService.connect` drives an actual
/// `livekit_client` room/network handshake, which these party-lifecycle
/// tests don't need and shouldn't depend on being reachable.
class _NoopLiveKitRoomService extends LiveKitRoomService {
  @override
  Future<void> connect(String url, String token,
      {bool enableMic = true, bool enableCamera = true}) async {}

  @override
  Future<void> disconnect() async {}
}

/// A socket whose acks are scripted per-event, so `party:create`/`party:join`
/// can be exercised without a real server.
class _ScriptedSocket extends MockSocketClient {
  final Map<String, dynamic> Function(String event, Object? data) responder;
  _ScriptedSocket(this.responder);

  @override
  Future<dynamic> emitWithAck(String event, [Object? data]) async {
    emitted.add((event, data));
    return responder(event, data);
  }
}

/// Minimal no-op [PlayerController] — the sync engine only needs a `playing`
/// stream and synchronous position getters to attach without throwing.
class _NoopPlayer implements PlayerController {
  @override
  Future<void> open(String url, {Duration startAt = Duration.zero, bool autoplay = false}) async {}
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> setRate(double rate) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> setAudioTrack(String? trackId) async {}
  @override
  Future<void> setSubtitle(String? trackId) async {}
  @override
  Future<void> dispose() async {}
  @override
  Stream<Duration> get position => const Stream.empty();
  @override
  Stream<Duration> get duration => const Stream.empty();
  @override
  Stream<bool> get buffering => const Stream.empty();
  @override
  Stream<bool> get playing => const Stream.empty();
  @override
  Stream<bool> get completed => const Stream.empty();
  @override
  Stream<PlayerTracks> get tracks => const Stream.empty();
  @override
  Duration get positionNow => Duration.zero;
  @override
  Duration get durationNow => Duration.zero;
  @override
  bool get isPlayingNow => false;
  @override
  bool get isBufferingNow => false;
}

/// An [ApiClient] whose `livekitToken` never resolves usefully (party flows
/// treat A/V as best-effort), keeping these tests focused on party/host logic.
class _StubApiClient extends MockApiClient {
  @override
  Future<LiveKitToken> livekitToken(String partyId) async =>
      const LiveKitToken(token: 't', url: 'ws://mock');
}

Map<String, dynamic> _session({
  required String hostId,
  String hostName = 'Host',
  bool collaborativeControl = false,
  List<Map<String, dynamic>> guests = const [],
}) =>
    {
      'id': 'party-1',
      'hostId': hostId,
      'hostName': hostName,
      'stage': 'lobby',
      'collaborativeControl': collaborativeControl,
      'syncMode': 'hopping',
      'guests': guests,
      'schedule': {},
      'browse': {'stack': []},
      'waiting': [],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _ScriptedSocket socket;
  late ProviderContainer container;

  ProviderContainer build(String myUserId, Map<String, dynamic> Function(String, Object?) responder) {
    socket = _ScriptedSocket(responder);
    final c = ProviderContainer(overrides: [
      socketClientProvider.overrideWithValue(socket),
      apiClientProvider.overrideWithValue(_StubApiClient()),
      playerControllerProvider.overrideWithValue(_NoopPlayer()),
      livekitRoomServiceProvider.overrideWithValue(_NoopLiveKitRoomService()),
      currentUserIdProvider.overrideWithValue(myUserId),
    ]);
    addTearDown(() async {
      await c.read(syncEngineProvider).detach();
      c.dispose();
    });
    return c;
  }

  test('create() makes the creator host: isHost/canControl true, wired onto the engine', () async {
    container = build('host1', (event, data) {
      if (event == ClientEvent.partyCreate) {
        return {'partyId': 'party-1', 'session': _session(hostId: 'host1')};
      }
      return {'ok': true};
    });

    final notifier = container.read(partyProvider.notifier);
    final partyId = await notifier.create();

    expect(partyId, 'party-1');
    expect(notifier.isHost, isTrue);
    expect(notifier.canControl, isTrue);

    final engine = container.read(syncEngineProvider) as SyncEngineImpl;
    expect(engine.isHost, isTrue);
    expect(engine.canControl, isTrue);
  });

  test('join() as a guest with collaborativeControl off: not host, canControl false', () async {
    container = build('guest1', (event, data) {
      if (event == ClientEvent.partyJoin) {
        return {'status': 'joined', 'session': _session(hostId: 'host1', collaborativeControl: false)};
      }
      return {'ok': true};
    });

    final notifier = container.read(partyProvider.notifier);
    final status = await notifier.join('party-1');

    expect(status, 'joined');
    expect(notifier.isHost, isFalse);
    expect(notifier.canControl, isFalse);

    final engine = container.read(syncEngineProvider) as SyncEngineImpl;
    expect(engine.isHost, isFalse);
    expect(engine.canControl, isFalse);
  });

  test('join() waiting for approval only fully attaches after party:approved', () async {
    container = build('guest1', (event, data) {
      if (event == ClientEvent.partyJoin) return {'status': 'waiting'};
      return {'ok': true};
    });

    final notifier = container.read(partyProvider.notifier);
    final status = await notifier.join('party-1');

    expect(status, 'waiting');
    expect(container.read(partyProvider), isNull);
    expect((container.read(syncEngineProvider) as SyncEngineImpl).canControl, isFalse);

    // Host approves — the server pushes party:approved with the session.
    socket.inject(
        ServerEvent.partyApproved, {'session': _session(hostId: 'host1', collaborativeControl: true)});
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(container.read(partyProvider), isNotNull);
    expect(notifier.canControl, isTrue); // collaborative control granted on entry
    final engine = container.read(syncEngineProvider) as SyncEngineImpl;
    expect(engine.canControl, isTrue);
    expect(engine.isHost, isFalse);
  });

  test('setCollaborative(true) flips a guest\'s canControl without a host role', () async {
    container = build('guest1', (event, data) {
      if (event == ClientEvent.partyJoin) {
        return {'status': 'joined', 'session': _session(hostId: 'host1', collaborativeControl: false)};
      }
      return {'ok': true};
    });

    final notifier = container.read(partyProvider.notifier);
    await notifier.join('party-1');
    expect(notifier.canControl, isFalse);

    await notifier.setCollaborative(true);

    expect(notifier.canControl, isTrue);
    expect(notifier.isHost, isFalse);
    final engine = container.read(syncEngineProvider) as SyncEngineImpl;
    expect(engine.canControl, isTrue);
    expect(engine.isHost, isFalse);
  });

  test('host:changed transfers host authority to the engine', () async {
    container = build('guest1', (event, data) {
      if (event == ClientEvent.partyJoin) {
        return {'status': 'joined', 'session': _session(hostId: 'host1')};
      }
      return {'ok': true};
    });

    final notifier = container.read(partyProvider.notifier);
    await notifier.join('party-1');
    expect(notifier.isHost, isFalse);

    socket.inject(ServerEvent.hostChanged, {'hostId': 'guest1'});

    expect(notifier.isHost, isTrue);
    expect(notifier.canControl, isTrue);
    final engine = container.read(syncEngineProvider) as SyncEngineImpl;
    expect(engine.isHost, isTrue);
    expect(engine.canControl, isTrue);
  });

  test('end() (host) detaches the engine and clears local party state', () async {
    container = build('host1', (event, data) {
      if (event == ClientEvent.partyCreate) {
        return {'partyId': 'party-1', 'session': _session(hostId: 'host1')};
      }
      return {'ok': true};
    });

    final notifier = container.read(partyProvider.notifier);
    await notifier.create();
    expect(container.read(partyProvider), isNotNull);

    await notifier.end();

    expect(container.read(partyProvider), isNull);
    expect(socket.isConnected, isFalse);
    final engine = container.read(syncEngineProvider) as SyncEngineImpl;
    expect(engine.isHost, isFalse);
  });
}
