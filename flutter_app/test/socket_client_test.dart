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

  test('the socket URL carries an explicit port for a multi-label host', () {
    // The bug this guards, verbatim from the field: "Connection to
    // 'https://watch.example.com:0/socket.io/?EIO=4&transport=websocket'
    // was not upgraded to websocket".
    //
    // socket_io_client parses a multi-label HTTPS host as port 0 and then
    // builds its handshake URL from what it parsed — so setting `port` in the
    // options map, which the test above already asserted and which already
    // PASSED, never had a chance to correct it. That is exactly why this
    // shipped: the options were right and the URL was not.
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
}
