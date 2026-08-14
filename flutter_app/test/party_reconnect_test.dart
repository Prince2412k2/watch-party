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
import 'package:watchparty/ui/ui.dart';
import 'package:watchparty/state/state.dart';

/// Getting back into a party without anyone pressing anything.
///
/// The bug: a drop left the room silently gone, and the only way back was the
/// Reconnect button in the party panel. Two connections can drop and they are
/// not the same failure — the socket cuts you out of the room, LiveKit only
/// costs you camera and mic — so only one of them is allowed to put a page in
/// front of the film.

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

  test('minimising keeps the retrying, it only moves the surface', () {
    fakeAsync((async) {
      final socket = _PartySocket();
      final container = _container(socket);
      final notifier = container.read(partyConnectionProvider.notifier);
      notifier.start();
      _joinParty(container, async);

      socket.acceptDials = false;
      unawaited(socket.disconnect());
      async.flushMicrotasks();

      notifier.minimise();
      expect(container.read(partyConnectionProvider).minimised, isTrue);
      expect(container.read(partyConnectionProvider).lost, isTrue);

      final before = socket.connects;
      async.elapse(const Duration(seconds: 30));
      // The whole point of Back here: it gives you the picture back WITHOUT
      // giving up on the room.
      expect(socket.connects, greaterThan(before));

      notifier.expand();
      expect(container.read(partyConnectionProvider).minimised, isFalse);
    });
  });

  _surfaceTests();

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
  Future<ProviderContainer> showSurface(
    WidgetTester tester, {
    bool minimised = false,
  }) async {
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
    if (minimised) container.read(partyConnectionProvider.notifier).minimise();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: AnalogToastHost(child: PartyReconnectScreen()),
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

  testWidgets('shows the room you are trying to get back into', (tester) async {
    final container = await showSurface(tester);

    expect(find.text('Reconnecting…'), findsOneWidget);
    // The people in it, host marked as such.
    expect(find.text('Ada'), findsOneWidget);
    expect(find.text('Grace'), findsOneWidget);
    expect(find.text('Host'), findsOneWidget);
    // And the way out, which is not the same as the way back.
    expect(find.byIcon(Icons.close), findsOneWidget);
    await settle(tester, container);
  });

  testWidgets('Back sends it to the corner without giving up', (tester) async {
    final container = await showSurface(tester);

    await tester.tap(find.byType(GlassBackButton));
    await tester.pump();

    expect(container.read(partyConnectionProvider).minimised, isTrue);
    // Still lost, still retrying — only the drawing moved.
    expect(container.read(partyConnectionProvider).lost, isTrue);
    expect(find.text('Ada'), findsNothing);
    expect(find.textContaining('Reconnecting'), findsOneWidget);
    await settle(tester, container);
  });

  testWidgets('the pill goes back to the full surface', (tester) async {
    final container = await showSurface(tester, minimised: true);

    expect(find.text('Ada'), findsNothing);
    await tester.tap(find.textContaining('Reconnecting'));
    await tester.pump();

    expect(container.read(partyConnectionProvider).minimised, isFalse);
    expect(find.text('Ada'), findsOneWidget);
    await settle(tester, container);
  });

  testWidgets('the cross stops the retrying and leaves', (tester) async {
    final container = await showSurface(tester);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump(const Duration(milliseconds: 100));

    expect(container.read(partyProvider), isNull);
    expect(container.read(partyConnectionProvider).lost, isFalse);
  });
}
