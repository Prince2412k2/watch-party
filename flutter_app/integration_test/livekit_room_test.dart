// Live A/V integration test for E6 LiveKitRoomService.
//
// Mirrors the de-risk spike (`spike/lib/main.dart`, S2): connect to the
// existing LiveKit room with a backend-issued token, then publish camera +
// mic on this Linux box (which has a real /dev/video0), and assert the room
// reaches `connected` with a local camera track published.
//
// Requires a LiveKit server reachable at the URL in
// `/tmp/wp-spike-livekit.txt` (line 1: ws url, line 2: token) — the same
// artifact the spike produced. Regenerate it (or point at a fresh
// `/api/livekit/token` response) if the token has expired.
//
// Run:  flutter test integration_test/livekit_room_test.dart -d linux
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:logging/logging.dart' as logging;

import 'package:watchparty/livekit/livekit_room.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  logging.Logger.root.level = logging.Level.ALL;
  logging.Logger.root.onRecord.listen((r) {
    // ignore: avoid_print
    print('[LK-LOG] ${r.loggerName} ${r.level.name}: ${r.message}');
  });
  // A benign flutter_webrtc teardown race ("No active stream to cancel" on
  // an EventChannel during peer-connection disposal) surfaces as a platform
  // exception through FlutterError.onError; it does not affect connect /
  // publish correctness (same underlying libwebrtc path the spike proved
  // works interactively). Log it instead of failing the test on it.
  final previousOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    final exception = details.exception;
    if (exception is PlatformException &&
        exception.message == 'No active stream to cancel') {
      // ignore: avoid_print
      print('[LK-LOG] ignoring benign teardown PlatformException: $exception');
      return;
    }
    previousOnError?.call(details);
  };

  testWidgets('connects to LiveKit and publishes a local camera track',
      (tester) async {
    final lines =
        await File('/tmp/wp-spike-livekit.txt').readAsLines();
    final url = lines[0].trim();
    final token = lines[1].trim();
    expect(url, isNotEmpty);
    expect(token, isNotEmpty);

    final service = LiveKitRoomService();
    final snapshots = <LiveKitRoomSnapshot>[];
    final sub = service.snapshots.listen(snapshots.add);

    await service.connect(url, token);

    // Pump until the room reaches `connected` and a local camera track shows
    // up in the snapshot (up to ~20s, matching the spike's observed timing).
    var connectedWithCamera = false;
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 250));
      await Future<void>.delayed(const Duration(milliseconds: 250));
      final s = service.snapshot;
      final local = s.participants.where((p) => p.isLocal);
      if (s.connected &&
          local.isNotEmpty &&
          local.first.videoTrack != null &&
          !local.first.videoMuted) {
        connectedWithCamera = true;
        break;
      }
    }

    expect(service.snapshot.connectionState, lk.ConnectionState.connected,
        reason: 'room never reached connected; '
            'last error=${service.snapshot.error}');
    expect(connectedWithCamera, isTrue,
        reason: 'local camera track never published; '
            'last snapshot=${service.snapshot.participants}');

    // Deliberately skip disconnect/dispose here: a known flutter_webrtc
    // teardown race (an EventChannel "No active stream to cancel"
    // PlatformException fired from native code after peer-connection
    // disposal) surfaces asynchronously and would otherwise fail this test
    // for a reason unrelated to what's under test (connect + publish). The
    // process exiting at the end of `flutter test` tears the room down.
    await sub.cancel();
  }, timeout: const Timeout(Duration(minutes: 2)));
}
