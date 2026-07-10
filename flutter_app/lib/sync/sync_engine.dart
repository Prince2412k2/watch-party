import 'dart:async';

import '../models/party_state.dart';
import '../net/socket_client.dart';
import '../player/player_controller.dart';

/// FROZEN CONTRACT (PLAN §3.4). The host-authority sync engine binds a
/// [PlayerController] to a [SocketClient] and keeps local playback locked onto
/// the server's shared [SyncSchedule]. E5.1 implements the real drift-correction
/// / applying-guard algorithm (ported from the web `useSyncPlay`); Phase 0 ships
/// only the interface + a passive mock.
abstract class SyncEngine {
  /// Begin driving [player] from [socket] for the given party. [canControl]
  /// gates whether local user gestures author sync commands (host / collaborative).
  Future<void> attach({
    required PlayerController player,
    required SocketClient socket,
    required String partyId,
    required bool canControl,
  });

  /// Stop syncing and detach listeners (does not dispose the player/socket).
  Future<void> detach();

  /// Whether local gestures currently author sync commands.
  bool get canControl;
  set canControl(bool value);

  // ── Local user intents (only take effect when [canControl]) ────────────
  Future<void> requestPlay();
  Future<void> requestPause();
  Future<void> requestSeek(Duration position);

  /// The last schedule the engine applied.
  SyncSchedule get currentSchedule;

  /// Emits every schedule the engine applies locally.
  Stream<SyncSchedule> get scheduleStream;

  /// Current measured drift between local playback and the shared timeline.
  Stream<Duration> get drift;
}

/// No-op mock: reflects schedules it receives via [applySchedule] and echoes
/// intents to the socket, so party UI (E5.2/5.3) can be built before the real
/// engine lands. It does NOT perform drift correction.
class MockSyncEngine implements SyncEngine {
  PlayerController? _player;
  SocketClient? _socket;
  // ignore: unused_field
  String? _partyId; // stored for the real E5 engine; unused in the mock
  bool _canControl = false;

  final _scheduleCtrl = StreamController<SyncSchedule>.broadcast();
  final _driftCtrl = StreamController<Duration>.broadcast();
  SyncSchedule _schedule = const SyncSchedule();

  @override
  Future<void> attach({
    required PlayerController player,
    required SocketClient socket,
    required String partyId,
    required bool canControl,
  }) async {
    _player = player;
    _socket = socket;
    _partyId = partyId;
    _canControl = canControl;
  }

  @override
  Future<void> detach() async {
    _player = null;
    _socket = null;
    _partyId = null;
  }

  /// Test/E5 hook: apply an incoming schedule (loosely mirrors it onto the player).
  Future<void> applySchedule(SyncSchedule schedule) async {
    _schedule = schedule;
    _scheduleCtrl.add(schedule);
    final player = _player;
    if (player == null) return;
    if (schedule.paused) {
      await player.pause();
    } else {
      await player.play();
    }
  }

  @override
  bool get canControl => _canControl;
  @override
  set canControl(bool value) => _canControl = value;

  @override
  Future<void> requestPlay() async {
    if (_canControl) _socket?.emit('sync:play', {'positionTicks': 0});
  }

  @override
  Future<void> requestPause() async {
    if (_canControl) _socket?.emit('sync:pause', {'positionTicks': 0});
  }

  @override
  Future<void> requestSeek(Duration position) async {
    if (_canControl) {
      _socket?.emit('sync:seek',
          {'positionTicks': position.inMilliseconds * 10000});
    }
  }

  @override
  SyncSchedule get currentSchedule => _schedule;

  @override
  Stream<SyncSchedule> get scheduleStream => _scheduleCtrl.stream;

  @override
  Stream<Duration> get drift => _driftCtrl.stream;
}
