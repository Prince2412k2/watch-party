import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/data/api_client.dart';
import 'package:watchparty/data/mock_api_client.dart';
import 'package:watchparty/livekit/livekit_room.dart';
import 'package:watchparty/net/events.dart';
import 'package:watchparty/analog/chrome/chrome.dart';
import 'package:watchparty/net/socket_client.dart';
import 'package:watchparty/party/party_reconnect_screen.dart';
import 'package:watchparty/state/state.dart';

/// Getting back into a party without anyone pressing anything.
///
/// The bug: a drop left the room silently gone, and the only way back was the
/// Reconnect button in the party panel. Two connections can drop and they are
/// not the same failure — the socket cuts you out of the room, LiveKit only
/// costs you camera and mic. Neither should cover the film.

/// Counts dials, answers a join, and lets the test decide whether a dial
/// actually restores the link.
class _PartySocket extends MockSocketClient {
  int connects = 0;

  /// While false, a dial goes through the motions and the link stays down —
  /// which is what a retry against a server that is still unreachable does.
  bool acceptDials = true;

  @override
  Future<void> connect() async {
    connects++;
    if (acceptDials) await super.connect();
  }

  @override
  Future<dynamic> emitWithAck(String event, [Object? data]) async {
    emitted.add((event, data));
    if (event == ClientEvent.partyJoin) {
      return {'status': 'joined', 'session': _session};
    }
    return {'ok': true};
  }
}

class _GatedResumeSocket extends _PartySocket {
  final resume = Completer<dynamic>();

  @override
  Future<dynamic> emitWithAck(String event, [Object? data]) {
    if (event == ClientEvent.partyResume) {
      emitted.add((event, data));
      return resume.future;
    }
    return super.emitWithAck(event, data);
  }
}

Map<String, dynamic> get _session => {
  'id': 'room-1',
  'hostId': 'host-1',
  'hostName': 'Ada',
  'stage': 'watching',
  'mediaItemId': 'movie-1',
  'mediaSourceId': 'source-1',
  'syncMode': 'hopping',
  'guests': [
    {'userId': 'guest-1', 'name': 'Grace'},
  ],
  'schedule': <String, dynamic>{},
  'browse': {'stack': <dynamic>[]},
  'waiting': <dynamic>[],
};

