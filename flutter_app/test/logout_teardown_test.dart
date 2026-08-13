import 'dart:async';
import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:watchparty/cache/media_cache_proxy.dart';
import 'package:watchparty/data/api_client.dart';
import 'package:watchparty/data/mock_api_client.dart';
import 'package:watchparty/livekit/livekit_room.dart';
import 'package:watchparty/net/events.dart';
import 'package:watchparty/net/socket_client.dart';
import 'package:watchparty/player/player_controller.dart';
import 'package:watchparty/state/state.dart';

// Session teardown on logout and on an origin switch (issue #59).
//
// Logout is the one flow where a half-completed teardown is dangerous rather
// than merely untidy: a live camera, a socket still authenticated as the
// previous user, or a persisted cookie that the next launch replays. So the
// cases here are the ones that used to leave something behind — an active A/V
// party, a logout the server never answered, a logout the server answered with
// a 500, and pointing the app at a different backend.

/// A room service that reports a connected room without touching the network,
/// so the party can be torn down from a genuinely "live A/V" state.
class _FakeLiveKitRoomService extends LiveKitRoomService {
  final _snapshots = StreamController<LiveKitRoomSnapshot>.broadcast();
  int disconnectCalls = 0;

  @override
  Stream<LiveKitRoomSnapshot> get snapshots => _snapshots.stream;

  @override
  Future<void> connect(
    String url,
    String token, {
    bool enableMic = false,
    bool enableCamera = false,
  }) async {
    _publish(
      const LiveKitRoomSnapshot(
        connectionState: lk.ConnectionState.connected,
        micEnabled: true,
        cameraEnabled: true,
        participants: [
          ParticipantTrack(identity: 'host1', name: 'Host', isLocal: false),
        ],
      ),
    );
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
    _publish(const LiveKitRoomSnapshot());
  }

  @override
  Future<void> dispose() async {
    await _snapshots.close();
  }

  void _publish(LiveKitRoomSnapshot snapshot) {
    if (!_snapshots.isClosed) _snapshots.add(snapshot);
  }
}

/// Records what the shared player was asked to do, so "playback stopped" can be
/// asserted rather than assumed.
class _RecordingPlayer implements PlayerController {
  int openCalls = 0;
  int pauseCalls = 0;
  final List<Duration> seeks = [];

  @override
  Future<void> open(
    String url, {
    Duration startAt = Duration.zero,
    bool autoplay = false,
  }) async => openCalls++;

  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async => pauseCalls++;
  @override
  Future<void> seek(Duration position) async => seeks.add(position);
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

class _JoinedPartySocket extends MockSocketClient {
  _JoinedPartySocket(this._session);
  final Map<String, dynamic> _session;
  String? lastUrl;

  @override
  set url(String value) => lastUrl = value;

  @override
  Future<dynamic> emitWithAck(String event, [Object? data]) async {
    emitted.add((event, data));
    if (event == ClientEvent.partyJoin) {
      return {'status': 'joined', 'session': _session};
    }
    return {'ok': true};
  }
}

/// Mints a LiveKit token so `_postJoinSetup` reaches the room service.
class _PartyApi extends MockApiClient {
  @override
  Future<LiveKitToken> livekitToken(String partyId) async =>
      const LiveKitToken(token: 'token', url: 'ws://livekit.test');
}

/// The server never answers the logout. The local teardown still has to run.
class _UnreachableLogoutApi extends _PartyApi {
  @override
  Future<void> logout() async =>
      throw SocketException('network is unreachable');
}

Map<String, dynamic> _watchingSession() => {
  'id': 'party-1',
  'hostId': 'host1',
  'hostName': 'Host',
  'stage': 'watching',
  'mediaItemId': 'movie-1',
  'mediaSourceId': 'source-1',
  'collaborativeControl': true,
  'syncMode': 'hopping',
  'guests': [
    {'userId': 'guest1', 'name': 'Me'},
  ],
  'schedule': <String, dynamic>{},
  'browse': {'stack': <dynamic>[]},
  'waiting': [
    {'userId': 'guest2', 'name': 'Latecomer'},
  ],
};

/// A [DioApiClient] over a scripted transport, plus the jar it holds, so cookie
/// state can be inspected directly.
class _StubbedClient {
  _StubbedClient(this.api, this.jar, this.origin);
  final DioApiClient api;
  final CookieJar jar;
  final Uri origin;

