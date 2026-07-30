import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/cache/media_cache_proxy.dart';
import 'package:watchparty/data/api_client.dart';
import 'package:watchparty/data/mock_api_client.dart';
import 'package:watchparty/livekit/livekit_room.dart';
import 'package:watchparty/models/subtitle_preferences.dart';
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

/// Minimal no-op [PlayerController] — the sync engine only needs a `playing`
/// stream and synchronous position getters to attach without throwing.
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

Map<String, dynamic> _session({
  required String hostId,
  String hostName = 'Host',
  String stage = 'lobby',
  String? mediaItemId,
  String? mediaSourceId,
  bool collaborativeControl = false,
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
  'syncMode': 'hopping',
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
  }) {
    socket = _ScriptedSocket(responder);
    player = _NoopPlayer();
    final c = ProviderContainer(
      overrides: [
        socketClientProvider.overrideWithValue(socket),
        apiClientProvider.overrideWithValue(_StubApiClient()),
        playerControllerProvider.overrideWithValue(player),
        if (proxy != null) mediaCacheProxyProvider.overrideWithValue(proxy),
        livekitRoomServiceProvider.overrideWithValue(_NoopLiveKitRoomService()),
        currentUserIdProvider.overrideWithValue(myUserId),
      ],
    );
    addTearDown(() async {
      await c.read(syncEngineProvider).detach();
      c.dispose();
    });
    return c;
  }

  test(
    'session preserves playback indices and exact subtitle preferences contract',
    () async {
      final preferences = {
        'delayMs': -750,
        'fontScalePercent': 130,
        'verticalPosition': 'middle',
        'fontFamily': 'mono',
        'textColor': '#7fdbff',
        'backgroundOpacityPercent': 40,
      };
      container = build('guest1', (event, data) {
        if (event == ClientEvent.partyJoin) {
          return {
            'status': 'joined',
            'session': _session(
              hostId: 'host1',
              playback: const {
                'mediaSourceId': 'source-1',
                'audioStreams': [],
                'subtitleStreams': [],
                'selectedAudioIndex': 3,
                'selectedSubtitleIndex': -1,
              },
              subtitlePreferences: preferences,
            ),
          };
        }
        return {'ok': true};
      });

      final notifier = container.read(partyProvider.notifier);
      await notifier.join('party-1');

      expect(notifier.playback!.selectedAudioIndex, 3);
      expect(notifier.playback!.selectedSubtitleIndex, -1);
      expect(notifier.subtitlePreferences.toJson(), {
        ...preferences,
        'textColor': '#7FDBFF',
      });
    },
  );

  test(
    'only the host emits canonical track and subtitle preference changes',
    () async {
      container = build('guest1', (event, data) {
        if (event == ClientEvent.partyJoin) {
          return {'status': 'joined', 'session': _session(hostId: 'host1')};
        }
        return {'ok': true};
      });
      final guest = container.read(partyProvider.notifier);
      await guest.join('party-1');
      final before = socket.emitted.length;
      await guest.setPlaybackTracks(
        audioStreamIndex: 2,
        subtitleStreamIndex: -1,
      );
      await guest.setSubtitlePreferences(SubtitlePreferences.defaults);
      expect(socket.emitted.length, before);

      await container.read(syncEngineProvider).detach();
      container = build('host1', (event, data) {
        if (event == ClientEvent.partyCreate) {
          return {'partyId': 'party-1', 'session': _session(hostId: 'host1')};
        }
        return {'ok': true};
      });
      final host = container.read(partyProvider.notifier);
      await host.create();
      await host.setPlaybackTracks(
        audioStreamIndex: 2,
        subtitleStreamIndex: -1,
      );
      await host.setSubtitlePreferences(
        SubtitlePreferences.defaults.copyWith(fontFamily: 'serif'),
      );

      final tracksEvent = socket.emitted[socket.emitted.length - 2];
      expect(tracksEvent.$1, ClientEvent.partySetPlaybackTracks);
      expect(tracksEvent.$2, {
        'audioStreamIndex': 2,
        'subtitleStreamIndex': -1,
      });
      expect(socket.emitted.last.$1, ClientEvent.partySetSubtitlePreferences);
      expect(socket.emitted.last.$2, {
        'preferences': {
          ...SubtitlePreferences.defaults.toJson(),
          'fontFamily': 'serif',
        },
      });
    },
  );

  test(
    'create() makes the creator host: isHost/canControl true, wired onto the engine',
    () async {
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
    },
  );

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

  test(
    'solo handoff reuses open episode and preserves track selection',
    () async {
      final proxy = MediaCacheProxy(apiClient: _StubApiClient());
      await proxy.start();
      addTearDown(proxy.dispose);
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
      }, proxy: proxy);

      await container
          .read(partyProvider.notifier)
          .createFromCurrentPlayback(
            mediaItemId: 'episode-1',
            position: const Duration(minutes: 12),
            audioStreamIndex: 3,
            subtitleStreamIndex: -1,
          );

      expect(player.openCalls, 0);
      final create = socket.emitted.firstWhere(
        (entry) => entry.$1 == ClientEvent.partyCreate,
      );
      expect(create.$2, {
        'mediaItemId': 'episode-1',
        'audioStreamIndex': 3,
        'subtitleStreamIndex': -1,
      });
    },
  );

  test(
    'join() as a guest with collaborativeControl off: not host, canControl false',
    () async {
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
      expect(notifier.canControl, isFalse);

      final engine = container.read(syncEngineProvider) as SyncEngineImpl;
      expect(engine.isHost, isFalse);
      expect(engine.canControl, isFalse);
    },
  );

  test('web-host media source reaches the Flutter guest cache proxy', () async {
    final proxy = MediaCacheProxy(apiClient: _StubApiClient());
    await proxy.start();
    addTearDown(proxy.dispose);
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
    }, proxy: proxy);

    await container.read(partyProvider.notifier).join('party-1');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(player.openCalls, 1);
    expect(Uri.parse(player.lastOpenedUrl!).queryParameters, {
      'mediaSourceId': 'source-4k',
    });
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
      expect(
        (container.read(syncEngineProvider) as SyncEngineImpl).canControl,
        isFalse,
      );

      // Host approves — the server pushes party:approved with the session.
      socket.inject(ServerEvent.partyApproved, {
        'session': _session(hostId: 'host1', collaborativeControl: true),
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(container.read(partyProvider), isNotNull);
      expect(
        notifier.canControl,
        isTrue,
      ); // collaborative control granted on entry
      final engine = container.read(syncEngineProvider) as SyncEngineImpl;
      expect(engine.canControl, isTrue);
      expect(engine.isHost, isFalse);
    },
  );

  test(
    'setCollaborative(true) flips a guest\'s canControl without a host role',
    () async {
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
      await notifier.join('party-1');
      expect(notifier.canControl, isFalse);

      await notifier.setCollaborative(true);

      expect(notifier.canControl, isTrue);
      expect(notifier.isHost, isFalse);
      final engine = container.read(syncEngineProvider) as SyncEngineImpl;
      expect(engine.canControl, isTrue);
      expect(engine.isHost, isFalse);
    },
  );

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

  test(
    'selectMedia carries detail track choices into the active party',
    () async {
      container = build('host1', (event, data) {
        if (event == ClientEvent.partyCreate) {
          return {'partyId': 'party-1', 'session': _session(hostId: 'host1')};
        }
        return {'ok': true};
      });

      final notifier = container.read(partyProvider.notifier);
      await notifier.create();
      await notifier.selectMedia(
        'movie-1',
        audioStreamIndex: 3,
        subtitleStreamIndex: 7,
      );

      final event = socket.emitted.last;
      expect(event.$1, ClientEvent.partySelectMedia);
      expect(event.$2, {
        'mediaItemId': 'movie-1',
        'audioStreamIndex': 3,
        'subtitleStreamIndex': 7,
      });
    },
  );

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

  test(
    'end() (host) detaches the engine and clears local party state',
    () async {
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
    },
  );

  test(
    'party:ended stops a Flutter guest player and clears the room',
    () async {
      container = build('guest1', (event, data) {
        if (event == ClientEvent.partyJoin) {
          return {'status': 'joined', 'session': _session(hostId: 'web-host')};
        }
        return {'ok': true};
      });
      await container.read(partyProvider.notifier).join('party-1');

      socket.inject(ServerEvent.partyEnded, const {});
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(player.pauseCalls, 1);
      expect(container.read(partyProvider), isNull);
      expect(socket.isConnected, isFalse);
    },
  );
}