/// A room service that connects instantly and never touches the network.
class _NoopLiveKit extends LiveKitRoomService {
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

class _PartyApi extends MockApiClient {
  @override
  Future<LiveKitToken> livekitToken(String partyId) async =>
      const LiveKitToken(token: 'token', url: 'ws://livekit.test');
}

ProviderContainer _container(_PartySocket socket) {
  final container = ProviderContainer(
    overrides: [
      socketClientProvider.overrideWithValue(socket),
      apiClientProvider.overrideWithValue(_PartyApi()),
      livekitRoomServiceProvider.overrideWithValue(_NoopLiveKit()),
      currentUserIdProvider.overrideWithValue('guest-1'),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Join for real — through the socket ack — so the party state under test is
/// the one the app would actually be holding.
void _joinParty(ProviderContainer container, FakeAsync async) {
  unawaited(container.read(partyProvider.notifier).join('room-1'));
  async.elapse(const Duration(milliseconds: 50));
  expect(container.read(partyProvider), isNotNull);
}

void main() {
  group('the backoff', () {
    test('starts fast and stops growing', () {
      // Most drops are a blip, so the first retry is immediate-ish; past half a
      // minute a tighter loop fixes nothing and only hammers a server that is
      // already struggling.
      expect(partyRetryBackoff(0), const Duration(seconds: 1));
      expect(partyRetryBackoff(1), const Duration(seconds: 2));
      expect(partyRetryBackoff(2), const Duration(seconds: 4));
      expect(partyRetryBackoff(3), const Duration(seconds: 8));
      expect(partyRetryBackoff(4), const Duration(seconds: 15));
      expect(partyRetryBackoff(50), const Duration(seconds: 15));
    });
  });

  test('a drop outside a party raises nothing', () {
    fakeAsync((async) {
      final socket = _PartySocket();
      final container = _container(socket);
      container.read(partyConnectionProvider.notifier).start();

      unawaited(socket.connect());
      async.flushMicrotasks();
      socket.acceptDials = false;
      unawaited(socket.disconnect());
      async.elapse(const Duration(seconds: 30));

      // Nothing to be cut off from, so nothing to say and nothing to dial.
      expect(container.read(partyConnectionProvider).lost, isFalse);
      expect(socket.connects, 1);
    });
  });

  test('a drop in a party keeps retrying, on its own', () {
    fakeAsync((async) {
      final socket = _PartySocket();
      final container = _container(socket);
      container.read(partyConnectionProvider.notifier).start();
      _joinParty(container, async);
      final dialsBefore = socket.connects;

      socket.acceptDials = false;
      unawaited(socket.disconnect());
      async.flushMicrotasks();
      expect(container.read(partyConnectionProvider).lost, isTrue);

      // Nobody presses anything; the retries just happen.
      async.elapse(const Duration(seconds: 40));
      expect(
        socket.connects - dialsBefore,
        greaterThan(3),
        reason: 'should have retried several times unaided',
      );
      expect(container.read(partyConnectionProvider).attempt, greaterThan(3));
    });
  });

  test('the surface goes away by itself when the link comes back', () {
    fakeAsync((async) {
      final socket = _PartySocket();
      final container = _container(socket);
      container.read(partyConnectionProvider.notifier).start();
      _joinParty(container, async);

      socket.acceptDials = false;
      unawaited(socket.disconnect());
      async.flushMicrotasks();
      expect(container.read(partyConnectionProvider).lost, isTrue);

      // The link returns — by its own reconnect or because a retry landed.
      socket.acceptDials = true;
      async.elapse(const Duration(seconds: 5));

      final state = container.read(partyConnectionProvider);
      expect(state.lost, isFalse);
      expect(state.attempt, 0);

      // And it stops dialling.
      final settled = socket.connects;
      async.elapse(const Duration(seconds: 60));
      expect(socket.connects, settled);
    });
  });

  _surfaceTests();

  test('chat reconnects and waits for room recovery before sending', () {
    fakeAsync((async) {
      final socket = _GatedResumeSocket();
      final container = _container(socket);
      _joinParty(container, async);
      unawaited(socket.disconnect());
      async.flushMicrotasks();

      String? result = 'pending';
      unawaited(
        container.read(chatProvider.notifier).send('hello').then((e) {
          result = e;
        }),
      );
      async.flushMicrotasks();

      expect(socket.isConnected, isTrue);
      expect(result, 'pending');
      expect(
        socket.emitted.where((e) => e.$1 == ClientEvent.chatMessage),
        isEmpty,
      );
      expect(
        socket.emitted.where((e) => e.$1 == ClientEvent.partyResume),
        hasLength(1),
      );

      socket.resume.complete({'session': _session});
      async.flushMicrotasks();
      expect(result, isNull);
      expect(
        socket.emitted.where((e) => e.$1 == ClientEvent.chatMessage),
        hasLength(1),
      );
    });
  });

  test('a timed-out chat wait never sends later when recovery finishes', () {
    fakeAsync((async) {
      final socket = _GatedResumeSocket();
      final container = _container(socket);
      _joinParty(container, async);
      unawaited(socket.disconnect());
      async.flushMicrotasks();

      String? result;
      unawaited(
        container.read(chatProvider.notifier).send('hello').then((e) {
          result = e;
        }),
      );
      async.elapse(const Duration(seconds: 6));
      expect(result, contains('reconnecting'));
      expect(container.read(chatProvider.notifier).isRateLimited, isFalse);

      socket.resume.complete({'session': _session});
      async.flushMicrotasks();
      expect(
        socket.emitted.where((e) => e.$1 == ClientEvent.chatMessage),
        isEmpty,
      );
    });
  });

  test('leaving during chat recovery prevents the message from being sent', () {
    fakeAsync((async) {
      final socket = _GatedResumeSocket();
      final container = _container(socket);
      _joinParty(container, async);
      unawaited(socket.disconnect());
      async.flushMicrotasks();

      String? result;
      unawaited(
        container.read(chatProvider.notifier).send('hello').then((e) {
          result = e;
        }),
      );
      async.flushMicrotasks();
      unawaited(container.read(partyProvider.notifier).leave());
      async.flushMicrotasks();
      socket.resume.complete({'session': _session});
      async.flushMicrotasks();
      expect(result, isNotNull);
      expect(
        socket.emitted.where((e) => e.$1 == ClientEvent.chatMessage),
        isEmpty,
      );
    });
  });

  test('leaving stops the retrying for good', () {
    fakeAsync((async) {
      final socket = _PartySocket();
      final container = _container(socket);
      final notifier = container.read(partyConnectionProvider.notifier);
      notifier.start();
      _joinParty(container, async);

      socket.acceptDials = false;
      unawaited(socket.disconnect());
      async.flushMicrotasks();

      unawaited(notifier.stopAndLeave());
      async.flushMicrotasks();
      final after = socket.connects;

      async.elapse(const Duration(minutes: 2));
      expect(container.read(partyConnectionProvider).lost, isFalse);
      // A room nobody is in must not still be dialled.
      expect(socket.connects, after);
    });
  });
}

/// The surface itself: what a disconnected party looks like.
void _surfaceTests() {
  var movieTaps = 0;
  Future<ProviderContainer> showSurface(WidgetTester tester) async {
    movieTaps = 0;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.reset);

    final socket = _PartySocket();
    final container = ProviderContainer(
      overrides: [
        socketClientProvider.overrideWithValue(socket),
        apiClientProvider.overrideWithValue(_PartyApi()),
        livekitRoomServiceProvider.overrideWithValue(_NoopLiveKit()),
        currentUserIdProvider.overrideWithValue('guest-1'),
      ],
    );
    addTearDown(container.dispose);

    container.read(partyConnectionProvider.notifier).start();
    await socket.connect();
    await container.read(partyProvider.notifier).join('room-1');
    container.read(nowPlayingProvider.notifier).open(itemId: 'movie-1');

    socket.acceptDials = false;
    await socket.disconnect();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: AnalogToastHost(
            child: Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => movieTaps++,
                  child: const ColoredBox(color: Colors.blue),
                ),
                const Positioned.fill(child: PartyReconnectScreen()),
              ],
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
    return container;
  }

  /// Stop the retrying before the test ends. Not tidiness: the surface is
  /// SUPPOSED to still be retrying while it is on screen, and a live timer at
  /// the end of a widget test fails it.
  Future<void> settle(WidgetTester tester, ProviderContainer container) async {
    await container.read(partyConnectionProvider.notifier).stopAndLeave();
    await tester.pump();
  }

  testWidgets('shows only a small non-modal reconnecting tag', (tester) async {
    final container = await showSurface(tester);

    expect(find.text('Reconnecting…'), findsOneWidget);
    expect(find.text('Ada'), findsNothing);
    expect(find.byIcon(Icons.close), findsNothing);
    expect(
      find.descendant(
        of: find.byType(PartyReconnectScreen),
        matching: find.byType(ModalBarrier),
      ),
      findsNothing,
    );
    final tag = tester.getRect(find.text('Reconnecting…'));
    expect(tag.top, lessThan(50));
    expect(tag.right, lessThan(240));
    expect(container.read(nowPlayingProvider).itemId, 'movie-1');
    await settle(tester, container);
  });

  testWidgets('movie controls receive taps even through the tag', (
    tester,
  ) async {
    final container = await showSurface(tester);

    await tester.tapAt(tester.getCenter(find.text('Reconnecting…')));
    await tester.tapAt(const Offset(640, 450));
    expect(movieTaps, 2);
    expect(container.read(partyConnectionProvider).lost, isTrue);
    expect(find.text('Ada'), findsNothing);
    expect(find.textContaining('Reconnecting'), findsOneWidget);
    await settle(tester, container);
  });

  testWidgets('the tag disappears after recovery', (tester) async {
    final container = await showSurface(tester);

    final socket = container.read(socketClientProvider) as _PartySocket;
    socket.acceptDials = true;
    await socket.connect();
    await tester.pump();

    expect(container.read(partyConnectionProvider).lost, isFalse);
    expect(find.text('Reconnecting…'), findsNothing);
    await settle(tester, container);
  });
}