  Future<List<Cookie>> get storedCookies => jar.loadForRequest(origin);
}

/// Builds a client whose every request is answered by [respond] without leaving
/// the process, seeded with a session cookie for [baseUrl].
Future<_StubbedClient> _stubbedClient(
  String baseUrl,
  void Function(RequestOptions options, RequestInterceptorHandler handler)
  respond,
) async {
  final jar = CookieJar();
  final dio = Dio(BaseOptions(baseUrl: baseUrl));
  dio.interceptors.add(InterceptorsWrapper(onRequest: respond));
  final api = DioApiClient(dio: dio, cookieJar: jar);
  final origin = Uri.parse(baseUrl);
  await jar.saveFromResponse(origin, [Cookie('connect.sid', 'live-session')]);
  return _StubbedClient(api, jar, origin);
}

void _resolveAsUser(RequestOptions options, RequestInterceptorHandler handler) {
  handler.resolve(
    Response(
      requestOptions: options,
      statusCode: 200,
      data: const {'userId': 'u1', 'name': 'root', 'isAdmin': false},
    ),
  );
}

void main() {
  // Teardown clears the persisted server config, which reads SharedPreferences.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('logout tears the session down', () {
    late _JoinedPartySocket socket;
    late _RecordingPlayer player;
    late _FakeLiveKitRoomService livekit;

    Future<ProviderContainer> joinedParty({ApiClient? api}) async {
      socket = _JoinedPartySocket(_watchingSession());
      player = _RecordingPlayer();
      livekit = _FakeLiveKitRoomService();
      final proxy = MediaCacheProxy(apiClient: _PartyApi());
      await proxy.start();
      addTearDown(proxy.dispose);

      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(api ?? _PartyApi()),
          socketClientProvider.overrideWithValue(socket),
          playerControllerProvider.overrideWithValue(player),
          mediaCacheProxyProvider.overrideWithValue(proxy),
          livekitRoomServiceProvider.overrideWithValue(livekit),
          currentUserIdProvider.overrideWithValue('guest1'),
          serverConfigProvider.overrideWith(
            (ref) => ServerConfigNotifier(ref, 'https://old.test'),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(authProvider.notifier).login('root', 'root');
      // Force the chat notifier to exist before any message is delivered — it
      // subscribes to the socket in its constructor.
      expect(container.read(chatProvider), isEmpty);
      await container.read(partyProvider.notifier).join('party-1');
      container.read(nowPlayingProvider.notifier).open(itemId: 'local-movie');
      await player.open('https://media.test/local-movie', autoplay: true);
      await container.read(profileProvider.notifier).load();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return container;
    }

    test('during active A/V playback, leaving nothing running', () async {
      final container = await joinedParty();

      socket.inject(ServerEvent.chatMessage, const {
        'userId': 'host1',
        'name': 'Host',
        'text': 'starting now',
        'timestamp': 1,
      });

      expect(container.read(authProvider).isAuthenticated, isTrue);
      expect(container.read(partyProvider), isNotNull);
      expect(socket.isConnected, isTrue);
      expect(container.read(livekitProvider).connected, isTrue);
      expect(container.read(livekitProvider).cameraEnabled, isTrue);
      expect(container.read(chatProvider), isNotEmpty);
      expect(container.read(partyWaitingProvider), isNotEmpty);
      expect(container.read(profileProvider).profile, isNotNull);
      expect(player.openCalls, 1, reason: 'the movie is open and playing');

      await container.read(authProvider.notifier).logout();

      expect(container.read(authProvider).isAuthenticated, isFalse);
      expect(container.read(authProvider).initialized, isTrue);
      expect(container.read(partyProvider), isNull);
      expect(container.read(partyWaitingProvider), isEmpty);
      expect(socket.isConnected, isFalse);
      expect(livekit.disconnectCalls, greaterThanOrEqualTo(1));
      expect(container.read(livekitProvider).connected, isFalse);
      expect(container.read(livekitProvider).cameraEnabled, isFalse);
      expect(player.pauseCalls, greaterThanOrEqualTo(1));
      expect(player.seeks, contains(Duration.zero));
      expect(container.read(chatProvider), isEmpty);
      expect(container.read(profileProvider).profile, isNull);
      // Back to whatever the build itself knows: null for a build that has to
      // be told its origin, and the baked-in one for a build that already
      // knows — which must not be stranded on a server picker it never shows.
      expect(container.read(serverConfigProvider), bakedServerUrl);
      // Cached avatar drawings are keyed by this revision.
      expect(container.read(avatarRevisionProvider), 1);
    });

    test('when the server is unreachable, without throwing', () async {
      final container = await joinedParty(api: _UnreachableLogoutApi());

      // The sign-out button awaits this bare; a failed round trip must not
      // surface as an unhandled error, and must not skip the teardown.
      await container.read(authProvider.notifier).logout();

      expect(container.read(authProvider).isAuthenticated, isFalse);
      expect(container.read(authProvider).initialized, isTrue);
      expect(container.read(partyProvider), isNull);
      expect(socket.isConnected, isFalse);
      expect(livekit.disconnectCalls, greaterThanOrEqualTo(1));
      expect(container.read(livekitProvider).connected, isFalse);
      expect(player.pauseCalls, greaterThanOrEqualTo(1));
      expect(container.read(profileProvider).profile, isNull);
      expect(container.read(serverConfigProvider), bakedServerUrl);
    });
  });

