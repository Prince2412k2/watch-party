import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/cache/media_cache_proxy.dart';
import 'package:watchparty/data/api_client.dart';
import 'package:watchparty/data/mock_api_client.dart';
import 'package:watchparty/livekit/livekit_room.dart';
import 'package:watchparty/models/party_state.dart';
import 'package:watchparty/net/events.dart';
import 'package:watchparty/net/socket_client.dart';
import 'package:watchparty/player/player_controller.dart';
import 'package:watchparty/state/state.dart';

/// No-op A/V room — real `LiveKitRoomService.connect` drives an actual
/// `livekit_client` room/network handshake, which these party-lifecycle
/// tests don't need and shouldn't depend on being reachable.
class _NoopLiveKitRoomService extends LiveKitRoomService {
  @override
  Future<void> connect(
    String url,
    String token, {
    bool enableMic = true,
    bool enableCamera = true,
  }) async {}

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

class _NeverAckEndSocket extends MockSocketClient {
  @override
  Future<dynamic> emitWithAck(String event, [Object? data]) {
    if (event == ClientEvent.partyEnd) return Completer<dynamic>().future;
    return super.emitWithAck(event, data);
  }
}

/// Minimal no-op [PlayerController] used to prove party events never touch it.
class _NoopPlayer implements PlayerController {
  int openCalls = 0;
  int pauseCalls = 0;
  String? lastOpenedUrl;

  @override
  Future<void> open(
    String url, {
    Duration startAt = Duration.zero,
    bool autoplay = false,
  }) async {
    openCalls++;
    lastOpenedUrl = url;
  }

  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async => pauseCalls++;
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

class _GatedTokenApi extends _StubApiClient {
  final token = Completer<LiveKitToken>();

  @override
  Future<LiveKitToken> livekitToken(String partyId) => token.future;
}

class _RecordingLiveKitRoomService extends _NoopLiveKitRoomService {
  int connectCalls = 0;

