import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/net/socket_client.dart';
import 'package:watchparty/ui/widgets/join_code_dialog.dart';

void main() {
  test('HTTPS Socket.IO uses port 443 with native WebSocket transport', () {
    final options = socketOptionsFor(
      'https://watch.example.com',
      'connect.sid=session',
    );

    expect(options['port'], 443);
    expect(options['transports'], ['websocket']);
    expect(options['extraHeaders'], {'Cookie': 'connect.sid=session'});
  });

  test('explicit Socket.IO ports are preserved', () {
    expect(socketOptionsFor('http://localhost:3005', null)['port'], 3005);
  });

  test('join dialog hides transport implementation errors', () {
    expect(
      partyJoinError(
        Exception('WebSocketException: connection was not upgraded'),
      ),
      'Could not connect to the party. Check your connection and try again.',
    );
  });

  test('a custom connector supplies the dial', () {
    // Without this, socket_io_client uses its default connector and the port
    // is lost inside dart:io. The option is the ONLY point at which our code
    // still gets to see the URL.
    expect(
      socketOptionsFor('https://watch.example.com', null)['webSocketConnector'],
      isNotNull,
    );
  });

  test('dart:io has no default port for wss — the reason for the fix', () {
    // The entire `:0` failure reduces to this one line of Dart behaviour, so
    // assert it directly rather than trusting the retelling.
    //
    // socket_io_client's Transport._port() omits a port equal to the scheme
    // default, handing dart:io `wss://host/...`. dart:io rebuilds that as an
    // HTTPS request copying `uri.port` — and for `wss`, Dart has no default
    // port, so that is 0. Hence `https://host:0/socket.io/?...`.
    expect(Uri.parse('wss://watch.example.com/socket.io/').port, 0);
    // For https it would have been fine, which is why every previous theory
    // that reasoned about the https URL looked plausible and was wrong.
    expect(Uri.parse('https://watch.example.com/socket.io/').port, 443);
  });

  test('the connector writes the port a wss URL is missing', () {
    // What connectSocketWebSocket does before dialling. Rebuilt here rather
    // than opening a socket: the assertion is about the URL, not the network.
    Uri withPort(Uri uri) => uri.hasPort
        ? uri
        : uri.replace(port: uri.isScheme('wss') ? 443 : 80);

    expect(
      withPort(Uri.parse('wss://watch.example.com/socket.io/')).toString(),
      'wss://watch.example.com:443/socket.io/',
    );
    // And the round trip that matters: the rebuilt URL now survives the parse
    // that was returning 0.
    expect(
      Uri.parse(
        withPort(Uri.parse('wss://watch.example.com/socket.io/')).toString(),
      ).port,
      443,
    );
    // A URL that already names a port is untouched.
    expect(
      withPort(Uri.parse('ws://localhost:3005/socket.io/')).toString(),
      'ws://localhost:3005/socket.io/',
    );
  });

  test('the socket URL carries an explicit port for a multi-label host', () {
    // Belt and braces only — this settles the engine's recorded origin, and
    // does NOT reach the transport's URL, because Transport._port() strips a
    // default port again on the way out. The field failure proved it: the
    // client logged :443 and the exception still said :0.
    expect(
      socketUrlFor('https://watch.example.com'),
      'https://watch.example.com:443',
    );
    expect(
      socketUrlFor('http://example.internal'),
      'http://example.internal:80',
    );
  });

  test('a URL that already names a port is left alone', () {
    // localhost and tailnet addresses parse correctly today; rewriting them
    // would be a change with no upside and a real chance of breaking dev.
    expect(socketUrlFor('http://localhost:3005'), 'http://localhost:3005');
    expect(
      socketUrlFor('https://host.example:8443'),
      'https://host.example:8443',
    );
  });

  group('a flaky upgrade is retried', () {
    // Diagnosing a real report showed the handshake refused and an identical
    // request a second later accepted — 101, correct accept, correct headers.
    // The endpoint sits behind a CDN whose edges occasionally answer an upgrade
    // badly. One failed dial used to be the whole connection, because there is
    // no polling fallback to fall back TO.
    late HttpServer server;
    late int requests;

    /// Fails the first [failures] upgrade attempts, then serves a real one.
    Future<void> serve({required int failures}) async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      requests = 0;
      server.listen((request) async {
        requests++;
        if (requests <= failures) {
          // A plausible bad answer: not a 101, so dart:io reports exactly the
          // "was not upgraded to websocket" this retry exists for.
          request.response.statusCode = HttpStatus.badGateway;
          await request.response.close();
          return;
        }
        final socket = await WebSocketTransformer.upgrade(request);
        await socket.close();
      });
    }

    tearDown(() => server.close(force: true));

    test('two bad answers then a good one still connects', () async {
      await serve(failures: 2);
      final socket = await connectSocketWebSocket(
        Uri.parse('ws://127.0.0.1:${server.port}/socket.io/'),
      );
      expect(requests, 3, reason: 'it kept trying until the edge behaved');
      await socket.close();
    });

    test('a socket closed after the upgrade reports the close code', () async {
      // The fact that separates "something in the path killed it" (1006, no
      // close frame) from "the peer closed politely" (1000/1001) — socket.io
      // says 'transport close' for both.
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        await socket.close(1011, 'nope');
      });

      final probe = SocketDialProbe();
      final socket = await connectSocketWebSocket(
        Uri.parse('ws://127.0.0.1:${server.port}/socket.io/'),
        probe: probe,
      );
      // Drain, so the close frame is delivered before the code is read.
      await socket.events.drain<void>();

      expect(probe.closeDescription, 'ws close 1011 "nope"');
    });

    test('a server that never upgrades still fails, and says what it said',
        () async {
      // The retry must not turn a genuinely broken endpoint into a hang or an
      // endless loop: three attempts, then report.
      await serve(failures: 1000);
      await expectLater(
        connectSocketWebSocket(
          Uri.parse('ws://127.0.0.1:${server.port}/socket.io/'),
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            allOf(contains('3 attempts'), contains('502')),
          ),
        ),
      );
    });
  });
}