  group('DioApiClient.logout drops the local session', () {
    test('when the request never reaches the server', () async {
      var failRequests = false;
      final stub = await _stubbedClient('http://example.test', (
        options,
        handler,
      ) {
        if (failRequests) {
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.connectionError,
              error: SocketException('network is unreachable'),
            ),
          );
          return;
        }
        _resolveAsUser(options, handler);
      });

      // A successful call caches the Cookie: header image widgets reuse.
      await stub.api.me();
      expect(stub.api.cookieHeader, contains('connect.sid=live-session'));

      failRequests = true;
      await expectLater(stub.api.logout(), throwsA(isA<DioException>()));

      expect(stub.api.cookieHeader, isNull);
      expect(await stub.storedCookies, isEmpty);
    });

    test('when the server answers 500', () async {
      var logoutFails = false;
      final stub = await _stubbedClient('http://example.test', (
        options,
        handler,
      ) {
        if (logoutFails) {
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 500,
              data: const {'error': 'session store unavailable'},
            ),
          );
          return;
        }
        _resolveAsUser(options, handler);
      });

      await stub.api.me();
      expect(stub.api.cookieHeader, isNotNull);

      logoutFails = true;
      await expectLater(
        stub.api.logout(),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 500)
              .having((e) => e.operation, 'operation', 'logout'),
        ),
      );

      expect(stub.api.cookieHeader, isNull);
      expect(await stub.storedCookies, isEmpty);
    });
  });

  group('changing the server origin', () {
    late _JoinedPartySocket socket;

    Future<(ProviderContainer, _StubbedClient)> signedInAt(
      String origin,
    ) async {
      final stub = await _stubbedClient(origin, _resolveAsUser);
      socket = _JoinedPartySocket(_watchingSession());
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(stub.api),
          socketClientProvider.overrideWithValue(socket),
          serverConfigProvider.overrideWith(
            (ref) => ServerConfigNotifier(ref, origin),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(authProvider.notifier).login('root', 'root');
      expect(container.read(authProvider).isAuthenticated, isTrue);
      expect(stub.api.cookieHeader, isNotNull);
      return (container, stub);
    }

    test('drops the previous origin\'s authentication immediately', () async {
      final (container, stub) = await signedInAt('http://old.test');

      await container.read(serverConfigProvider.notifier).setUrl('new.test');

      expect(container.read(serverConfigProvider), 'https://new.test');
      expect(stub.api.baseUrl, 'https://new.test');
      expect(socket.lastUrl, 'https://new.test');
      // Nothing minted by the old origin survives the switch.
      expect(stub.api.cookieHeader, isNull);
      expect(await stub.storedCookies, isEmpty);
      expect(container.read(authProvider).isAuthenticated, isFalse);
      expect(container.read(authProvider).initialized, isTrue);
    });

    test('keeps the session when the origin is re-saved unchanged', () async {
      final (container, stub) = await signedInAt('https://same.test');

      // Trailing slash and bare host both normalize to the current origin.
      await container.read(serverConfigProvider.notifier).setUrl('same.test/');

      expect(container.read(serverConfigProvider), 'https://same.test');
      expect(container.read(authProvider).isAuthenticated, isTrue);
      expect(stub.api.cookieHeader, isNotNull);
      expect(await stub.storedCookies, isNotEmpty);
    });
  });
}
