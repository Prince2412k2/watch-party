import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/net/events.dart';
import 'package:watchparty/net/socket_client.dart';
import 'package:watchparty/state/state.dart';

void main() {
  late MockSocketClient socket;
  late ProviderContainer container;

  setUp(() {
    socket = MockSocketClient();
    container = ProviderContainer(
      overrides: [socketClientProvider.overrideWithValue(socket)],
    );
    addTearDown(container.dispose);
  });

  test('appends an incoming chat:message to state', () {
    // Force the notifier to build (and subscribe) before injecting.
    container.read(chatProvider);

    socket.inject(ServerEvent.chatMessage, {
      'userId': 'u2',
      'name': 'Alex',
      'text': 'hey!',
      'timestamp': 1000,
    });

    final messages = container.read(chatProvider);
    expect(messages, hasLength(1));
    expect(messages.single.userId, 'u2');
    expect(messages.single.text, 'hey!');
  });

  test('send() emits chat:message over the socket', () async {
    final error = await container.read(chatProvider.notifier).send('hello');

    expect(error, isNull);
    expect(socket.emitted, hasLength(1));
    final (event, data) = socket.emitted.single;
    expect(event, ClientEvent.chatMessage);
    expect((data as Map)['text'], 'hello');
  });

  test('send() ignores blank text without emitting', () async {
    final error = await container.read(chatProvider.notifier).send('   ');

    expect(error, isNull);
    expect(socket.emitted, isEmpty);
  });

  test('client-side rate limit trips after 5 sends within the window', () async {
    final notifier = container.read(chatProvider.notifier);

    for (var i = 0; i < 5; i++) {
      final error = await notifier.send('msg $i');
      expect(error, isNull, reason: 'send #$i should succeed');
    }

    expect(notifier.isRateLimited, isTrue);

    final blocked = await notifier.send('one too many');
    expect(blocked, isNotNull);
    expect(blocked, contains('Rate limited'));

    // Only the first 5 actually reached the socket.
    expect(socket.emitted, hasLength(5));
  });

  test('surfaces a server-side rate-limit ack as an error', () async {
    socket = _RateLimitingSocketClient();
    container = ProviderContainer(
      overrides: [socketClientProvider.overrideWithValue(socket)],
    );
    addTearDown(container.dispose);

    final error = await container.read(chatProvider.notifier).send('hi');
    expect(error, contains('Rate limited'));
  });
}

/// A socket whose ack always reports the server-side rate limit, regardless
/// of the client-side send-time window — exercises the ack error path
/// independently of the local guard.
class _RateLimitingSocketClient extends MockSocketClient {
  @override
  Future<dynamic> emitWithAck(String event, [Object? data]) async {
    emitted.add((event, data));
    return {'error': 'rate limited'};
  }
}
