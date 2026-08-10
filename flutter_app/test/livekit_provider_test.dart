import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/livekit/livekit_room.dart';
import 'package:watchparty/state/livekit_provider.dart';

class _FailingLiveKitService extends LiveKitRoomService {
  @override
  Future<void> connect(
    String url,
    String token, {
    bool enableMic = false,
    bool enableCamera = false,
  }) async {
    throw StateError('connection failed');
  }
}

void main() {
  test('connect records and rethrows failures', () async {
    final notifier = LiveKitNotifier(_FailingLiveKitService());
    addTearDown(notifier.dispose);

    await expectLater(
      notifier.connect('ws://livekit.test', 'token'),
      throwsStateError,
    );

    expect(notifier.state.connected, isFalse);
    expect(notifier.state.connecting, isFalse);
    expect(notifier.state.error, contains('LiveKit'));
  });

  test(
    'disconnect emits an empty disconnected snapshot without a room',
    () async {
      final service = LiveKitRoomService();
      addTearDown(service.dispose);
      final snapshot = service.snapshots.first;

      await service.disconnect();

      final disconnected = await snapshot;
      expect(disconnected.connected, isFalse);
      expect(disconnected.participants, isEmpty);
      expect(disconnected.micEnabled, isFalse);
      expect(disconnected.cameraEnabled, isFalse);
    },
  );
}
