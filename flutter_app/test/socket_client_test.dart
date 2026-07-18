import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/net/socket_client.dart';
import 'package:watchparty/ui/widgets/join_code_dialog.dart';

void main() {
  test('HTTPS Socket.IO uses port 443 with native WebSocket transport', () {
    final options = socketOptionsFor(
      'https://watch.sniffkin.tech',
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
}