  @override
  Future<void> connect(
    String url,
    String token, {
    bool enableMic = true,
    bool enableCamera = true,
  }) async {
    connectCalls++;
  }
}

Map<String, dynamic> _session({
  required String hostId,
  String hostName = 'Host',
  String stage = 'lobby',
  String? mediaItemId,
  String? mediaSourceId,
  bool collaborativeControl = false,
  String syncMode = 'hopping',
  List<Map<String, dynamic>> guests = const [],
  Map<String, dynamic>? playback,
  Map<String, dynamic>? subtitlePreferences,
  List<Map<String, dynamic>> waiting = const [],
}) => {
  'id': 'party-1',
  'hostId': hostId,
  'hostName': hostName,
  'stage': stage,
  'mediaItemId': mediaItemId,
  'mediaSourceId': mediaSourceId,
  'collaborativeControl': collaborativeControl,
  'syncMode': syncMode,
  'guests': guests,
  'schedule': {},
  'browse': {'stack': []},
  'waiting': waiting,
  'playback': playback,
  'subtitlePreferences': subtitlePreferences,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _ScriptedSocket socket;
  late ProviderContainer container;
  late _NoopPlayer player;

  ProviderContainer build(
    String myUserId,
    Map<String, dynamic> Function(String, Object?) responder, {
    MediaCacheProxy? proxy,
    _NoopPlayer? withPlayer,
    ApiClient? api,
    LiveKitRoomService? livekit,
  }) {
    socket = _ScriptedSocket(responder);
    player = withPlayer ?? _NoopPlayer();
    final c = ProviderContainer(
      overrides: [
        socketClientProvider.overrideWithValue(socket),
        apiClientProvider.overrideWithValue(api ?? _StubApiClient()),
        playerControllerProvider.overrideWithValue(player),
        if (proxy != null) mediaCacheProxyProvider.overrideWithValue(proxy),
        livekitRoomServiceProvider.overrideWithValue(
          livekit ?? _NoopLiveKitRoomService(),
        ),
        currentUserIdProvider.overrideWithValue(myUserId),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('create() makes the creator host', () async {
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
  });

  test('resume restores a host party and its waiting requests', () async {
    container = build('host1', (event, data) {
      if (event == ClientEvent.partyResume) {
        return {
          'session': _session(
            hostId: 'host1',
            waiting: const [
              {'userId': 'guest1', 'name': 'Guest'},
            ],
          ),
        };
      }
      return {'ok': true};
    });

    final resumed = await container.read(partyProvider.notifier).resume();

    expect(resumed, isTrue);
    expect(container.read(partyProvider)?.hostId, 'host1');
    expect(container.read(partyWaitingProvider).single.userId, 'guest1');
  });

  test('socket reconnect refreshes the host waiting snapshot', () async {
    var waiting = const <Map<String, dynamic>>[];
    container = build('host1', (event, data) {
      if (event == ClientEvent.partyCreate) {
        return {'partyId': 'party-1', 'session': _session(hostId: 'host1')};
      }
      if (event == ClientEvent.partyResume) {
        return {'session': _session(hostId: 'host1', waiting: waiting)};
      }
      return {'ok': true};
    });
    final notifier = container.read(partyProvider.notifier);
    await notifier.create();
    waiting = const [
      {'userId': 'guest1', 'name': 'Guest'},
    ];

    await socket.disconnect();
    await socket.connect();
    await Future<void>.delayed(Duration.zero);

    expect(container.read(partyWaitingProvider).single.userId, 'guest1');
    expect(
      socket.emitted.where((entry) => entry.$1 == ClientEvent.partyResume),
      isNotEmpty,
    );
  });

  test(
    'waiting guest repeats join with its new socket after reconnect',
    () async {
      var joinCount = 0;
      container = build('guest1', (event, data) {
        if (event == ClientEvent.partyJoin) {
          joinCount++;
          return {'status': 'waiting'};
        }
        return {'ok': true};
      });
      final notifier = container.read(partyProvider.notifier);
      await notifier.join('party-1');

      await socket.disconnect();
      await socket.connect();
      await Future<void>.delayed(Duration.zero);

      expect(joinCount, 2);
      expect(socket.emitted.last.$2, {'partyId': 'party-1'});
    },
  );

  test('starting a party while watching does not attach the movie', () async {
    container = build('host1', (event, data) {
      if (event == ClientEvent.partyCreate) {
        return {
          'partyId': 'party-1',
          'session': _session(
            hostId: 'host1',
            stage: 'watching',
            mediaItemId: 'episode-1',
            mediaSourceId: 'source-1',
          ),
        };
      }
      return {'ok': true};
    });

    await container.read(partyProvider.notifier).create();

    expect(player.openCalls, 0);
    final create = socket.emitted.firstWhere(
      (entry) => entry.$1 == ClientEvent.partyCreate,
    );
    expect(create.$2, isEmpty);
  });

  test('join() identifies a guest without owning playback', () async {
    container = build('guest1', (event, data) {
      if (event == ClientEvent.partyJoin) {
        return {
          'status': 'joined',
          'session': _session(hostId: 'host1', collaborativeControl: false),
        };
      }
      return {'ok': true};
    });

    final notifier = container.read(partyProvider.notifier);
    final status = await notifier.join('party-1');

    expect(status, 'joined');
    expect(notifier.isHost, isFalse);
  });

  test('joining a watching room does not open the host movie', () async {
    container = build('guest1', (event, data) {
      if (event == ClientEvent.partyJoin) {
        return {
          'status': 'joined',
          'session': _session(
            hostId: 'web-host',
            stage: 'watching',
            mediaItemId: 'movie-1',
            mediaSourceId: 'source-4k',
          ),
        };
      }
      return {'ok': true};
    });

    await container.read(partyProvider.notifier).join('party-1');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(player.openCalls, 0);
    expect(player.lastOpenedUrl, isNull);
  });

  test('leaving during token fetch cannot reconnect A/V', () async {
    final api = _GatedTokenApi();
    final livekit = _RecordingLiveKitRoomService();
    container = build(
      'guest1',
      (event, data) {
        if (event == ClientEvent.partyJoin) {
          return {'status': 'joined', 'session': _session(hostId: 'host1')};
        }
        return {'ok': true};
      },
      api: api,
      livekit: livekit,
    );

    final joining = container.read(partyProvider.notifier).join('party-1');
    await Future<void>.delayed(Duration.zero);
    await container.read(partyProvider.notifier).leave();
    api.token.complete(const LiveKitToken(token: 't', url: 'ws://mock'));

    await expectLater(joining, throwsStateError);
    expect(container.read(partyProvider), isNull);
    expect(livekit.connectCalls, 0);
  });

  test(
    'join() waiting for approval only fully attaches after party:approved',
    () async {
      container = build('guest1', (event, data) {
        if (event == ClientEvent.partyJoin) return {'status': 'waiting'};
        return {'ok': true};
      });

      final notifier = container.read(partyProvider.notifier);
      final status = await notifier.join('party-1');

      expect(status, 'waiting');
      expect(container.read(partyProvider), isNull);

      // Host approves — the server pushes party:approved with the session.
      socket.inject(ServerEvent.partyApproved, {
        'session': _session(hostId: 'host1', collaborativeControl: true),
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(container.read(partyProvider), isNotNull);
    },
  );

  test('host:changed updates host authority', () async {
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
  });

  test('session snapshots deduplicate participant identities', () async {
    container = build('host1', (event, data) {
      if (event == ClientEvent.partyCreate) {
        return {
          'partyId': 'party-1',
          'session': _session(
            hostId: 'host1',
            guests: const [
              {'userId': 'guest1', 'name': 'Guest'},
              {'userId': 'guest1', 'name': 'Guest'},
              {'userId': 'host1', 'name': 'Host duplicate'},
            ],
          ),
        };
      }
      return {'ok': true};
    });

    await container.read(partyProvider.notifier).create();

    expect(container.read(partyProvider)!.participants.map((p) => p.userId), [
      'host1',
      'guest1',
    ]);
  });

  test('end() clears local party state', () async {
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
  });

  test(
    'end() clears local state when the server does not acknowledge',
    () async {
      final hangingSocket = _NeverAckEndSocket();
      final localContainer = ProviderContainer(
        overrides: [
          socketClientProvider.overrideWithValue(hangingSocket),
          livekitRoomServiceProvider.overrideWithValue(
            _NoopLiveKitRoomService(),
          ),
          currentUserIdProvider.overrideWithValue('host1'),
          partyProvider.overrideWith(
            (ref) => PartyNotifier(
              ref,
              ackTimeout: const Duration(milliseconds: 10),
            ),
          ),
        ],
      );
      addTearDown(localContainer.dispose);
      final notifier = localContainer.read(partyProvider.notifier);
      notifier.setState(const PartyState(id: 'party-1', hostId: 'host1'));

      await expectLater(notifier.end(), throwsA(isA<TimeoutException>()));

      expect(localContainer.read(partyProvider), isNull);
    },
  );

  test('party:ended clears the room without stopping local playback', () async {
    container = build('guest1', (event, data) {
      if (event == ClientEvent.partyJoin) {
        return {'status': 'joined', 'session': _session(hostId: 'web-host')};
      }
      return {'ok': true};
    });
    await container.read(partyProvider.notifier).join('party-1');

    socket.inject(ServerEvent.partyEnded, const {});
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(player.pauseCalls, 0);
    expect(container.read(partyProvider), isNull);
    expect(socket.isConnected, isFalse);
  });
}
